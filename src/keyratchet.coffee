# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

Nacl = require 'nacl'

class KeyRatchet

  # Last used key, we know other party has it
  lastKey: null

  # Confirmed key, we know other party just got it
  confirmedKey: null

  # Next key, we sending it to the other party. We
  # do not know when/if it will confirm it
  nextKey: null

  _roles: ['lastKey', 'confirmedKey', 'nextKey']

  constructor: (@id, @keyRing, firstKey = null) ->
    throw new Error('KeyRatchet - missing params') unless @id and @keyRing
    for s in @_roles
      @[s] = @keyRing.getKey(@keyTag s)
    @startRatchet firstKey if firstKey

  keyTag: (role) ->
    "#{role}_#{@id}"

  storeKey: (role) ->
    @keyRing.saveKey @keyTag(role), @[role]

  startRatchet: (firstKey) ->
    # If we dont have confirmed key to work with
    # we have to start ratched with a default key
    for k in ['confirmedKey', 'lastKey']
      unless @[k]
        @[k] = firstKey
        @storeKey k

    # create next ratchet key unless we already done so
    unless @nextKey
      @nextKey = Nacl.makeKeyPair()
      @storeKey 'nextKey'

  pushKey: (newKey) ->
    @lastKey = @confirmedKey
    @confirmedKey = @nextKey
    @nextKey = newKey
    @storeKey(s) for s in @_roles

  confKey: (newConfirmedKey) ->
    return false if @confirmedKey? and @confirmedKey.equal newConfirmedKey
    # console.log "Key confirmed: replacing in #{@id} | #{@confirmedKey.boxPk.toBase64()} with #{newConfirmedKey.boxPk.toBase64()}"
    @lastKey = @confirmedKey
    @confirmedKey = newConfirmedKey
    @storeKey(s) for s in ['lastKey', 'confirmedKey']
    return true

  curKey: ->
    return @confirmedKey if @confirmedKey
    return @lastKey

  h2LastKey: -> Nacl.h2 @lastKey.boxPk
  h2ConfirmedKey: -> Nacl.h2 @confirmedKey.boxPk
  h2NextKey: -> Nacl.h2 @nextKey.boxPk

  keyByHash: (hash) ->
    for s in @_roles
      return @[s] if Nacl.h2(@[s].boxPk) is hash

  isNextKeyHash: (hash) ->
    @h2NextKey().equal hash

  toStr: -> JSON.stringify(@).toBase64()
  fromStr: (str) -> Utils.extend @, JSON.parse(str.fromBase64())

  selfDestruct: (overseerAuthorized) ->
    return null unless overseerAuthorized
    for s in @_roles
      @keyRing.deleteKey @keyTag s

module.exports = KeyRatchet
window.KeyRatchet = KeyRatchet if window.__CRYPTO_DEBUG
