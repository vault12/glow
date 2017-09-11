# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

Config  = require 'config'
MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'
Utils   = require 'utils'

# ----- Communication Relay: Start session -----
describe 'Relay Session', ->
  return unless window.__globalTest.runTests['relay session']
  @slow(window.__globalTest.slow)
  @timeout(window.__globalTest.timeouts.long)

  before ->
    @skip() if __globalTest.offline

  [Alice, Bob] = [null, null]
  # run this one as blocking async to see if the relay is online for the tests
  it 'get Server Token', ->

    MailBox.new('Alice').then (ret)->
      Alice = ret
      MailBox.new('Bob').then (ret)->
        Bob = ret

        r = new Relay(__globalTest.host)
        tm = Config.RELAY_TOKEN_TIMEOUT
        Config.RELAY_TOKEN_TIMEOUT = 2

        r.getServerToken().then ->

          unless r.relayToken
            window.__globalTest.offline = true
            console.log "Local server offline: start relay at #{r.url}"

          r.online.should.be.false
          r.relayToken.should.not.be.null
          r.clientToken.should.not.be.null
          expect(r.relayKey).is.null

          Utils.delay Config.RELAY_TOKEN_TIMEOUT + 5, ->
            Config.RELAY_TOKEN_TIMEOUT = tm
            r.online.should.be.false
            expect(r.relayToken).is.null
            expect(r.clientToken).is.null

  it 'get session key', ->
    r = new Relay(__globalTest.host)
    r.openConnection().then ->
      r.online.should.be.true
      r.relayToken.should.not.be.null
      r.clientToken.should.not.be.null
      r.relayKey.should.not.be.null

  it 'prove mailbox :hpk', ->
    r = new Relay(__globalTest.host)
    r.openConnection().then ->
      r.connectMailbox(Alice).then ->
        expect(Alice.sessionKeys).not.empty

  it 'emits token timeout event', ->
    rt = Config.RELAY_TOKEN_TIMEOUT
    Config.RELAY_TOKEN_TIMEOUT = 10
    r = new Relay(__globalTest.host)
    r.on 'relaytokentimeout', ->
      Config.RELAY_TOKEN_TIMEOUT = rt
    r.openConnection()

  it 'clear mailboxes', ->
    Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true)
