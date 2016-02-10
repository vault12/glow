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
  @timeout(window.__globalTest.timeouts.long)

  [Alice, Bob] = [new MailBox('Alice'), new MailBox('Bob')]

  # run this one as blocking async to see if the relay is online for the tests
  it 'get Server Token', (done) ->
    r = new Relay(__globalTest.host)

    # cater for various Promise implementations (.finally/.always)
    always = ->
      unless r.relayToken
        window.__globalTest.offline = true
        console.log "Local server offline: start relay at #{r.url}"
      done()

    r.getServerToken().then ->
      r.online.should.be.false
      r.relayToken.should.not.be.null
      r.clientToken.should.not.be.null
      expect(r.relayKey).is.null

      Utils.delay Config.RELAY_TOKEN_TIMEOUT + 1000, ->
        r.online.should.be.false
        expect(r.relayToken).is.null
        expect(r.clientToken).is.null
    .finally always

  it 'get session key', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    o = r.openConnection().done ->
      r.online.should.be.true
      r.relayToken.should.not.be.null
      r.clientToken.should.not.be.null
      r.relayKey.should.not.be.null
      Utils.delay Config.RELAY_SESSION_TIMEOUT + 1000, ->
        r.online.should.be.false
        expect(r.relayToken).is.null
        expect(r.clientToken).is.null
        expect(r.relayKey).is.null
      done()

  it 'prove mailbox :hpk', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    r.openConnection().done ->
      r.connectMailbox(Alice).done ->
        expect(Alice.sessionKeys).not.empty
        done()

  it 'emits session expired event', (done)->
    rt = Config.RELAY_TOKEN_TIMEOUT
    Config.RELAY_TOKEN_TIMEOUT = 1
    r = new Relay(__globalTest.host)
    r.on 'relaytokentimeout', ->
      Config.RELAY_TOKEN_TIMEOUT = rt
      done()
    r.openConnection().done ->

  it 'clear mailboxes', (done) ->
    Alice.selfDestruct(true)
    Bob.selfDestruct(true)
    done()
