# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

KeyRing = require 'keyring'
MailBox = require 'mailbox'
Nacl    = require 'nacl'
Config  = require 'config'
Utils   = require 'utils'

# ----- Keyring with guest keys -----
describe 'KeyRing with keys', ->
  return unless window.__globalTest.runTests['keyring']

  r1 = null
  r2 = null
  k1 = null

  it 'create keyring', (done)->
    KeyRing.new('main_test').then (r)->
      r1 = r
      KeyRing.new('backup_test').then (r)->
        r2 = r
        for r in [r1, r2]
          expect(r.storage).is.not.null
          expect(r.commKey).is.not.null
          expect(r.guestKeys).is.not.null
          expect(r.registry).is.not.null
        done()

  key_buffer = []
  it 'check system keys', ->
    for r in [r1, r2]
      for k in [r.getMasterKey(), r.getPubCommKey()]
        k.should.be.a('string')
        key_buffer.push k
        expect(k.fromBase64().length).equal(32) # 32 byte buffer

  it 'check re-load of system keys', (done)->
    KeyRing.new('main_test').then (r)->
      rc1 = r
      KeyRing.new('backup_test').then (r)->
        rc2 = r
        kb2 = []
        for r in [rc1, rc2]
          for k in [r.getMasterKey(), r.getPubCommKey()]
            kb2.push k
        # rings with the same name load the same keys
        expect(kb2).deep.equal(key_buffer)
        done()

  a = null
  b = null
  it 'add guests', (done)->
    Nacl.makeKeyPair().then (kp)->
      a = kp
      Nacl.makeKeyPair().then (kp)->
        b = kp
        Promise.all [r1, r2].map (r)->
          # null calls throw errors
          expect(-> r.addGuest(null, null)).to.throw(Utils.ENSURE_ERROR_MSG)
          expect(r.registry.length).equal(0)
          expect(-> r.addGuest(null, '123')).to.throw(Utils.ENSURE_ERROR_MSG)
          expect(r.registry.length).equal(0)
          expect(-> r.addGuest('123', null)).to.throw(Utils.ENSURE_ERROR_MSG)
          expect(r.registry.length).equal(0)

          r.addGuest('Alice', a.strPubKey()).then ->
            expect(r.registry.length).equal(1)
            expect(r.guestKeys['Alice']).not.null

            r.addGuest('Bob', b.strPubKey()).then ->
              expect(r.registry.length).equal(2)
              expect(r.guestKeys['Bob']).not.null
        .then ->
          done()

  it 'guest keys match', ->
    # retrieved keys equal the ones we provided
    for r in [r1, r2]
      for n, i in r.getGuestKey('Alice').boxPk
        expect(a.boxPk[i]).equal(n)

      for n, i in r.getGuestKey('Bob').boxPk
        expect(b.boxPk[i]).equal(n)

  it 'remove guests', (done)->
    Promise.all [r1, r2].map (r)->
      r.removeGuest('Alice').then ->
        expect(r.registry.length).equal(1)
        expect(r.guestKeys['Alice']).to.be.undefined
        expect(r.registry.indexOf('Alice')).equal(-1)

        r.removeGuest('Bob').then ->
          expect(r.registry.length).equal(0)
          expect(r.guestKeys['Bob']).to.be.undefined
          expect(r.registry.indexOf('Bob')).equal(-1)
    .then ->
      done()

  [spectre, jb] = [null, null]
  it 'create from secret key', (done)->
    KeyRing.new('missile_command_1').then (k)->
      spectre = k
      write_on_napkin = spectre.commKey.strSecKey()

      # smuggle the napkin
      KeyRing.new('james_bond_briefcase').then (k)->
        jb = k
        jb.commFromSecKey(write_on_napkin.fromBase64()).then ->
          expect(spectre.commKey).deep.equal jb.commKey
          done()

  it 'guest persistence', (done)->
    Nacl.random().then (ret)->
      id1 = ret.toBase64()
      Nacl.makeKeyPair().then (ret)->
        key = ret.strPubKey()

        KeyRing.new(id1).then (ret)->
          k1 = ret
          k1.addGuest('guest', key).then ->
            keyA = k1.getGuestKey('guest')

            KeyRing.new(id1).then (k2)->
              keyB = k2.getGuestKey('guest')
              expect(keyA).is.not.null
              expect(keyB).is.not.null
              expect(keyA.toString()).equal(keyB.toString())
              done()

  it 'emits guest timeout event', (done)->
    st = Config.RELAY_SESSION_TIMEOUT
    Config.RELAY_SESSION_TIMEOUT = 1
    k1.on 'tmpguesttimeout', ->
      expect(k1.getGuestKey('TmpAlice')).is.null
      Config.RELAY_SESSION_TIMEOUT = st
      done()
    k1.addTempGuest('TmpAlice', '123')

  it 'clean up storage', (done)->
    Promise.all [r1, r2, spectre, jb, k1].map (r)->
      r.selfDestruct(true)
    .then ->
      done()
