# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

module.exports =
  Utils:                  require 'utils'
  Mixins:                 require 'mixins'
  Nacl:                   require 'nacl'
  Keys:                   require 'keys'
  SimpleStorageDriver:    require 'test_driver'
  CryptoStorage:          require 'crypto_storage'
  KeyRing:                require 'keyring'
  MailBox:                require 'mailbox'
  Relay:                  require 'relay'
  RachetBox:              require 'rachetbox'
  Config:                 require 'config'
  JsNaclDriver:           require 'js_nacl_driver'
  JsNaclWebWorkerDriver:  require 'js_nacl_worker_driver'

  # naclImpl required API:
  # - crypto_secretbox_KEYBYTES (constant)
  # - crypto_secretbox_random_nonce(): Promise(nonce)
  # - crypto_secretbox(data, nonce, key): Promise(data)
  # - crypto_secretbox_open(ct, nonce, key): Promise(data)
  # - crypto_box(data, nonce, pkTo, skFrom): Promise(data)
  # - crypto_box_open(ctext, nonce, pkFrom, skTo): Promise(data)
  # - crypto_box_random_nonce(): Promise(nonce)
  # - crypto_box_keypair(): Promise(kp)
  # - crypto_box_keypair_from_raw_sk(raw_sk): Promise(kp)
  # - crypto_box_seed_keypair(seed): Promise(kp)
  # - crypto_box_keypair_from_seed(seed): Promise(kp)
  # - crypto_hash_sha256(data): Promise(hash)
  # - random_bytes(size): Promise(bytes)
  # - encode_latin1(string): Promise(Uint8Array)
  # - decode_latin1(Uint8Array): Promise(string)
  # - encode_utf8(utf8): Promise(data)
  # - decode_utf8(data): Promise(utf8)
  # - to_hex(data): Promise(hex)
  # - from_hex(hex): Promise(data)
  #
  setNaclImpl: (naclImpl)->
    @Nacl.setNaclImpl(naclImpl)

  # js-nacl note: crypto_box_keypair_from_seed(seed)
  # This call will be deprecated,
  # keeping for compatibility with native driver.

  # promiseImpl requried API:
  # - promise(func(resolve, reject)): Promise - a deferrable Promise
  # - all([promises]): Promise - resolve all elements
  # The Promise object is expected to implement:
  # - then(func(result)): Promise
  # - catch(func(Error)): Promise
  # - finally(func()): Promise
  setPromiseImpl: (promiseImpl)->
    @Utils.setPromiseImpl(promiseImpl)

  # storeImpl required API:
  # - get(key: String): Promise(Object)
  # - set(key: String, value: Object): Promise
  # - remove(key: String): Promise
  startStorageSystem: (storeImpl) ->
    @CryptoStorage.startStorageSystem(storeImpl)

  # ajaxImpl required API:
  # - ajax( url: String, data: String ): Promise(response)
  #   Promise: resolved with text/plain response
  #   method: POST
  #   contentType: 'text/plain'
  #   dataType: 'text'
  setAjaxImpl: (ajaxImpl)->
    @Utils.setAjaxImpl(ajaxImpl)

# export glow in browser
if window
  window.glow = module.exports
