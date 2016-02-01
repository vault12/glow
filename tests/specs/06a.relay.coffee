# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

describe 'Relay Ops, wrapper API', ->
  return unless window.__globalTest.runTests['relay wrapper']
  @timeout(window.__globalTest.timeouts.tiny)

  [Alice, Bob] = [new MailBox('Alice'), new MailBox('Bob')]
  Alice.keyRing.addGuest('Bob', Bob.getPubCommKey())
  Bob.keyRing.addGuest('Alice', Alice.getPubCommKey())

  it 'upload message to mailbox :hpk', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Alice.sendToVia('Bob', r, 'Hi Bob from Alice 202').done ->
      window.__globalTest.bob_nonce2 = Alice.lastMsg.nonce
      done()

  it 'count Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).done ->
      r.count(Bob).done ->
        expect(r.result).equal 1
        done()

  it 'download Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).done ->
      r.download(Bob).done ->
        d = r.result[0]
        msg = Bob.decodeMessage('Alice', d['nonce'], d['data'])
        expect(msg).equal 'Hi Bob from Alice 202'
        done()

  it 'delete from Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).done ->
      # not deleted anything
      r.delete(Bob, []).done ->
        r.count(Bob).then ->
          expect(r.result).equal 1
          # so it is the same count
        .done ->
        # now lets delete for real
          r.delete(Bob,[__globalTest.bob_nonce2]).then ->
            expect(r.result).equal 0
          .done ->
            r.count(Bob).done ->
              expect(r.result).equal 0
              done()

  it 'clear mailboxes', (done) ->
    Alice.selfDestruct(true)
    Bob.selfDestruct(true)
    done()
