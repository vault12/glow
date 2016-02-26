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

  # storage master key arrives from HW storage
  # Returns a Promise
  new: (id, strMasterKey = null)->
    if strMasterKey
      key = Keys.fromString strMasterKey
      next = CryptoStorage.new(key, id).then (storage)=>
        @storage = storage
    if !@storage
      next = CryptoStorage.new(null, id).then (storage)=>
        @storage = storage
    next.then =>
      @_ensureKeys()

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

  # Returns a Promise
  _loadGuestKeys: ->
    @storage.get('guest_registry').then (registry)=>
      @registry = registry or []
      @guestKeys = {} # tag -> { pk, hpk }
      @guestKeyTimeouts = {}
    next = Utils.resolve()
    for r in @registry
      next = next.then =>
        @storage.get("guest[#{r}]").then (val)=>
          @guestKeys[r] = val
    next

  # Returns a Promise
  commFromSeed: (seed)->
    Nacl.encode_utf8(seed).then (encoded)=>
      Nacl.fromSeed(encoded).then (commKey)=>
        @commKey = commKey
        @storage.save('comm_key', @commKey.toString())

  # Returns a Promise
  commFromSecKey: (rawSecKey)->
    @commKey = Nacl.fromSecretKey rawSecKey
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

  # Synchronous
  _addRegistry: (strGuestTag)->
    Utils.ensure(strGuestTag)
    @registry.push(strGuestTag) unless @registry.indexOf(strGuestTag) > -1

  # Returns a Promise
  _saveNewGuest: (tag, pk)->
    Utils.ensure(tag and pk)
    @storage.save("guest[#{tag}]", pk).then =>
      @storage.save('guest_registry', @registry)

  # Returns a Promise
  _removeGuestRecord: (tag)->
    Utils.ensure(tag)
    @storage.remove("guest[#{tag}]").then =>
      i = @registry.indexOf tag
      if i > -1
        @registry.splice(i, 1)
        @storage.save('guest_registry', @registry)

  # Returns a Promise
  addGuest: (strGuestTag, b64_pk)->
    Utils.ensure(strGuestTag and b64_pk)
    b64_pk = b64_pk.trimLines()
    @_addRegistry strGuestTag
    @_addGuestRecord(strGuestTag, b64_pk).then (guest)=>
      @_saveNewGuest(strGuestTag, guest)

  # Returns a Promise
  _addGuestRecord: (strGuestTag, b64_pk)->
    Utils.ensure(strGuestTag, b64_pk)
    Nacl.h2(b64_pk.fromBase64()).then (h2)=>
      @guestKeys[strGuestTag] =
        pk: b64_pk
        hpk: h2.toBase64()

  # Synchronous
  addTempGuest: (strGuestTag,strPubKey)->
    Utils.ensure(strGuestTag and strPubKey)
    strPubKey = strPubKey.trimLines()
    @guestKeys[strGuestTag] = strPubKey
    if @guestKeyTimeouts[strGuestTag]
      clearTimeout @guestKeyTimeouts[strGuestTag]
    @guestKeyTimeouts[strGuestTag] = Utils.delay Config.RELAY_SESSION_TIMEOUT, =>
      delete @guestKeys[strGuestTag]
      delete @guestKeyTimeouts[strGuestTag]
      @emit 'tmpguesttimeout', strGuestTag

  # Returns a Promise
  removeGuest: (strGuestTag)->
    Utils.ensure(strGuestTag and @guestKeys[strGuestTag])
    @guestKeys[strGuestTag] = null # erase the pointer just in case
    delete @guestKeys[strGuestTag]
    @_removeGuestRecord strGuestTag

  # Synchronous
  getGuestKey: (strGuestTag)->
    Utils.ensure(strGuestTag and @guestKeys[strGuestTag])
    new Keys
      boxPk: @getGuestRecord(strGuestTag).fromBase64()

  # Synchronous
  getGuestRecord: (strGuestTag)->
    Utils.ensure(strGuestTag and @guestKeys[strGuestTag])
    @guestKeys[strGuestTag].pk

  # have to call with overseerAuthorized as true for extra safety
  # Returns a Promise
  selfDestruct: (overseerAuthorized)->
    Utils.ensure(overseerAuthorized)
    rcopy = @registry.slice()
    @removeGuest g for g in rcopy
    @storage.remove('guest_registry').then =>
      @storage.remove('comm_key').then =>
        @storage.selfDestruct(overseerAuthorized)

module.exports = KeyRing
window.KeyRing = KeyRing if window.__CRYPTO_DEBUG
