# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Utils = require 'utils'

# Nacl driver for the js-nacl emscripten implementation
class JsNaclDriver

  @API: [
    'crypto_secretbox_random_nonce'
    'crypto_secretbox'
    'crypto_secretbox_open'
    'crypto_box'
    'crypto_box_open'
    'crypto_box_random_nonce'
    'crypto_box_keypair'
    'crypto_box_keypair_from_raw_sk'
    'crypto_box_keypair_from_seed'
    'crypto_hash_sha256'
    'random_bytes'
    'encode_utf8'
    'decode_utf8'
    'to_hex'
    'from_hex'
  ]

  _instance: null
  _unloadTimer:  null

  # HEAP_SIZE: heap size for js-nacl emscripten implementation; default 2 ** 23 = 8,388,608
  # UNLOAD_TIMEOUT: unload timeout for js-nacl emscripten implementation; default: 15 seconds
  constructor: (js_nacl = null, @HEAP_SIZE = 2 ** 23, @UNLOAD_TIMEOUT = 15 * 1000)->

    # If we are running in the browser, then nacl_factory will be defined by
    # including the nacl_factory.js lib before including glow. If we are on node,
    # then require 'js-nacl' will include nacl_factory appropriately
    # https://github.com/tonyg/js-nacl
    @js_nacl = js_nacl or (if nacl_factory? then nacl_factory) or require('js-nacl')

    @.crypto_secretbox_KEYBYTES = @use().crypto_secretbox_KEYBYTES

    JsNaclDriver.API.forEach (f)=>
      @[f] = =>
        inst = @use()
        Utils.resolve(inst[f].apply(inst, arguments))

  # whenever we call use, we're accessing the js-nacl lib for a function call
  # if we haven't used any js-nacl lib function calls in 15 seconds, then it
  # unloads via the unload call
  use: ->
    # timer unloads 8mb heap 15 sec after last use
    clearTimeout @_unloadTimer if @_unloadTimer
    @_unloadTimer = setTimeout((=> @unload()), @UNLOAD_TIMEOUT)

    unless @_instance   # Global instance to avoid duplicating heap
      @_instance = @js_nacl.instantiate(@HEAP_SIZE) # 8mb heap
    @_instance

  unload: ->
    # Nacl hasn't been used in 15 seconds, unload it and free the heap
    @_unloadTimer = null
    @_instance = null
    delete @_instance

module.exports = JsNaclDriver
window.JsNaclDriver = JsNaclDriver if window.__CRYPTO_DEBUG
