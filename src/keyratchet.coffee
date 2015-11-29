# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

Nacl     = require 'nacl'

class KeyRatchet

  # Last used key, we know other party has it
  last_key: null

  # Confirmed key, we know other party just got it
  conf_key: null

  # Next key, we sending it to the other party. We
  # do not know when/if it will confirm it
  next_key: null

  _roles: ['last_key', 'conf_key', 'next_key']

  constructor: (@id, @keyRing, firstKey =null) ->
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
    for k in ['conf_key', 'last_key']
      unless @[k]
        @[k] = firstKey
        @storeKey k

    # create next ratchet key unless we already done so
    unless @next_key
      @next_key = Nacl.makeKeyPair()
      @storeKey 'next_key'

  pushKey: (newKey) ->
    @last_key = @conf_key
    @conf_key = @next_key
    @next_key = newKey
    @storeKey(s) for s in @_roles

  confKey: (confirmedKey) ->
    return false if @conf_key? and @conf_key.equal confirmedKey
    # console.log "Key confirmed: replacing in #{@id} | #{@conf_key.boxPk.toBase64()} with #{confirmedKey.boxPk.toBase64()}"
    @last_key = @conf_key
    @conf_key = confirmedKey
    @storeKey(s) for s in ['last_key', 'conf_key']
    return true

  curKey: ->
    return @conf_key if @conf_key
    return @last_key

  h2_last_key: -> Nacl.h2 @last_key.boxPk
  h2_conf_key: -> Nacl.h2 @conf_key.boxPk
  h2_next_key: -> Nacl.h2 @next_key.boxPk

  keyByHash: (hash) ->
    for s in @_roles
      return @[s] if Nacl.h2(@[s].boxPk) is hash

  isNextKeyHash: (hash) ->
    @h2_next_key().equal hash

  toStr: -> JSON.stringify(@).toBase64()
  fromStr: (str) -> Utils.extend @, JSON.parse(str.fromBase64())

  selfDestruct: (overseerAuthorized) ->
    return null unless overseerAuthorized
    for s in @_roles
      @keyRing.deleteKey @keyTag s

module.exports = KeyRatchet
window.KeyRatchet = KeyRatchet if window.__CRYPTO_DEBUG
