# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

Keys          = require 'keys'
Utils         = require 'utils'
Config        = require 'config'
JsNaclDriver  = require 'js_nacl_driver'


class Nacl

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

  naclImpl: null

  # Synchronous
  @setNaclImpl: (naclImpl)->
    @naclImpl = naclImpl

  # Synchronous
  @use: ->
    @setDefaultNaclImpl() if not @naclImpl
    @naclImpl

  # Synchronous
  @setDefaultNaclImpl: ->
    @naclImpl = new JsNaclDriver()

  # Returns a Promise
  @makeSecretKey: ->
    @use().random_bytes(@use().crypto_secretbox_KEYBYTES).then (bytes)->
      new Keys
        key: bytes

  # Returns a Promise
  @random: (size = 32)->
    @use().random_bytes(size)

  # Returns a Promise
  @makeKeyPair: ->
    @use().crypto_box_keypair().then (kp)->
      new Keys(kp)

  # Returns a Promise
  @fromSecretKey: (raw_sk)->
    @use().crypto_box_keypair_from_raw_sk(raw_sk).then (kp)->
      new Keys(kp)

  # Returns a Promise
  @fromSeed: (seed)->
    @use().crypto_box_keypair_from_seed(seed).then (kp)->
      new Keys(kp)

  # Returns a Promise
  @sha256: (data)->
    @use().crypto_hash_sha256(data)

  # Returns a Promise
  @to_hex: (data)->
    @use().to_hex(data)

  # Returns a Promise
  @from_hex: (data)->
    @use().from_hex(data)

  # Returns a Promise
  @encode_utf8: (data)->
    @use().encode_utf8(data)

  # Returns a Promise
  @decode_utf8: (data)->
    @use().decode_utf8(data)

  # h2(m) = sha256(sha256(32x0 + m))
  # Zero out initial sha256 block, and double hash 0-padded message
  # http://cs.nyu.edu/~dodis/ps/h-of-h.pdf
  # Returns a Promise
  @h2: (str)->
    str = str.toUint8ArrayRaw() if Utils.type(str) is 'String'
    tmp = new Uint8Array(32 + str.length)
    tmp.fillWith 0
    tmp.set(str, 32)
    @sha256(tmp).then (sha)=>
      @sha256(sha)

  # Returns a Promise
  @h2_64: (b64str)->
    Nacl.h2(b64str.fromBase64()).then (h2)->
      h2.toBase64()

module.exports = Nacl
window.Nacl = Nacl if window.__CRYPTO_DEBUG
