# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config = require 'config'
Keys = require 'keys'
Nacl = require 'nacl'
Utils = require 'utils'

# Secure local storage
class CryptoStorage

  # Construction:
  # CryptoStorage.new(..params..).then (storage)=>
  #   storage is ready to be used here

  _storageDriver: null

  # Keys are tagged in local storage with a versioned prefix
  # Synchronous
  tag: (strKey)->
    strKey and strKey + @root

  # Changing roots allows different versions to keep separate storage areas
  # Returns a Promise
  @new: (storageKey = null, r = null)->
    cs = new CryptoStorage
    cs.storageKey = storageKey
    cs.root = if r then ".#{r}#{Config._DEF_ROOT}" else Config._DEF_ROOT
    # TODO: move storage key to hw and provide it in ctor call
    unless cs.storageKey
      cs._loadKey().then ->
        unless cs.storageKey
          # If we don't have a loaded storageKey, make a new one
          cs.newKey().then ->
            cs
        else
          cs
    else
      Utils.resolve(cs)

  # Returns a Promise
  _saveKey: ->
    @_set(Config._SKEY_TAG, @storageKey.toString())

  # Returns a Promise
  _loadKey: ->
    @_get(Config._SKEY_TAG).then (keyStr)=>
      @setKey(Keys.fromString(keyStr)) if keyStr

  # have to call with overseerAuthorized as true for extra safety
  # Returns a Promise
  selfDestruct: (overseerAuthorized)->
    Utils.ensure(overseerAuthorized)
    @_localRemove(@tag(Config._SKEY_TAG))

  # Returns a Promise
  setKey: (objStorageKey)->
    @storageKey = objStorageKey
    @_saveKey()

  # Returns a Promise
  newKey: ->
    Nacl.makeSecretKey().then (key)=>
      @setKey(key)

  # main storage functions

  # Returns a Promise
  save: (strTag, data)->
    Utils.ensure(strTag)
    # let's convert the data to JSON, then make that string a byte array
    data = JSON.stringify(data)
    Nacl.use().encode_utf8(data).then (data)=>
    # each data field saved generates its own nonce
      Nacl.use().crypto_secretbox_random_nonce().then (nonce)=>
        Nacl.use().crypto_secretbox(data, nonce, @storageKey.key).then (aCText)=>
          # save the chipher text and nonce for this save op
          # @_set(strTag, aCText.toBase64()).then =>
          #   @_set("#{Config._NONCE_TAG}.#{strTag}", nonce.toBase64()).then =>
          #     true # signal success
          @_multiSet(strTag, aCText.toBase64(),
            "#{Config._NONCE_TAG}.#{strTag}", nonce.toBase64()).then =>
            true # signal success

  # Returns a Promise
  get: (strTag)->
    @_get(strTag).then (ct)=> # get cipher text by storage tag
      return null unless ct # nothing to do without cipher text
      @_get("#{Config._NONCE_TAG}.#{strTag}").then (nonce)=>
        return null unless nonce # nothing to do without nonce
        # covert cipher text to arrays from base64 in local storage
        Nacl.use().crypto_secretbox_open(ct.fromBase64(), nonce.fromBase64(),
          @storageKey.key).then (aPText)=>
          # restore JSON string from plain text array and parse it
          Nacl.use().decode_utf8(aPText).then (data)=>
            JSON.parse(data)

  # Returns a Promise
  remove: (strTag)->
    @_localRemove(@tag(strTag)).then =>
      @_localRemove(@tag("#{Config._NONCE_TAG}.#{strTag}")).then =>
        true

  # Private access functions for tagged read/write
  # Returns a Promise
  _get: (strTag)->
    @_localGet(@tag(strTag))

  # Returns a Promise
  _set: (strTag, strData)->
    Utils.ensure(strTag)
    @_localSet(@tag(strTag), strData).then ->
      strData

  # Returns a Promise
  _multiSet: (strTag1, strData1, strTag2, strData2)->
    Utils.ensure(strTag1, strTag2)
    if @_storage().multiSet
      @_localMultiSet([ @tag(strTag1), strData1, @tag(strTag2), strData2 ])
    else
      @_set(strTag1, strData1).then =>
        @_set(strTag2, strData2)

  # Returns a Promise
  _localGet: (str)->
    @_storage().get(str)

  # Returns a Promise
  _localSet: (str, data)->
    @_storage().set(str, data)

  # Returns a Promise
  _localMultiSet: (pairs)->
    @_storage().multiSet(pairs)

  # Returns a Promise
  _localRemove: (str)->
    @_storage().remove(str)

  # Synchronous
  _storage: ()->
    CryptoStorage._storageDriver

  # Synchronous
  @startStorageSystem = (driver)->
    Utils.ensure(driver)
    @_storageDriver = driver

module.exports = CryptoStorage
