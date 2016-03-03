# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

# ----- Example: sketch of exchanging invite codes -----
describe 'Invite codes', ->
  return unless window.__globalTest.runTests['relay invites']

  @timeout(window.__globalTest.timeouts.mid)

  [Alice, Bob] = [null, null]
  [aliceTemp, bobCode] = [null, null]
  sms_invite = null
  it 'create mailboxes', (done)->
    handle done, MailBox.new('Alice').then (ret)->
      Alice = ret
      MailBox.new('Bob').then (ret)->
        Bob = ret
        done()

  # Alice and Bob are remote: they no longer have each others guest keys!
  # Let's do it via SMS/email

  it 'Alice invites Bob', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    handle done, MailBox.new('aliceTemp').then (ret)->
      aliceTemp = ret
      # Alice sends an invite via SMS to Bob and Bob receives sms_invite
      Nacl.random(32).then (seed)->
        sms_invite =
          seed: seed.toBase64() # use random to prevent test races
          pkey: aliceTemp.getPubCommKey()

        MailBox.fromSeed(sms_invite.seed).then (ret)->
          inviteCode = ret
          aliceTemp.keyRing.addGuest('invite_bob',
            inviteCode.getPubCommKey()).then ->

            aliceTemp.sendToVia('invite_bob', r,
              looking_for: 'Bob'
              iam: 'Alice'
              # hash value might be better here, but Alice insisted
              confirmation: 'Alice + Bob = ❤️').then ->
              # Alice has no further need of Bob's invite code
              inviteCode.selfDestruct(true).then ->
                done()

  bobCode = null
  it 'Bob uses invite code', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    handle done, MailBox.fromSeed(sms_invite.seed).then (ret)->
      bobCode = ret
      bobCode.keyRing.addGuest('aliceTemp', sms_invite.pkey).then ->
        bobCode.connectToRelay(r).then ->
          bobCode.relayCount(r).then (count)->
            expect(count).equal 1
            bobCode.relayMessages(r).then (download)->
              expect(download).length.is 1
              invite_block = download[0].msg

              # Bob verifies validity of the invite confirmation block
              expect(invite_block.looking_for).equal 'Bob'
              expect(invite_block.iam).equal 'Alice'
              expect(invite_block.confirmation).equal 'Alice + Bob = ❤️'
              done()

  it 'Bob sends Alice his credentials', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    handle done, bobCode.sendToVia('aliceTemp', r,
      dest: 'Alice'
      iam: 'Bob'
      content: 'My public key'
      pub_key: Bob.getPubCommKey()).then ->
      # No further need of the invite code
      bobCode.selfDestruct(true).then ->
        done()

  it 'Alice gets Bob public key', (done)->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    handle done, aliceTemp.getRelayMessages(r).then (download)->
      bob_data = download[0].msg

      expect(bob_data.dest).equal 'Alice'
      expect(bob_data.iam).equal 'Bob'
      expect(bob_data.pub_key).is.not.null

      # Alice now has Bob's long term comm key
      Alice.keyRing.addGuest(bob_data.iam, bob_data.pub_key).then ->
        # No further need of Alice's temp key
        aliceTemp.selfDestruct(true).then ->
          done()

  it 'Alice has a comm channel to Bob', ->
    return if __globalTest.offline
    expect(Alice._gPk('Bob').toBase64()).equal Bob.getPubCommKey()
    # Alice sends her invite block to Bob over a secure channel

  it 'clear mailboxes', (done)->
    handle done, Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true).then ->

      if not __globalTest.offline
        r = new Relay(__globalTest.host)
        MailBox.fromSeed('Hello Bob!').then (inv)->
          inv.clean(r).then ->
            inv.selfDestruct(true).then ->
              done()
      else
        done()
