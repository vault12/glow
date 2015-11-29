# A test driver - not to be used in production for permanent key storage
class SimpleTestDriver

  _state: null
  _key_tag: (key) -> "#{@_root_tag}.#{key}"

  constructor: (root = 'storage.', sourceData = null) ->
    @_root_tag = "__glow.#{root}" # + root
    @_load(sourceData)

  get: (key) ->
    @_load() if not @_state
    if @_state[key] then @_state[key] else JSON.parse localStorage.getItem @_key_tag key

  set: (key, value) ->
    @_load() if not @_state
    @_state[key] = value
    localStorage.setItem @_key_tag(key), JSON.stringify value
    @_persist()

  remove: (key) ->
    @_load() if not @_state
    delete @_state[key]
    localStorage.removeItem @_key_tag key
    @_persist()

  _persist: () ->
    # Permanently save the state object in a real driver
    # _state.save()

  _load: (sourceData = null) ->
    # Load from persitent app storage in the real driver
    @_state = if sourceData then sourceData else {}
    console.log 'INFO: SimpleTestDriver uses localStorage and should not be
      used in production for permanent key storage.'

module.exports = SimpleTestDriver
