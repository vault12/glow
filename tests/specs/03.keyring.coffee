# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

KeyRing = require 'keyring'
MailBox = require 'mailbox'
Nacl    = require 'nacl'

# ----- Keyring with guest keys -----
describe 'KeyRing with keys', ->
  return unless window.__globalTest.runTests['keyring']

  r1 = new KeyRing('main_test')
  r2 = new KeyRing('backup_test')
  k1 = null

  it 'create keyring', ->
    for r in [r1, r2]
      expect(r.storage).is.not.null
      expect(r.commKey).is.not.null
      expect(r.guestKeys).is.not.null
      expect(r.registry).is.not.null

  key_buffer = []
  it 'check system keys', ->
    for r in [r1, r2]
      for k in [r.getMasterKey(), r.getPubCommKey()]
        k.should.be.a('string')
        key_buffer.push k
        expect(k.fromBase64().length).equal(32) # 32 byte buffer

  it 'check re-load of system keys', ->
    rc1 = new KeyRing('main_test')
    rc2 = new KeyRing('backup_test')
    kb2 = []
    for r in [rc1, rc2]
      for k in [r.getMasterKey(), r.getPubCommKey()]
        kb2.push k

    # rings with the same name load the same keys
    expect(kb2).deep.equal(key_buffer)

  a = Nacl.makeKeyPair()
  b = Nacl.makeKeyPair()
  it 'add guests', ->
    for r in [r1, r2]
      # null calls are ignored
      expect(r.addGuest(null, null)).is.null
      expect(r.registry.length).equal(0)
      expect(r.addGuest(null, '123')).is.null
      expect(r.registry.length).equal(0)
      expect(r.addGuest('123', null)).is.null
      expect(r.registry.length).equal(0)

      r.addGuest('Alice', a.strPubKey())
      expect(r.registry.length).equal(1)
      expect(r.guestKeys['Alice']).not.null

      r.addGuest('Bob', b.strPubKey())
      expect(r.registry.length).equal(2)
      expect(r.guestKeys['Bob']).not.null

  it 'guest keys match', ->
    # retrieved keys equal the ones we provided
    for r in [r1, r2]
      for n, i in r.getGuestKey('Alice').boxPk
        expect(a.boxPk[i]).equal(n)

      for n, i in r.getGuestKey('Bob').boxPk
        expect(b.boxPk[i]).equal(n)

  it 'remove guests', ->
    for r in [r1, r2]
      r.removeGuest('Alice')
      expect(r.registry.length).equal(1)
      expect(r.guestKeys['Alice']).to.be.undefined
      expect(r.registry.indexOf('Alice')).equal(-1)

      r.removeGuest('Bob')
      expect(r.registry.length).equal(0)
      expect(r.guestKeys['Bob']).to.be.undefined
      expect(r.registry.indexOf('Bob')).equal(-1)

  [spectre, jb] = [null,null]
  it 'create from secret key', ->
    spectre = new KeyRing('missile_command_1')
    write_on_napkin = spectre.commKey.strSecKey()

    # smuggle the napkin
    jb = new KeyRing('james_bond_briefcase')
    jb.commFromSecKey write_on_napkin.fromBase64()
    expect(spectre.commKey).deep.equal jb.commKey

  it 'guest persistence', ->
    id1 = Nacl.random().toBase64()
    key = Nacl.makeKeyPair().strPubKey()

    k1 = new KeyRing(id1)
    k1.addGuest('guest', key)
    keyA = k1.getGuestKey('guest')

    k2 = new KeyRing(id1)
    keyB = k2.getGuestKey('guest')

    expect(keyA).is.not.null
    expect(keyB).is.not.null
    expect(keyA.toString()).equal(keyB.toString())

  it 'clean up storage', ->
    for r in [r1, r2, spectre, jb, k1]
      r.selfDestruct(true)
