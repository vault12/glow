# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

describe 'Relay Ops, wrapper API', ->
  return unless window.__globalTest.runTests['relay wrapper']
  @slow(window.__globalTest.slow)
  @timeout(window.__globalTest.timeouts.tiny)

  before ->
    @skip() if __globalTest.offline

  [Alice, Bob] = [null, null]
  it 'create mailboxes', ->
    MailBox.new('Alice').then (ret)->
      Alice = ret
      MailBox.new('Bob').then (ret)->
        Bob = ret
        Alice.keyRing.addGuest('Bob', Bob.getPubCommKey()).then ->
          Bob.keyRing.addGuest('Alice', Alice.getPubCommKey())

  it 'upload message to mailbox :hpk', ->
    r = new Relay(__globalTest.host)
    Alice.sendToVia('Bob', r, 'Hi Bob from Alice 202').then (msg) ->
      window.__globalTest.bob_nonce2 = msg.payload.nonce
      window.__globalTest.alice_storage_token = msg.storage_token

  it 'check uploaded message status', ->
    r = new Relay(__globalTest.host)
    st = window.__globalTest.alice_storage_token
    Alice.connectToRelay(r).then ->
      Alice.relay_msg_status(r,st).then (ttl)->
        expect(ttl).above 0

  it 'count Bob mailbox', ->
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).then ->
      r.count(Bob).then (count)->
        expect(count).equal 1

  it 'download Bob mailbox', ->
    r = new Relay(__globalTest.host)
    Bob.connectToRelay(r).then ->
      r.download(Bob).then (result)->
        d = result[0]
        Bob.decodeMessage('Alice', d['nonce'], d['data']).then (msg)->
          expect(msg).equal 'Hi Bob from Alice 202'

  it 'delete from Bob mailbox', ->
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

  it 'check deleted message status', ->
    r = new Relay(__globalTest.host)
    st = window.__globalTest.alice_storage_token
    Alice.connectToRelay(r).then ->
      r.messageStatus(Alice,st).then (ttl)->
        expect(ttl).equal -2  # message is now deleted

  it 'clear mailboxes', ->
    Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true)
