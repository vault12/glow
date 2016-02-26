# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Utils = require 'utils'

# Nacl driver for the js-nacl emscripten implementation
class JsNaclDriver

  # heap size for js-nacl emscripten implementation
  @HEAP_SIZE: 2 ** 23 # 8,388,608
  # unload timeout for js-nacl emscripten implementation
  @UNLOAD_TIMEOUT: 15 * 1000

  @API = [
    crypto_secretbox_random_nonce
    crypto_secretbox
    crypto_secretbox_open
    crypto_box
    crypto_box_open
    crypto_box_random_nonce
    crypto_box_keypair
    crypto_box_keypair_from_raw_sk
    crypto_box_keypair_from_seed
    crypto_hash_sha256
    random_bytes
    encode_utf8
    decode_utf8
    to_hex
    from_hex
  ]

  @_instance:     null
  @_unloadTimer:  null

  constructor: ->
    # If we are running in the browser, then nacl_factory will be defined by
    # including the nacl_factory.js lib before including glow. If we are on node,
    # then require 'js-nacl' will include nacl_factory appropriately
    # https://github.com/tonyg/js-nacl
    @js_nacl = nacl_factory? or require 'js-nacl'

    @API.forEach (f)=>
      @[f] = =>
        inst = @use()
        Utils.resolve(inst[f].apply(inst, arguments))

  # whenever we call use, we're accessing the js-nacl lib for a function call
  # if we haven't used any js-nacl lib function calls in 15 seconds, then it
  # unloads via the unload call
  @use: ->
    # timer unloads 8mb heap 15 sec after last use
    clearTimeout @_unloadTimer if @_unloadTimer
    @_unloadTimer = setTimeout((-> Nacl.unload()), @UNLOAD_TIMEOUT)

    unless window.__naclInstance   # Global instance to avoid duplicating heap
      window.__naclInstance = js_nacl.instantiate(@HEAP_SIZE) # 8mb heap
    window.__naclInstance

  @unload: ->
    # Nacl hasn't been used in 15 seconds, unload it and free the heap
    @_unloadTimer = null
    window.__naclInstance = null
    delete window.__naclInstance
