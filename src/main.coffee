# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

module.exports =
  Utils:                require 'utils'
  Mixins:               require 'mixins'
  Nacl:                 require 'nacl'
  Keys:                 require 'keys'
  SimpleStorageDriver:  require 'test_driver'
  CryptoStorage:        require 'crypto_storage'
  KeyRing:              require 'keyring'
  MailBox:              require 'mailbox'
  Relay:                require 'relay'
  RachetBox:            require 'rachetbox'
  Config:               require 'config'

  # storeImpl required API:
  # - get(key: String): Object
  # - set(key: String, value: Object): Void
  # - remove(key: String): Void

  startStorageSystem: (storeImpl) ->
    @CryptoStorage.startStorageSystem storeImpl

  # ajaxImpl required API:
  # - ajax( url: String, data: String ): Promise
  #   Promise: resolved with text/plain response
  #   method: POST
  #   contentType: 'text/plain'
  #   dataType: 'text'

  setAjaxImpl: (ajaxImpl)->
    @Utils.setAjaxImpl ajaxImpl

# export glow in browser
if window
  window.glow = module.exports
