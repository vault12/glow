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
  @timeout(window.__globalTest.timeouts.mid)

  [Alice, Bob] = [null, null]
  it 'create mailboxes', (done)->
    MailBox.new('Alice').then (ret)->
      Alice = ret
      MailBox.new('Bob').then (ret)->
        Bob = ret
        Alice.keyRing.addGuest('Bob', Bob.getPubCommKey()).then ->
          Bob.keyRing.addGuest('Alice', Alice.getPubCommKey()).then ->
            done()

  code1 = {id: 1, code: 12345, msg: 'Missile code #1 is 12345'}
  code2 = {id: 2, code: 67890, msg: 'Missile code #2 is 67890'}
  code3 = {id: 3, code: 11111, msg: 'Missile code #3 is 11111'}

  it 'Give missile codes to Bob', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Alice.sendToVia('Bob', r, code1).then ->
      Alice.relaySend('Bob', code2, r).then ->
        Alice.relaySend('Bob', code3, r).then ->
          Bob.connectToRelay(r).then ->
            Bob.relayCount(r).then (count)->
              expect(count).equal 3
              done()

  download = null
  it 'Bob gets missile codes', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    Bob.getRelayMessages(r).then (_download)->
      download = _download
      expect(download).length.is 3
      msgs = Utils.map download, (m) -> m.msg
      expect(msgs).deep.equal [code1, code2, code3]
      done()

  it 'Bob erases his tracks', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    list = Utils.map download, (i) -> i.nonce
    Bob.connectToRelay(r).then ->
      Bob.relayCount(r).then (count)->
        expect(count).equal 3
        Bob.relayDelete(list, r).then ->
          Bob.relayCount(r).then (count)->
            expect(count).equal 0
            done()

  it 'clear mailboxes', (done)->
    Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true).then ->
        done()
