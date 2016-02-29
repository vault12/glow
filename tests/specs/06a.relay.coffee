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

  [Alice, Bob] = [null, null]
  it 'create mailboxes', (done)->
    MailBox.new('Alice').then (ret)->
      Alice = ret
      MailBox.new('Bob').then (ret)->
        Bob = ret
        Alice.keyRing.addGuest('Bob', Bob.getPubCommKey()).then ->
          Bob.keyRing.addGuest('Alice', Alice.getPubCommKey()).then ->
            done()

  it 'upload message to mailbox :hpk', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Alice.sendToVia('Bob', r, 'Hi Bob from Alice 202').then (msg)->
      window.__globalTest.bob_nonce2 = msg.payload.nonce
      done()

  it 'count Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).then ->
      r.count(Bob).then (count)->
        expect(count).equal 1
        done()

  it 'download Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).then ->
      r.download(Bob).then (result)->
        d = result[0]
        Bob.decodeMessage('Alice', d['nonce'], d['data']).then (msg)->
          expect(msg).equal 'Hi Bob from Alice 202'
          done()

  it 'delete from Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).then ->
      # not deleted anything
      r.delete(Bob, []).then ->
        r.count(Bob).then (count)->
          # so it is the same count
          expect(count).equal 1
          # now lets delete for real
          r.delete(Bob, [__globalTest.bob_nonce2]).then (result)->
            expect(result).equal 0
            r.count(Bob).then (count)->
              expect(count).equal 0
              done()

  it 'clear mailboxes', (done) ->
    Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true).then ->
        done()
