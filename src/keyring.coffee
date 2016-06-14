# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config        = require 'config'
CryptoStorage = require 'crypto_storage'
Keys          = require 'keys'
Nacl          = require 'nacl'
Utils         = require 'utils'
EventEmitter  = require('events').EventEmitter

# Manages the public keys of correspondents
class KeyRing extends EventEmitter

  # Construction:
  # KeyRing.new(..params..).then (kr)=>
  #   kr is ready to be used here

  # storage master key arrives from HW storage
  # Returns a Promise
  @new: (id, strMasterKey = null)->
    kr = new KeyRing
    if strMasterKey
      key = Keys.fromString(strMasterKey)
      next = CryptoStorage.new(key, id).then (storage)=>
        kr.storage = storage
    else
      next = CryptoStorage.new(null, id).then (storage)=>
        kr.storage = storage
    next.then =>
      kr._ensureKeys().then =>
        kr

  # make sure we have all basic keys created
  # Returns a Promise
  _ensureKeys: ->
    @_loadCommKey().then =>
      @_loadGuestKeys()

  # Returns a Promise
  _loadCommKey: ->
    @getKey('comm_key').then (commKey)=>
      @commKey = commKey
      return if @commKey
      Nacl.makeKeyPair().then (commKey)=>
        @commKey = commKey
        @saveKey('comm_key', @commKey)

  getNumberOfGuests: ->
    Object.keys(@guestKeys or {}).length

  # Returns a Promise
  _loadGuestKeys: ->
    @storage.get('guest_registry').then (guestKeys)=>
      @guestKeys = guestKeys or {} # tag -> { pk, hpk }
      @guestKeyTimeouts = {}

  # Returns a Promise
  commFromSeed: (seed)->
    Nacl.encode_utf8(seed).then (encoded)=>
      Nacl.fromSeed(encoded).then (commKey)=>
        @commKey = commKey
        @storage.save('comm_key', @commKey.toString())

  # Returns a Promise
  commFromSecKey: (rawSecKey)->
    Nacl.fromSecretKey(rawSecKey).then (commKey)=>
      @commKey = commKey
      @storage.save('comm_key', @commKey.toString())

  # Synchronous
  tagByHpk: (hpk)->
    for own k, v of @guestKeys
      return k if hpk is v.hpk
    null

  # Synchronous
  getMasterKey: ->
    @storage.storageKey.key2str('key') # to b64 string

  # Synchronous
  getPubCommKey: ->
    @commKey.strPubKey()

  # Returns a Promise
  saveKey: (tag, key)->
    @storage.save(tag, key.toString()).then ->
      key

  # Returns a Promise
  getKey: (tag)->
    @storage.get(tag).then (k)->
      if k then Keys.fromString(k) else null

  # Returns a Promise
  deleteKey: (tag)->
    @storage.remove(tag)

  # Returns a Promise
  _saveNewGuest: (tag, pk)->
    Utils.ensure(tag and pk)
    @storage.save('guest_registry', @guestKeys)

  # Returns a Promise
  addGuest: (strGuestTag, b64_pk)->
    Utils.ensure(strGuestTag and b64_pk)
    b64_pk = b64_pk.trimLines()
    # @_addRegistry strGuestTag
    @_addGuestRecord(strGuestTag, b64_pk).then (guest)=>
      @_saveNewGuest(strGuestTag, guest)

  # Returns a Promise
  _addGuestRecord: (strGuestTag, b64_pk)->
    Utils.ensure(strGuestTag, b64_pk)
    Nacl.h2(b64_pk.fromBase64()).then (h2)=>
      @guestKeys[strGuestTag] =
        pk: b64_pk
        hpk: h2.toBase64()

  timeToGuestExpiration: (strGuestTag)->
    Utils.ensure(strGuestTag)
    entry = @guestKeyTimeouts[strGuestTag]
    return 0 if not timeoutEntry
    Math.max(Config.RELAY_SESSION_TIMEOUT - (Date.now() - entry.startTime), 0)

  # Synchronous
  addTempGuest: (strGuestTag, strPubKey)->
    Utils.ensure(strGuestTag, strPubKey)
    strPubKey = strPubKey.trimLines()
    Nacl.h2(strPubKey.fromBase64()).then (h2)=>
      @guestKeys[strGuestTag] =
        pk: strPubKey
        hpk: h2.toBase64()
      if @guestKeyTimeouts[strGuestTag]
        clearTimeout @guestKeyTimeouts[strGuestTag].timeoutId
      @guestKeyTimeouts[strGuestTag] =
        timeoutId: Utils.delay Config.RELAY_SESSION_TIMEOUT, =>
          delete @guestKeys[strGuestTag]
          delete @guestKeyTimeouts[strGuestTag]
          @emit 'tmpguesttimeout', strGuestTag
        startTime: Date.now()

  # Returns a Promise
  removeGuest: (strGuestTag)->
    Utils.ensure(strGuestTag)
    return Utils.resolve() unless @guestKeys[strGuestTag]
    delete @guestKeys[strGuestTag]
    @storage.save('guest_registry', @guestKeys)

  # Synchronous
  getGuestKey: (strGuestTag)->
    Utils.ensure(strGuestTag)
    return null unless @guestKeys[strGuestTag]
    new Keys
      boxPk: @getGuestRecord(strGuestTag).fromBase64()

  # Synchronous
  getGuestRecord: (strGuestTag)->
    Utils.ensure(strGuestTag)
    return null unless @guestKeys[strGuestTag]
    @guestKeys[strGuestTag].pk

  # have to call with overseerAuthorized as true for extra safety
  # Returns a Promise
  selfDestruct: (overseerAuthorized)->
    Utils.ensure(overseerAuthorized)
    @storage.remove('guest_registry').then =>
      @storage.remove('comm_key').then =>
        @storage.selfDestruct(overseerAuthorized)

module.exports = KeyRing
window.KeyRing = KeyRing if window.__CRYPTO_DEBUG
