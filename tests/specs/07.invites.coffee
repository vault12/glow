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

  @timeout(1000)

  [Alice, Bob] = [new MailBox('Alice'), new MailBox('Bob')]
  [aliceTemp, bobCode] = [null, null]
  sms_invite = null

  # Alice and Bob are remote: they no longer have each others guest keys!
  #
  # Let's do it via SMS/email

  it 'Alice invites Bob', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    aliceTemp = new MailBox('aliceTemp')
    inviteCode = MailBox.fromSeed('Hello Bob!')
    aliceTemp.keyRing.addGuest( 'invite_bob', inviteCode.getPubCommKey())

    aliceTemp.sendToVia('invite_bob', r,
      looking_for: 'Bob'
      iam: 'Alice'
      # hash value might be better here, but Alice insisted
      confirmation: 'Alice + Bob = ❤️')
    .done ->
      # Alice has no further need of Bob's invite code
      inviteCode.selfDestruct(true)
      done()

    sms_invite = ['Hello Bob!', aliceTemp.getPubCommKey()]
    # Alice sends an invite via SMS to Bob and Bob receives sms_invite

  bobCode = null
  it 'Bob uses invite code', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    bobCode = MailBox.fromSeed(sms_invite[0])
    bobCode.keyRing.addGuest 'aliceTemp', sms_invite[1]

    bobCode.connectToRelay(r).done ->
      bobCode.relayCount().done ->
        expect(r.result).equal 1
        bobCode.relayMessages().done ->
          expect(bobCode.lastDownload).length.is 1
          invite_block = bobCode.lastDownload[0].msg

          # Bob verifies validity of the invite confirmation block
          expect(invite_block.looking_for).equal 'Bob'
          expect(invite_block.iam).equal 'Alice'
          expect(invite_block.confirmation).equal 'Alice + Bob = ❤️'
          done()

  it 'Bob sends Alice his credentials', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    bobCode.sendToVia('aliceTemp', r,
      dest: 'Alice'
      iam: 'Bob'
      content: 'My public key'
      pub_key: Bob.getPubCommKey())
    .done ->
      # No further need of the invite code
      bobCode.selfDestruct(true)
      done()

  it 'Alice gets Bob public key', (done) ->
    return done() if __globalTest.offline
    r = new Relay(__globalTest.host)

    aliceTemp.getRelayMessages(r).done ->
      bob_data = aliceTemp.lastDownload[0].msg

      expect(bob_data.dest).equal 'Alice'
      expect(bob_data.iam).equal 'Bob'
      expect(bob_data.pub_key).is.not.null

      # Alice now has Bob's long term comm key
      Alice.keyRing.addGuest(bob_data.iam, bob_data.pub_key)

      # No further need of Alice's temp key
      aliceTemp.selfDestruct(true)
      done()

  it 'Alice has a comm channel to Bob', ->
    return if __globalTest.offline
    expect(Alice._gPk('Bob').toBase64()).equal Bob.getPubCommKey()
    # Alice sends her invite block to Bob over a secure channel

  it 'clear mailboxes', (done) ->
    Alice.selfDestruct(true)
    Bob.selfDestruct(true)

    if not __globalTest.offline
      r = new Relay(__globalTest.host)
      inv = MailBox.fromSeed('Hello Bob!')
      inv.clean(r).done ->
        inv.selfDestruct(true)

    done()
