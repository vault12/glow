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
  return unless window.__global_test.run_tests['relay session']
  @timeout(5000)

  [Alice, Bob] = [new MailBox('Alice'), new MailBox('Bob')]

  # run this one as blocking async to see if the relay is online for the tests
  it 'get Server Token', (done) ->
    r = new Relay(__global_test.host)

    # cater for various Promise implementations (.finally/.always)
    always = ->
      unless r.relay_token
        window.__global_test.offline = true
        console.log "Local server offline: start relay at #{r.url}"
      done()

    r.getServerToken().then ->
      r.online.should.be.false
      r.relay_token.should.not.be.null
      r.client_token.should.not.be.null
      expect(r.relay_key).is.null

      Utils.delay Config.RELAY_TOKEN_TIMEOUT + 1000, ->
        r.online.should.be.false
        expect(r.relay_token).is.null
        expect(r.client_token).is.null
    .finally always

  it 'get session key', (done) ->
    return done() if __global_test.offline
    r = new Relay(__global_test.host)
    o = r.openConnection().done ->
      r.online.should.be.true
      r.relay_token.should.not.be.null
      r.client_token.should.not.be.null
      r.relay_key.should.not.be.null
      Utils.delay Config.RELAY_SESSION_TIMEOUT + 1000, ->
        r.online.should.be.false
        expect(r.relay_token).is.null
        expect(r.client_token).is.null
        expect(r.relay_key).is.null
      done()

  it 'prove mailbox :hpk', (done)->
    return done() if __global_test.offline
    r = new Relay(__global_test.host)
    r.openConnection().done ->
      r.connectMailbox(Alice).done ->
        expect(Alice.session_keys).not.empty
        done()

  it 'clear mailboxes', (done) ->
    Alice.selfDestruct(true)
    Bob.selfDestruct(true)
    done()
