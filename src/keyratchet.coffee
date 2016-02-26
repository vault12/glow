# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

Nacl = require 'nacl'

class KeyRatchet

  # Construction:
  # KeyRatchet.new(..params..).then (kr)=>
  #   kr is ready to be used here

  # Last used key, we know other party has it
  lastKey: null

  # Confirmed key, we know other party just got it
  confirmedKey: null

  # Next key, we sending it to the other party. We
  # do not know when/if it will confirm it
  nextKey: null

  _roles: ['lastKey', 'confirmedKey', 'nextKey']

  # Returns a Promise
  @new: (@id, @keyRing, firstKey = null)->
    Utils.ensure(@id, @keyRing)
    kr = new KeyRatchet
    keys = @_roles.map (s)=>
      kr.keyRing.getKey(kr.keyTag(s)).then (key)=>
        kr[s] = key
    Utils.all(keys).then =>
      if firstKey
        kr.startRatchet(firstKey).then =>
          kr
      else
        kr

  # Synchronous
  keyTag: (role)->
    "#{role}_#{@id}"

  # Returns a Promise
  storeKey: (role)->
    @keyRing.saveKey(@keyTag(role), @[role])

  # Returns a Promise
  startRatchet: (firstKey)->
    # If we dont have confirmed key to work with
    # we have to start ratchet with a default key
    keys = ['confirmedKey', 'lastKey'].map (k)=>
      unless @[k]
        @[k] = firstKey
        @storeKey k
    Utils.all(keys).then =>
      unless @nextKey
        Nacl.makeKeyPair().then (nextKey)=>
          @nextKey = nextKey
          @storeKey('nextKey')

  # Returns a Promise
  pushKey: (newKey)->
    @lastKey = @confirmedKey
    @confirmedKey = @nextKey
    @nextKey = newKey
    Utils.all(@_roles.map (s)=> @storeKey(s))

  # Returns a Promise
  confKey: (newConfirmedKey)->
    return Utils.resolve(false) if @confirmedKey and @confirmedKey.equal(newConfirmedKey)
    # console.log "Key confirmed: replacing in #{@id} | #{@confirmedKey.boxPk.toBase64()} with #{newConfirmedKey.boxPk.toBase64()}"
    @lastKey = @confirmedKey
    @confirmedKey = newConfirmedKey
    Utils.all(['lastKey', 'confirmedKey'].map((s)=> @storeKey(s))).then ->
      true

  # Synchronous
  curKey: ->
    return @confirmedKey if @confirmedKey
    @lastKey

  # Returns a Promise
  h2LastKey: ->
    Nacl.h2(@lastKey.boxPk)

  # Returns a Promise
  h2ConfirmedKey: ->
    Nacl.h2(@confirmedKey.boxPk)

  # Returns a Promise
  h2NextKey: ->
    Nacl.h2(@nextKey.boxPk)

  # Returns a Promise
  keyByHash: (hash)->
    Utils.serial @_roles, (role)=>
      Nacl.h2(@[s].boxPk).then (h2)=>
        @[s] if h2 == hash

  # Returns a Promise
  isNextKeyHash: (hash)->
    @h2NextKey().then (h2)->
      h2.equal(hash)

  # Synchronous
  toStr: ->
    JSON.stringify(@).toBase64()

  # Synchronous
  fromStr: (str)->
    Utils.extend @, JSON.parse(str.fromBase64())

  # Returns a Promise
  selfDestruct: (overseerAuthorized)->
    Utils.ensure(overseerAuthorized)
    Utils.all @_roles.map (s)=>
      @keyRing.deleteKey(@keyTag(s))

module.exports = KeyRatchet
window.KeyRatchet = KeyRatchet if window.__CRYPTO_DEBUG
