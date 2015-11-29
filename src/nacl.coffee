# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# A light wrapper around the js-nacl library

# If we are running in the browser, then nacl_factory will be defined by
# including the nacl_factory.js lib before including glow. If we are on node,
# then require 'js-nacl' will include nacl_factory appropriately
if nacl_factory?
  js_nacl = nacl_factory
else
  js_nacl  = require 'js-nacl' # https://github.com/tonyg/js-nacl

Keys          = require 'keys'
Utils         = require 'utils'

class Nacl
  @HEAP_SIZE:     2 ** 23
  @_instance:     null
  @_unloadTimer:  null

  # whenever we call use, we're accessing the js-nacl lib for a function call
  # if we haven't used any js-nacl lib function calls in 15 seconds, then it
  # unloads via the unload call
  @use: ->
    # timer unloads 8mb heap 15 sec after last use
    clearTimeout @_unloadTimer if @_unloadTimer
    @_unloadTimer = setTimeout((-> Nacl.unload()), 15 * 1000)

    unless window.__nacl_instance   # Global instance to avoid duplicating heap
      window.__nacl_instance = js_nacl.instantiate(@HEAP_SIZE) # 8mb heap
    window.__nacl_instance

  @unload: ->
    # Nacl hasn't been used in 15 seconds, unload it and free the heap
    @_unloadTimer = null
    window.__nacl_instance = null
    delete window.__nacl_instance

  @makeSecretKey: ->
    new Keys(
      key: @use().random_bytes(@use().crypto_secretbox_KEYBYTES)
    )

  @random: (size = 32) ->
    @use().random_bytes(size)

  @makeKeyPair: ->
    new Keys @use().crypto_box_keypair()

  @fromSecretKey: (raw_sk) ->
    new Keys @use().crypto_box_keypair_from_raw_sk(raw_sk)

  @fromSeed: (seed) ->
    new Keys @use().crypto_box_keypair_from_seed(seed)

  @sha256: (data) ->
    @use().crypto_hash_sha256 data

  @to_hex: (data) ->
    @use().to_hex data

  @from_hex: (data) ->
    @use().from_hex data

  @encode_utf8: (data) ->
    @use().encode_utf8 data

  @decode_utf8: (data) ->
    @use().decode_utf8 data

  # h2(m) = sha256(sha256(32x0 + m))
  # Zero out initial sha256 block, and double hash 0-padded message
  # http://cs.nyu.edu/~dodis/ps/h-of-h.pdf
  @h2: (str) ->
    str = str.toUint8ArrayRaw() if Utils.type(str) is 'String'
    tmp = new Uint8Array(32 + str.length)
    tmp.fill_with 0
    tmp.set(str, 32)
    @sha256 @sha256 tmp

  @h2_64: (b64str) ->
    Nacl.h2(b64str.fromBase64()).toBase64()

module.exports = Nacl
window.Nacl = Nacl if window.__CRYPTO_DEBUG
