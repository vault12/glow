# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
chai                  = require 'chai' # http://chaijs.com/ BDD/TDD assertion lib
CryptoStorage         = require 'crypto_storage'
SimpleTestDriver      = require 'test_driver'
JsNaclDriver          = require 'js_nacl_driver'
JsNaclWebWorkerDriver = require 'js_nacl_worker_driver'
Nacl                  = require 'nacl'
Utils                 = require 'utils'

# make mocha use source maps; the programmatic way
# (we prefer to have tests as close to prod as possible, so we load this through a <script>)
# require('source-map-support').install
#   handleUncaughtExceptions: false

# initialize "should" assertion interface
chai.should()

if localStorage
  drv = new SimpleTestDriver('tests', {})

  # prevent problems on test reruns after failed tests
  k = (localStorage.key(i) for i in [0...localStorage.length])
  k.map (x) -> localStorage.removeItem x if (x? and (x.indexOf drv._root_tag > -1) and (!!~ x.indexOf 'blocked_' == -1))

  # Start crypto storage stystem with simple localStorage driver
  CryptoStorage.startStorageSystem drv

# Testing configurations.
# host points to known Zax server(s). To set up your own Zax server, see the
# instructions at https://github.com/vault12/zax#installation

# Allow for global overriding
if not window.__globalTest

  # select a preset (local vs remote) or edit your own settings
  remoteTest = false

  if remoteTest or window.__isTravis
    # remote testing
    window.__globalTest =
      host: 'https://z.vault12.com'
      offline: false
      slow: 5000
      timeouts:
        tiny: 50000
        mid: 130000
        long: 500000
  else
    # local testing
    window.__globalTest =
      host: 'http://localhost:8080'
      offline: false
      slow: 100
      timeouts:
        tiny: 500
        mid: 1000
        long: 5000

Nacl.setNaclImpl(new JsNaclDriver())

# Uncomment to test with web worker js-nacl driver
# window.__globalTest.naclWorker = true
# Nacl.setNaclImpl(new JsNaclWebWorkerDriver())

# Test helpers
window.randNum = (min,max) ->
  parseInt(min + Math.random()*(max-min))

window.randWord = (len) ->
  consonants = 'bcdfghjklmnpqrstvwxyz'.split('')
  vowels = 'aeiou'.split('')
  word = ""
  for i in [0..(len / 2)]
    rConsonant = consonants.sample()
    rVowel = vowels.sample()
    rConsonant = rConsonant.toUpperCase() unless i>0
    word += rConsonant
    word += if i*2 < len-1 then rVowel else ''
  word

# control which tests to run
if not window.__globalTest.runTests
  window.__globalTest.runTests =
    'utils':                 true
    'nacl':                  true
    'crypto':                true
    'keyring':               true
    'mailbox':               true
    'relay session':         true
    'relay low level':       true
    'relay wrapper':         true
    'relay bulk':            true
    'relay invites':         true
    'relay stress':          true
    'relay ratchet':         true
    'relay noise ratchet':   true
    'relay race':            true
    'relay files low level': true
    'relay files wrapper':   true

# In tests you can directly access window.Utils, window.Mailbox, etc.
# from the console
window.__CRYPTO_DEBUG = true
