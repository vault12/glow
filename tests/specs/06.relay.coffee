# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

describe 'Relay Ops, low level API', ->
  return unless window.__global_test.run_tests['relay low level']
  @timeout(500)

  [Alice, Bob] = [new MailBox('Alice'), new MailBox('Bob')]

  Alice.keyRing.addGuest('Bob', Bob.getPubCommKey())
  Bob.keyRing.addGuest('Alice', Alice.getPubCommKey())

  it 'upload plaintext message to mailbox :hpk', (done) ->
    return done() if __global_test.offline
    r = new Relay(__global_test.host)
    r.openConnection().done ->
      r.connectMailbox(Alice).done ->
        expect(Alice.session_keys).not.empty
        r.runCmd('upload', Alice,
          to: Bob.hpk().toBase64()
          payload: 'Hi Bob from Alice 101')
        .done ->
          done()

  it 'message count in Bob mailbox', (done) ->
    return done() if __global_test.offline
    r = new Relay(__global_test.host)
    r.openConnection().done ->
      r.connectMailbox(Bob).done ->
        r.runCmd('count', Bob).done ->
          expect(r.result).equal 1
          done()

  it 'download plaintext Bob mailbox', (done) ->
    return done() if __global_test.offline
    r = new Relay(__global_test.host)
    r.openConnection().done ->
      r.connectMailbox(Bob).done ->
        r.runCmd('download', Bob).done ->
          expect(r.result[0].data).equal 'Hi Bob from Alice 101'
          window.__global_test.bob_nonce = r.result[0].nonce
          done()

  it 'delete from Bob mailbox', (done) ->
    return done() if __global_test.offline
    r = new Relay(__global_test.host)
    r.openConnection().done ->
      r.connectMailbox(Bob).done ->
        # have not deleted anything
        r.runCmd('delete', Bob,
          payload: [])
        .then ->
          expect(r.result).equal 1
          # so it is the same count
        .done ->
          # now delete for real
          r.runCmd('delete', Bob,
            payload: [__global_test.bob_nonce])
          .done ->
            expect(r.result).equal 0
            done()

  it 'few bad commands', (done) ->
    return done() if __global_test.offline
    r = new Relay(__global_test.host)
    r.openConnection().done ->
      r.connectMailbox(Bob).done ->
        expect(-> r.runCmd('count2', Bob)).to.throw(Error)
        expect(-> r.runCmd('UPLOAD', Bob)).to.throw(Error)
        expect(-> r.runCmd('download', Bob)).not.to.throw(Error)
        done()

  it 'clear mailboxes', (done) ->
    Alice.selfDestruct(true)
    Bob.selfDestruct(true)
    done()
