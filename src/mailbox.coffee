# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config        = require 'config'
KeyRing       = require 'keyring'
Nacl          = require 'nacl'
Utils         = require 'utils'

# Mailbox service to connect with the Zax relay service
class MailBox

  # Creates a new client Mailbox that will represent an hpk mailbox on the
  # relay. You can provide a friendly unique name to represent that Mailbox as
  # an *identity*. That name should be unique locally, since it's used as a
  # storage tag.

  # If your client supports dedicated cryptographic storage, you can keep the
  # master encryption key in that storage and provide it as strMasterKey.

  # All Mailbox storage calls will be symmetrically encrypted with that key.
  # Otherwise we will make a key for you, and save it in the same CryptoStorage
  # as the rest of of the data.
  constructor: (@identity, strMasterKey = null) ->
    @keyRing = new KeyRing(@identity, strMasterKey)
    @session_keys = {}
    @session_relay = {}
    @session_timeout = {}

  # You can create a Mailbox where the secret identity key is derived from a
  # well-known seed.
  @fromSeed: (seed, id = seed, strMasterKey = null) ->
    mbx = new MailBox(id, strMasterKey)
    mbx.keyRing.commFromSeed(id)
    mbx._hpk = null
    return mbx

  # You can also create a Mailbox if you already know the secret identity key
  @fromSecKey: (secKey, id, strMasterKey = null) ->
    mbx = new MailBox(id, strMasterKey)
    mbx.keyRing.commFromSecKey(secKey)
    mbx._hpk = null
    return mbx

  # --- Mailbox keys ---
  # This is the HPK (hash of the public key) of your mailbox. This is what Zax
  # Relays use as the universal address of your mailbox.
  hpk: ->
    return @_hpk if @_hpk
    @_hpk = Nacl.h2(@keyRing.comm_key.boxPk)

  # This is your public identity and default communication key. Your
  # correspondents can know it, whereas Relays do not need it (other than
  # temporarily for internal use during the ownership proof)
  getPubCommKey: ->
    @keyRing.getPubCommKey()

  # Each session with each Zax Relay creates its own temporary session keys
  createSessionKey: (sess_id) ->
    throw new Error('createSessionKey - no sess_id') unless sess_id
    return @session_keys[sess_id] if @session_keys[sess_id]?
    @session_keys[sess_id] = Nacl.makeKeyPair()

    # Remove key material after it expires on the relay
    @session_timeout[sess_id] = Utils.delay Config.RELAY_SESSION_TIMEOUT, =>
      @session_keys[sess_id] = null
      delete @session_keys[sess_id]

      @session_timeout[sess_id] = null
      delete @session_timeout[sess_id]

      @session_relay[sess_id] = null
      delete @session_relay[sess_id]

    return @session_keys[sess_id]

  # --- Low level encoding/decoding ---

  rawEncodeMessage: (msg, pkTo, skFrom) ->
    throw new Error('rawEncodeMessage: missing params') unless msg? and pkTo? and skFrom?
    nonce = @_make_nonce()
    return r =
      nonce: nonce.toBase64()
      ctext: Nacl.use().crypto_box(
        @_parseData(msg)
        nonce
        pkTo
        skFrom).toBase64()

  rawDecodeMessage: (nonce, ctext, pkFrom, skTo) ->
    throw new Error('rawEncodeMessage: missing params') unless nonce? and ctext? and pkFrom? and skTo?
    NC = Nacl.use()
    JSON.parse NC.decode_utf8 NC.crypto_box_open(ctext, nonce, pkFrom, skTo)

  # Encodes a free-form object *msg* to the guest key of a guest already
  # added to our keyring. If the session flag is set, we will look for keys in
  # temporary, not the persistent collection of session keys. skTag lets you
  # specifiy the secret key in a key ring
  encodeMessage: (guest, msg, session = false, skTag = null) ->
    throw new Error('encodeMessage: missing params') unless guest? and msg?
    throw new Error("encodeMessage: don't know guest #{guest}") unless (gpk = @_gPk guest)?
    sk = @_getSecretKey guest, session, skTag
    @rawEncodeMessage msg, gpk, sk

  # Decodes a ciphertext from a guest key already in our keyring with this
  # nonce. If session flag is set, looks for keys in temporary, not the
  # persistent collection of session keys. skTag (optional) lets you specify
  # the secret key in a key ring
  decodeMessage: (guest, nonce, ctext, session = false, skTag = null) ->
    throw new Error('decodeMessage: missing params') unless guest? and nonce? and ctext?
    throw new Error("decodeMessage: don't know guest #{guest}") unless (gpk = @_gPk guest)?
    sk = @_getSecretKey guest, session, skTag
    @rawDecodeMessage nonce.fromBase64(), ctext.fromBase64(), gpk, sk

  # Establishes a session, exchanges temp keys and proves our ownership of this
  # Mailbox to this specific relay. This is the first function to start
  # communications with any relay.
  connectToRelay: (relay) ->
    relay.openConnection().then =>
      relay.connectMailbox(@).then =>
        @lastRelay = relay

  # --- Initial communications ---
  # If we are not connected to a relay, we can still send a message (free form
  # object) to a specific guest in our keyring. This call will first establish
  # a connection to a relay and then send the first message via that relay.
  sendToVia: (guest, relay, msg) ->
    @connectToRelay(relay).then =>
      @relay_send(guest, msg, relay)

  # If we are not connected to a relay, we can still get pending messages for
  # us from that relay. This call will first establish a connection to a relay
  # and download messages. @lastDownload will be populated with an array of
  # messages and download meta-data about those messages.
  getRelayMessages: (relay) ->
    @connectToRelay(relay).then =>
      @relay_messages()

  # --- Established communication functions ---
  # Once a connection with a relay is established there is no need to create
  # new sessions. These 4 functions allow us to issue all 4 relay commands
  # using previously established connections to a relay stored in @lastRelay

  # Gets pending messages count and stores it in @count
  relay_count: ->
    throw new Error('relay_count - no open relay') unless @lastRelay
    @lastRelay.count(@).then =>
      @count = parseInt @lastRelay.result

  # Sends a free-form object to a guest whose keys we already have in our
  # keyring via @lastRelay
  relay_send: (guest, msg) ->
    throw new Error('mbx: relay_send - no open relay') unless @lastRelay
    enc_msg = @encodeMessage(guest, msg)
    @lastMsg = enc_msg
    @lastRelay.upload(@,Nacl.h2(@_gPk guest), enc_msg)

  # Downloads pending relay messages into @lastDownload
  relay_messages: ->
    throw new Error('relay_messages - no open relay') unless @lastRelay
    @lastRelay.download(@).then =>
      @lastDownload = []
      for emsg in @lastRelay.result
        if (tag = @keyRing.tagByHpk emsg.from)
          emsg['fromTag'] = tag
          emsg['msg'] = @decodeMessage tag, emsg.nonce, emsg.data
          delete emsg.data if emsg['msg']?
        @lastDownload.push emsg

  # If @downloadMeta has been populated by previous calls, this maps the list
  # of nonces of current messages on the relay. Since nonces are forced to be
  # unique, they are used as global message ids for a given mailbox
  relay_nonce_list: ->
    throw new Error('relay_nonce_list - no metadata') unless @lastDownload
    Utils.map @lastDownload, (i) -> i.nonce

  # Deletes messages from the relay given a list of message nonces.
  relay_delete: (list) ->
    throw new Error('relay_delete - no open relay') unless @lastRelay
    @lastRelay.delete(@, list)

  # Calls @relay_delete @relay_nonce_list: deletes up to the first 100 messages
  # from the relay for a given mailbox.
  clean: (r) ->
    @getRelayMessages(r).then =>
      @relay_delete(@relay_nonce_list())

  # Deletes a Mailbox and all its data from local CryptoStorage. This is a very
  # destructive operation, use with caution - it will also delete the Mailbox
  # keyring along with all stored public keys. To restore that information, you
  # will need to do another key exchange with all the guests on your keyring.
  selfDestruct: (overseerAuthorized) ->
    return null unless overseerAuthorized
    @keyRing.selfDestruct(overseerAuthorized)

  # --- Protected helpers ---

  # Get a guest key pair by id
  _gKey: (strId) ->
    return null unless strId
    @keyRing.getGuestKey strId

  # Get a guest public key by id
  _gPk: (strId) ->
    return null unless strId
    @_gKey(strId)?.boxPk

  _gHpk: (strId) ->
    return null unless strId
    Nacl.h2 @_gPk strId

  _getSecretKey: (guest, session, skTag) ->
    unless skTag
      return if session then @session_keys[guest].boxSk else @keyRing.comm_key.boxSk
    else
      # In this case we use the key ring to store temp secret keys
      return @_gPk skTag

  # Converts any object into Uint8Array
  _parseData: (data) ->
    return data if Utils.type(data) is 'Uint8Array'
    Nacl.use().encode_utf8 JSON.stringify data

  # Makes a timestamp nonce that a relay expects for any crypto operations.
  # timestamp is the first 8 bytes, the rest is random
  _make_nonce: (time = parseInt(Date.now() / 1000)) ->
    nonce = Nacl.use().crypto_box_random_nonce()
    throw new Error('RNG failed, try again?') unless nonce? and nonce.length is 24

    # split timestamp integer as an array of bytes
    bytes = Utils.itoa time

    # copy the timestamp into the first 8 bytes of nonce
    nonce[i] = 0 for i in [0..7]
    nonce[8 - bytes.length + i] = bytes[i] for i in [0..(bytes.length - 1)]
    return nonce

module.exports = MailBox
window.MailBox = MailBox if window.__CRYPTO_DEBUG
