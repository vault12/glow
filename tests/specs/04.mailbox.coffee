# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'
Config  = require 'config'

# ----- Communication MailBox -----
describe 'MailBox, offline Relay', ->
  return unless window.__globalTest.runTests['mailbox']

  [Alice, Bob] = [null, null]

   # An elegant variable init block
  [msg1, msg2, msg3, msg4, msg5,
   msg6, msg7, pt1, pt2, pt3, pt4] = (null for n in [1..11])

  it 'create mailbox', ->
    Alice = new MailBox('Alice_mbx')
    Bob = new MailBox('Bob_mbx')
    expect(Alice.keyRing).not.null
    expect(Bob.keyRing).not.null

  it 'exchange keys', ->
    expect(Alice.keyRing.registry.length).equal(0)
    expect(Alice.keyRing.getGuestKey('Bob_mbx')).is.null
    Alice.keyRing.addGuest('Bob_mbx', Bob.getPubCommKey())
    expect(Alice.keyRing.registry.length).equal(1)
    expect(Alice.keyRing.getGuestKey('Bob_mbx')).is.not.null

    expect(Bob.keyRing.registry.length).equal(0)
    expect(Bob.keyRing.getGuestKey('Alice_mbx')).is.null
    Bob.keyRing.addGuest('Alice_mbx', Alice.getPubCommKey())
    expect(Bob.keyRing.registry.length).equal(1)
    expect(Bob.keyRing.getGuestKey('Alice_mbx')).is.not.null

  it 'Mailbox from well known seed', ->
    m = MailBox.fromSeed('hello')
    pk = m.keyRing.getPubCommKey()
    pk.should.equal '2DM+z1PaxGXVnzsDh4zv+IlH7sV8llEFoEmg9fG3pRA='
    m.hpk().should.deep.equal new Uint8Array([255, 29, 75, 250, 114, 23, 77,
      198, 215, 184, 25, 211, 126, 152, 31, 82, 236, 188, 237, 35, 204, 66,
      209, 107, 162, 211, 241, 170, 1, 60, 236, 221])
    m.selfDestruct(true)

  it 'encrypt message', ->
    msg1 = Alice.encodeMessage('Bob_mbx', pt1 = 'Bob, I heard from Наталья
      Дубровская we have a problem with the water chip.')
    msg2 = Bob.encodeMessage('Alice_mbx', pt2 = 'Alice, I will dispatch one
      of the youngsters to find a replacement outside. नमस्ते!')

  it 'decrypt message', ->
    m1 = Bob.decodeMessage('Alice_mbx', msg1.nonce, msg1.ctext)
    m2 = Alice.decodeMessage('Bob_mbx', msg2.nonce, msg2.ctext)
    pt1.should.equal(m1)
    pt2.should.equal(m2)

  it 'emits session timeout event', (done)->
    st = Config.RELAY_SESSION_TIMEOUT
    Config.RELAY_SESSION_TIMEOUT = 1
    Alice.on 'relaysessiontimeout', ->
      Config.RELAY_SESSION_TIMEOUT = st
      done()
    Alice.createSessionKey('session_id_123')

  it 'clear mailboxes', ->
    Alice.selfDestruct(true)
    Bob.selfDestruct(true)
