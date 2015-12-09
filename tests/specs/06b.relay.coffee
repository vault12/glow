# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'
Utils   = require 'utils'

describe 'Relay Bulk Ops', ->
  return unless window.__globalTest.runTests['relay bulk']
  @timeout(1000)

  [Alice, Bob] = [new MailBox('Alice'), new MailBox('Bob')]

  Alice.keyRing.addGuest('Bob', Bob.getPubCommKey())
  Bob.keyRing.addGuest('Alice', Alice.getPubCommKey())

  code1 = {id: 1, code: 12345, msg: 'Missile code #1 is 12345'}
  code2 = {id: 2, code: 67890, msg: 'Missile code #2 is 67890'}
  code3 = {id: 3, code: 11111, msg: 'Missile code #2 is 11111'}

  it 'Give missile codes to Bob', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Alice.sendToVia('Bob', r, code1).done ->
      Alice.relaySend('Bob', code2).done ->
        Alice.relaySend('Bob', code3).done ->
          Bob.connectToRelay(r).done ->
            Bob.relayCount().done ->
              expect(r.result).equal 3
              done()

  it 'Bob gets missile codes', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.getRelayMessages(r).done ->
      expect(Bob.lastDownload).length.is 3
      msgs = Utils.map Bob.lastDownload, (m) -> m.msg
      expect(msgs).deep.equal [code1, code2, code3]
      done()

  it 'Bob erases his tracks', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    list = Utils.map Bob.lastDownload, (i) -> i.nonce
    Bob.connectToRelay(r).done ->
      Bob.relayCount().done ->
        expect(r.result).equal 3
        Bob.relayDelete(list).done ->
          Bob.relayCount().done ->
            expect(r.result).equal 0
            done()

  it 'clear mailboxes', (done) ->
    Alice.selfDestruct(true)
    Bob.selfDestruct(true)
    done()
