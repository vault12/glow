# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Utils = require 'utils'

# Nacl driver for the js-nacl emscripten implementation
class JsNaclDriver

  _instance: null
  _unloadTimer:  null

  # HEAP_SIZE: heap size for js-nacl emscripten implementation; default 2 ** 26 = 67,108,864
  constructor: (js_nacl = null, @HEAP_SIZE = 2 ** 26)->
    # If we are running in the browser, then nacl_factory will be defined by
    # including the nacl_factory.js lib before including glow. If we are on node,
    # then require 'js-nacl' will include nacl_factory appropriately
    # https://github.com/tonyg/js-nacl
    @js_nacl = js_nacl or (if nacl_factory? then nacl_factory) or require('js-nacl')
    @load()

  # whenever we call use, we're accessing the js-nacl lib for a function call
  use: ->
    # Global instance to avoid duplicating heap
    throw new Error('js-nacl is not loaded') unless @_instance
    @_instance

  load: ->
    nacl_factory.instantiate( (new_nacl) =>
      @_instance = new_nacl
      @.crypto_secretbox_KEYBYTES = @use().crypto_secretbox_KEYBYTES
      require('nacl').API.forEach (f)=>
        @[f] = =>
          inst = @use()
          try
            Utils.resolve(inst[f].apply(inst, arguments))
          catch e
            Utils.reject(e)
    ,
      requested_total_memory: @HEAP_SIZE
    )

  unload: ->
    @_instance = null
    delete @_instance

module.exports = JsNaclDriver
window.JsNaclDriver = JsNaclDriver if window.__CRYPTO_DEBUG
