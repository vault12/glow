# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

Utils   = require 'utils'
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
    MailBox.new('Alice_mbx').then (ret)->
      Alice = ret
      MailBox.new('Bob_mbx').then (ret)->
        Bob = ret
        expect(Alice.keyRing).not.null
        expect(Bob.keyRing).not.null

  it 'exchange keys', ->
    expect(Alice.keyRing.getNumberOfGuests()).equal(0)
    expect(Alice.keyRing.getGuestKey('Bob_mbx')).is.null
    Alice.keyRing.addGuest('Bob_mbx', Bob.getPubCommKey()).then ->
      expect(Alice.keyRing.getNumberOfGuests()).equal(1)
      expect(Alice.keyRing.getGuestKey('Bob_mbx')).is.not.null

      expect(Bob.keyRing.getNumberOfGuests()).equal(0)
      expect(Bob.keyRing.getGuestKey('Alice_mbx')).is.null
      Bob.keyRing.addGuest('Alice_mbx', Alice.getPubCommKey()).then ->
        expect(Bob.keyRing.getNumberOfGuests()).equal(1)
        expect(Bob.keyRing.getGuestKey('Alice_mbx')).is.not.null

  it 'nonces with data', ->
    # data = 0xCDEF89AB
    data = 0xFFFFFFFF
    MailBox._makeNonce().then (n1)=>
      # random nonce with timestamp only
      expect(MailBox._nonceData n1).is.not.equal data

      # random nonce with extra data, like message counter
      MailBox._makeNonce(data).then (n2)=>
        expect(MailBox._nonceData n2).is.equal data

  it 'Mailbox from well known seed', ->
    MailBox.fromSeed('hello').then (m)->
      pk = m.keyRing.getPubCommKey()
      pk.should.equal '2DM+z1PaxGXVnzsDh4zv+IlH7sV8llEFoEmg9fG3pRA='
      m.keyRing.hpk.should.deep.equal new Uint8Array([249, 209, 90, 99, 252, 44, 187,
        27, 13, 101, 229, 199, 235, 31, 235, 119, 224, 25, 207,
        215, 94, 130, 71, 230, 44, 22, 217, 0, 201, 41, 61, 222])
      m.selfDestruct(true)

  H2_KEY = 'vye4sj8BKHopBVXUfv3s3iKyP6TyNoJnHUYWCMcjwTo='
  H2_HPK = new Uint8Array([36, 36, 36, 231, 132, 114, 39, 6, 230, 153, 228, 128, 132,
    215, 100, 241, 87, 187, 9, 53, 179, 248, 176, 242, 249, 101, 68, 48, 48, 9, 219, 211])
  it 'Mailbox backup & restore', ->
    MailBox.fromSeed('hello2').then (m)->
      pk = m.keyRing.getPubCommKey()
      pk.should.equal H2_KEY
      m.keyRing.hpk.should.deep.equal H2_HPK
      backup = m.keyRing.backup()
      m.selfDestruct(true).then ->
        MailBox.fromBackup(backup,"backup test").then (m2)->
          pk = m2.keyRing.getPubCommKey()
          pk.should.equal H2_KEY
          m2.keyRing.hpk.should.deep.equal H2_HPK

  it 'encrypt message', ->
    Alice.encodeMessage('Bob_mbx', pt1 = 'Bob, I heard from Наталья
      Дубровская we have a problem with the water chip.').then (ret)->
      msg1 = ret
      Bob.encodeMessage('Alice_mbx', pt2 = 'Alice, I will dispatch one
        of the youngsters to find a replacement outside. नमस्ते!').then (ret)->
        msg2 = ret

  it 'decrypt message', ->
    Bob.decodeMessage('Alice_mbx', msg1.nonce, msg1.ctext).then (m1)->
      Alice.decodeMessage('Bob_mbx', msg2.nonce, msg2.ctext).then (m2)->
        pt1.should.equal(m1)
        pt2.should.equal(m2)

  it 'emits session timeout event', ->
    st = Config.RELAY_SESSION_TIMEOUT
    Config.RELAY_SESSION_TIMEOUT = 1
    Alice.on 'relaysessiontimeout', ->
      Config.RELAY_SESSION_TIMEOUT = st
    Alice.createSessionKey('session_id_123')

  it 'clear mailboxes', ->
    Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true)
