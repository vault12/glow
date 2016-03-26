# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Constants that define behavior for the glow library
class Config
  @_NONCE_TAG:  '__nc'
  @_SKEY_TAG:   'storage_key'
  @_DEF_ROOT:   '.v1.stor.vlt12'

  @RELAY_TOKEN_LEN: 32 # Relay tokens, keys and hashes are 32 bytes
  @RELAY_TOKEN_B64: 44

  # 5 min - Matched with config.x.relay.token_timeout
  @RELAY_TOKEN_TIMEOUT: 5 * 60 * 1000

  # 15 min - Matched with config.x.relay.session_timeout
  @RELAY_SESSION_TIMEOUT: 15 * 60 * 1000

  # 5 sec - Ajax request timeout
  @RELAY_AJAX_TIMEOUT: 5 * 1000

module.exports = Config

# Put all libs into global namespace for console access
# window.__CRYPTO_DEBUG = true
