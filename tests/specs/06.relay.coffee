# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

describe 'Relay Ops, low level API', ->
  return unless window.__globalTest.runTests['relay low level']
  @timeout(window.__globalTest.timeouts.tiny)

  [Alice, Bob] = [null, null]
  it 'create mailboxes', (done)->
    handle done, MailBox.new('Alice').then (ret)->
      Alice = ret
      MailBox.new('Bob').then (ret)->
        Bob = ret
        Alice.keyRing.addGuest('Bob', Bob.getPubCommKey()).then ->
          Bob.keyRing.addGuest('Alice', Alice.getPubCommKey()).then ->
            done()

  it 'upload plaintext message to mailbox :hpk', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    handle done, r.openConnection().then ->
      r.connectMailbox(Alice).then ->
        expect(Alice.sessionKeys).not.empty
        Bob.hpk().then (hpk)->
          r.runCmd('upload', Alice,
            to: hpk.toBase64()
            payload: 'Hi Bob from Alice 101')
          .then ->
            done()

  it 'message count in Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    handle done, r.openConnection().then ->
      r.connectMailbox(Bob).then ->
        r.runCmd('count', Bob).then (count)->
          expect(count).equal 1
          done()

  it 'download plaintext Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    handle done, r.openConnection().then ->
      r.connectMailbox(Bob).then ->
        r.runCmd('download', Bob).then (result)->
          expect(result[0].data).equal 'Hi Bob from Alice 101'
          window.__globalTest.bob_nonce = result[0].nonce
          done()

  it 'delete from Bob mailbox', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    handle done, r.openConnection().then ->
      r.connectMailbox(Bob).then ->
        # have not deleted anything
        r.runCmd('delete', Bob, payload: []).then (result)->
          # so it is the same count
          expect(result).equal 1
          # now delete for real
          r.runCmd('delete', Bob,
            payload: [__globalTest.bob_nonce]).then (result)->
            expect(result).equal 0
            done()

  it 'few bad commands', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)
    handle done, r.openConnection().then ->
      r.connectMailbox(Bob).then ->
        expect(-> r.runCmd('count2', Bob)).to.throw(Error)
        expect(-> r.runCmd('UPLOAD', Bob)).to.throw(Error)
        expect(-> r.runCmd('download', Bob)).not.to.throw(Error)
        done()

  it 'clear mailboxes', (done) ->
    handle done, Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true).then ->
        done()
