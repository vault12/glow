# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config        = require 'config'
KeyRing       = require 'keyring'
Nacl          = require 'nacl'
Utils         = require 'utils'
EventEmitter  = require('events').EventEmitter

# Mailbox service to connect with the Zax relay service
class MailBox extends EventEmitter

  # Construction:
  # MailBox.new(..params..).then (mbx)=>
  #   mbx is ready to be used here

  # Creates a new client Mailbox that will represent an hpk mailbox on the
  # relay. You can provide a friendly unique name to represent that Mailbox as
  # an *identity*. That name should be unique locally, since it's used as a
  # storage tag.

  # If your client supports dedicated cryptographic storage, you can keep the
  # master encryption key in that storage and provide it as strMasterKey.

  # All Mailbox storage calls will be symmetrically encrypted with that key.
  # Otherwise we will make a key for you, and save it in the same CryptoStorage
  # as the rest of of the data.
  # Returns a Promise
  @new: (identity, strMasterKey = null)->
    mbx = new MailBox()
    mbx.identity = identity
    mbx.sessionKeys = {}
    mbx.sessionTimeout = {}
    KeyRing.new(mbx.identity, strMasterKey).then (keyRing)->
      mbx.keyRing = keyRing
      # setup the nonce counter here to avoid any chance of races between
      # late init from storage and direct get from instance.
      mbx.keyRing.storage.get('_nonce_counter').then (_nonceCounter)->
        if _nonceCounter
          mbx._nonceCounter = _nonceCounter.fromBase64()
          mbx
        else
          mbx._nonceCounter = new Uint8Array(24)
          mbx.keyRing.storage.save('_nonce_counter', mbx._nonceCounter.toBase64()).then ->
            mbx

  # You can create a Mailbox where the secret identity key is derived from a
  # well-known seed.
  # Returns a Promise
  @fromSeed: (seed, id = seed, strMasterKey = null)->
    @new(id, strMasterKey).then (mbx)=>
      mbx.keyRing.commFromSeed(seed).then =>
        mbx._hpk = null
        mbx

  # You can also create a Mailbox if you already know the secret identity key
  # Returns a Promise
  @fromSecKey: (secKey, id, strMasterKey = null)->
    @new(id, strMasterKey).then (mbx)=>
      mbx.keyRing.commFromSecKey(secKey).then =>
        mbx._hpk = null
        mbx

  # --- Mailbox keys ---
  # This is the HPK (hash of the public key) of your mailbox. This is what Zax
  # Relays use as the universal address of your mailbox.
  # Returns a Promise
  hpk: ->
    return Utils.resolve(@_hpk) if @_hpk
    Nacl.h2(@keyRing.commKey.boxPk).then (hpk)=>
      @_hpk = hpk

  # This is your public identity and default communication key. Your
  # correspondents can know it, whereas Relays do not need it (other than
  # temporarily for internal use during the ownership proof)
  # Synchronous
  getPubCommKey: ->
    @keyRing.getPubCommKey()

  # Allows for preemptive session renewal to avoid
  # timeouts in the middle of a relay check
  # Synchronous
  timeToSessionExpiration: (sess_id)->
    session = @sessionTimeout[sess_id]
    return 0 if not session
    sesExp = Math.max(Config.RELAY_SESSION_TIMEOUT - (Date.now() - session.startTime), 0)
    guExp = @keyRing.timeToGuestExpiration(sess_id)
    Math.min(sesExp, guExp)

  # Each session with each Zax Relay creates its own temporary session keys
  # Returns a Promise
  createSessionKey: (sess_id, forceNew = false)->
    Utils.ensure(sess_id)
    return Utils.resolve(@sessionKeys[sess_id]) if not forceNew and @sessionKeys[sess_id]
    # cancel the previous timer to prevent erase of a newly created session key
    # if createSessionKey() is called repeatedly with the same sess_id
    if @sessionTimeout[sess_id]
      clearTimeout @sessionTimeout[sess_id].timeoutId
    Nacl.makeKeyPair().then (key)=>
      @sessionKeys[sess_id] = key
      # Remove key material after it expires on the relay
      @sessionTimeout[sess_id] =
        timeoutId: Utils.delay Config.RELAY_SESSION_TIMEOUT, => @_clearSession(sess_id)
        startTime: Date.now()
      key

  # Synchronous
  _clearSession: (sess_id)->
    @sessionKeys[sess_id] = null
    delete @sessionKeys[sess_id]
    @sessionTimeout[sess_id] = null
    delete @sessionTimeout[sess_id]
    @emit('relaysessiontimeout', sess_id)

  # Locally determine whether Relay.connectMailbox() needs to be called
  # Synchronous
  isConnectedToRelay: (relay)->
    Utils.ensure(relay)
    relayId = relay.relayId()
    Boolean(@sessionKeys[relayId]) and Boolean(@_gPk(relayId))

  # --- Low level encoding/decoding ---

  # Returns a Promise
  rawEncodeMessage: (msg, pkTo, skFrom, nonceData = null)->
    Utils.ensure(msg, pkTo, skFrom)
    @_makeNonce(nonceData).then (nonce)=>
      @_parseData(msg).then (data)=>
        Nacl.use().crypto_box(data, nonce, pkTo, skFrom).then (ctext)=>
          nonce: nonce.toBase64()
          ctext: ctext.toBase64()

  # Returns a Promise
  rawDecodeMessage: (nonce, ctext, pkFrom, skTo)->
    Utils.ensure(nonce, ctext, pkFrom, skTo)
    Nacl.use().crypto_box_open(ctext, nonce, pkFrom, skTo).then (data)->
      Nacl.use().decode_utf8(data).then (utf8)->
        JSON.parse(utf8)

  # Encodes a free-form object *msg* to the guest key of a guest already
  # added to our keyring. If the session flag is set, we will look for keys in
  # temporary, not the persistent collection of session keys. skTag lets you
  # specifiy the secret key in a key ring
  # Returns a Promise
  encodeMessage: (guest, msg, session = false, skTag = null)->
    Utils.ensure(guest, msg)
    throw new Error("encodeMessage: don't know guest #{guest}") unless (gpk = @_gPk(guest))
    sk = @_getSecretKey(guest, session, skTag)

    # TODO: add whatever neccesary int32 id/counter logic and provide nonceData as last param
    # That int32 (on receive/decode) can be restored via _nonceData()
    @rawEncodeMessage(msg, gpk, sk)

  # Decodes a ciphertext from a guest key already in our keyring with this
  # nonce. If session flag is set, looks for keys in temporary, not the
  # persistent collection of session keys. skTag (optional) lets you specify
  # the secret key in a key ring
  # Returns a Promise
  decodeMessage: (guest, nonce, ctext, session = false, skTag = null)->
    Utils.ensure(guest, nonce, ctext)
    throw new Error("decodeMessage: don't know guest #{guest}") unless (gpk = @_gPk(guest))
    sk = @_getSecretKey(guest, session, skTag)
    @rawDecodeMessage(nonce.fromBase64(), ctext.fromBase64(), gpk, sk)

  # Establishes a session, exchanges temp keys and proves our ownership of this
  # Mailbox to this specific relay. This is the first function to start
  # communications with any relay.
  # Returns a Promise
  connectToRelay: (relay)->
    Utils.ensure(relay)
    relay.openConnection().then =>
      relay.connectMailbox(@)

  # --- Initial communications ---
  # If we are not connected to a relay, we can still send a message (free form
  # object) to a specific guest in our keyring. This call will first establish
  # a connection to a relay and then send the first message via that relay.
  # Returns a Promise
  sendToVia: (guest, relay, msg)->
    Utils.ensure(guest, relay, msg)
    @connectToRelay(relay).then =>
      @relaySend(guest, msg, relay)

  # If we are not connected to a relay, we can still get pending messages for
  # us from that relay. This call will first establish a connection to a relay
  # and download messages. Result will be populated with an array of
  # messages and download meta-data about those messages.
  # Returns a Promise(messages)
  getRelayMessages: (relay)->
    Utils.ensure(relay)
    @connectToRelay(relay).then =>
      @relayMessages(relay)

  # --- Established communication functions ---
  # Once a connection with a relay is established there is no need to create
  # new sessions. These 4 functions allow us to issue all 4 relay commands
  # using previously established connections to a relay

  # Gets pending messages count and returns the result
  # Returns a Promise(count)
  relayCount: (relay)->
    Utils.ensure(relay)
    relay.count(@).then (result)=>
      parseInt(result)

  # Gets the status of previous sent message as redis TTL:
  # -2 : missing key
  # -1 : key never expires
  # 0+ : key time to live in seconds
  # Returns a Promise(ttl)
  relay_msg_status: (relay, storage_token) ->
    Utils.ensure(relay)
    relay.message_status(@,storage_token).then (ttl) =>
      ttl

  # Sends a free-form object to a guest we already have in our keyring
  # Returns a Promise
  relaySend: (guest, msg, relay)->
    Utils.ensure(relay)
    @encodeMessage(guest, msg).then (encMsg)=>
      Nacl.h2(@_gPk(guest)).then (h2)=>
        relay.upload(@, h2, encMsg)

  # Downloads pending relay messages
  # Returns a Promise(messages)
  relayMessages: (relay)->
    Utils.ensure(relay)
    relay.download(@).then (result)=>
      Utils.all result.map (emsg)=>
        if (tag = @keyRing.tagByHpk(emsg.from))
          emsg['fromTag'] = tag
          @decodeMessage(tag, emsg.nonce, emsg.data).then (msg)=>
            if msg
              emsg['msg'] = msg
              delete emsg.data
            emsg
        else
          emsg

  # Maps the list of nonces of current messages on the relay. Since nonces are
  # forced to be unique, they are used as global message ids for a given mailbox.
  # Synchronous
  relayNonceList: (download)->
    Utils.ensure(download)
    Utils.map download, (i) -> i.nonce

  # Deletes messages from the relay given a list of message nonces.
  # Returns a Promise
  relayDelete: (list, relay)->
    Utils.ensure(list, relay)
    relay.delete(@, list)

  # Deletes up to the first 100 messages from the relay for a given mailbox.
  # Returns a Promise
  clean: (relay)->
    Utils.ensure(relay)
    @getRelayMessages(relay).then (download)=>
      @relayDelete(@relayNonceList(download), relay)

  # Deletes a Mailbox and all its data from local CryptoStorage. This is a very
  # destructive operation, use with caution - it will also delete the Mailbox
  # keyring along with all stored public keys. To restore that information, you
  # will need to do another key exchange with all the guests on your keyring.
  # Returns a Promise
  selfDestruct: (overseerAuthorized)->
    Utils.ensure(overseerAuthorized)
    @keyRing.storage.remove('_nonce_counter').then =>
      @keyRing.selfDestruct(overseerAuthorized)

  # --- Protected helpers ---

  # Get a guest key pair by id
  # Synchronous
  _gKey: (strId)->
    Utils.ensure(strId)
    @keyRing.getGuestKey(strId)

  # Get a guest public key by id
  # Synchronous
  _gPk: (strId)->
    Utils.ensure(strId)
    @_gKey(strId)?.boxPk

  # Returns a Promise(hash)
  _gHpk: (strId)->
    Utils.ensure(strId)
    Nacl.h2(@_gPk(strId))

  # Synchronous
  _getSecretKey: (guest, session, skTag)->
    unless skTag
      return if session then @sessionKeys[guest].boxSk else @keyRing.commKey.boxSk
    else
      # In this case we use the key ring to store temp secret keys
      return @_gPk skTag

  # Converts any object into Uint8Array
  # Returns a Promise
  _parseData: (data)->
    return Utils.resolve(data) if Utils.type(data) is 'Uint8Array'
    Nacl.use().encode_utf8(JSON.stringify(data))

  # Makes a timestamp nonce that a relay expects for any crypto operations.
  # timestamp is the first 8 bytes, the rest is random, unless custom 'data'
  # is specified. 'data' will be packed as next 4 bytes after timestamp
  # Returns a Promise
  _makeNonce: (data = null, time = Date.now())->
    Nacl.use().crypto_box_random_nonce().then (nonce)->
      throw new Error('RNG failed, try again?') unless nonce? and nonce.length is 24

      # split timestamp integer as an array of bytes
      headerLen = 8  # max timestamp size
      aTime = Utils.itoa(parseInt(time/1000))

      if data
        aData = Utils.itoa(data)
        headerLen += 4 # extra 4 bytes for custom data

      # zero out nonce header area
      nonce[i] = 0 for i in [0...headerLen]

      # copy the timestamp into the first 8 bytes of nonce
      nonce[8 - aTime.length + i] = aTime[i] for i in [0..(aTime.length - 1)]
      # copy data if present
      nonce[12 - aData.length + i] = aData[i] for i in [0..(aData.length - 1)] if data
      nonce

  _nonceData: (nonce) ->
    Utils.atoi nonce.subarray(8,12)


module.exports = MailBox
window.MailBox = MailBox if window.__CRYPTO_DEBUG
