# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Utils = require 'utils'

# A test driver - not to be used in production for permanent key storage
class SimpleTestDriver

  _state: null
  _key_tag: (key) -> "#{@_root_tag}.#{key}"

  # Synchronous
  constructor: (root = 'storage.', sourceData = null) ->
    @_root_tag = "__glow.#{root}" # + root
    @_load(sourceData)

  # Returns a Promise
  get: (key) ->
    @_load() if not @_state
    res = if @_state[key] then @_state[key] else JSON.parse localStorage.getItem @_key_tag key
    Utils.resolve(res)

  # Returns a Promise
  set: (key, value) ->
    @_load() if not @_state
    @_state[key] = value
    localStorage.setItem @_key_tag(key), JSON.stringify value
    @_persist()

  # Returns a Promise
  multiSet: (pairs) ->
    @_load() if not @_state
    for key, i in pairs by 2
      localStorage.setItem @_key_tag(key), JSON.stringify pairs[i+1]
    @_persist()

  # Returns a Promise
  remove: (key) ->
    @_load() if not @_state
    delete @_state[key]
    localStorage.removeItem @_key_tag key
    @_persist()

  # Returns a Promise
  _persist: () ->
    # Permanently save the state object in a real driver
    # _state.save()
    Utils.resolve()

  # Synchronous
  _load: (sourceData = null) ->
    # Load from persitent app storage in the real driver
    @_state = if sourceData then sourceData else {}
    console.log 'INFO: SimpleTestDriver uses localStorage and should not be
      used in production for permanent key storage.'

module.exports = SimpleTestDriver
