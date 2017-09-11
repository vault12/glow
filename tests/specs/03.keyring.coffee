# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

KeyRing = require 'keyring'
MailBox = require 'mailbox'
Nacl    = require 'nacl'
Config  = require 'config'
Utils   = require 'utils'

kRing_ok = (r) ->
  expect(r.commKey).is.not.null
  expect(r.hpk).is.not.null
  expect(r.storage).is.not.null
  expect(r.guestKeys).is.not.null

# ----- Keyring with guest keys -----
describe 'KeyRing with keys', ->
  return unless window.__globalTest.runTests['keyring']

  r1 = null
  r2 = null
  k1 = null

  it 'create keyring', ->
    KeyRing.new('main_test').then (r)->
      r1 = r
      KeyRing.new('second_test').then (r)->
        r2 = r
        for r in [r1, r2]
          kRing_ok r

  key_buffer = []
  h_buffer = []
  it 'check system keys', ->
    for r in [r1, r2]
      for k in [r.getMasterKey(), r.getPubCommKey()]
        k.should.be.a('string')
        key_buffer.push k
        h_buffer.push r.hpk
        expect(k.fromBase64().length).equal(32) # 32 byte buffer

  it 'check re-load of system keys', ->
    KeyRing.new('main_test').then (r)->
      rc1 = r
      kRing_ok rc1
      KeyRing.new('second_test').then (r)->
        rc2 = r
        kb2 = []
        hb2 = []
        kRing_ok rc2
        for r in [rc1, rc2]
          for k in [r.getMasterKey(), r.getPubCommKey()]
            kb2.push k
            hb2.push r.hpk
        # rings with the same name load the same keys
        expect(kb2).deep.equal(key_buffer)
        expect(hb2).deep.equal(h_buffer)

  a = null
  b = null
  it 'add guests', ->
    Nacl.makeKeyPair().then (kp)->
      a = kp
      Nacl.makeKeyPair().then (kp)->
        b = kp
        Utils.all [r1, r2].map (r)->
          # null calls throw errors
          expect(-> r.addGuest(null, null)).to.throw(Utils.ENSURE_ERROR_MSG)
          expect(r.getNumberOfGuests()).equal(0)
          expect(-> r.addGuest(null, '123')).to.throw(Utils.ENSURE_ERROR_MSG)
          expect(r.getNumberOfGuests()).equal(0)
          expect(-> r.addGuest('123', null)).to.throw(Utils.ENSURE_ERROR_MSG)
          expect(r.getNumberOfGuests()).equal(0)

          r.addGuest('Alice', a.strPubKey()).then ->
            expect(r.getNumberOfGuests()).equal(1)
            expect(r.guestKeys['Alice']).not.null

            r.addGuest('Bob', b.strPubKey()).then ->
              expect(r.getNumberOfGuests()).equal(2)
              expect(r.guestKeys['Bob']).not.null

  it 'guest keys match', ->
    # retrieved keys equal the ones we provided
    for r in [r1, r2]
      for n, i in r.getGuestKey('Alice').boxPk
        expect(a.boxPk[i]).equal(n)

      for n, i in r.getGuestKey('Bob').boxPk
        expect(b.boxPk[i]).equal(n)

  it 'remove guests', ->
    Utils.all [r1, r2].map (r)->
      r.removeGuest('Alice').then ->
        expect(r.getNumberOfGuests()).equal(1)
        expect(r.guestKeys['Alice']).to.be.undefined

        r.removeGuest('Bob').then ->
          expect(r.getNumberOfGuests()).equal(0)
          expect(r.guestKeys['Bob']).to.be.undefined

  [spectre, jb] = [null, null]
  it 'create from secret key', ->
    KeyRing.new('missile_command_1').then (k)->
      spectre = k
      kRing_ok spectre
      write_on_napkin = spectre.commKey.strSecKey()

      # smuggle the napkin
      KeyRing.new('james_bond_briefcase').then (k)->
        jb = k
        jb.commFromSecKey(write_on_napkin.fromBase64()).then ->
          kRing_ok jb
          expect(spectre.commKey).deep.equal jb.commKey
          expect(spectre.hpk).deep.equal jb.hpk

  it 'guest persistence', ->
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

  it 'multi guest persistence', ->
    Nacl.random().then (ret)->
      id1 = ret.toBase64()
      Nacl.makeKeyPair().then (ret)->
        key1 = ret.strPubKey()
        Nacl.makeKeyPair().then (ret)->
          key2 = ret.strPubKey()

          KeyRing.new(id1).then (ret)->
            k1 = ret
            k1.addGuest('guest1', key1).then ->
              k1.addGuest('guest2', key2).then ->
                keyA_orig = k1.getGuestKey('guest1')
                keyB_orig = k1.getGuestKey('guest2')

                KeyRing.new(id1).then (k2)->
                  keyA = k2.getGuestKey('guest1')
                  keyB = k2.getGuestKey('guest2')
                  expect(keyA).is.not.null
                  expect(keyB).is.not.null

                  expect(keyA.toString()).equal(keyA_orig.toString())
                  expect(keyB.toString()).equal(keyB_orig.toString())

  [original, restored] = [null,null]
  it 'backup and restore', ->
    KeyRing.new('missile_control').then (kr1)->
      original = kr1
      p = (for i in [0..randNum(5,10)]
        Nacl.makeKeyPair().then (nkey)->
          name = randWord randNum 4,14
          key = nkey.strPubKey()
          original.addGuest name,key
      )

      Utils.all(p).then ->
        backup = original.backup()
        KeyRing.fromBackup('restored',backup).then (kr2)->
          restored = kr2
          expect(original.commKey).deep.equal(restored.commKey)
          expect(original.guestKeys).deep.equal(restored.guestKeys)
          expect(original.hpk).deep.equal(restored.hpk)

  it 'emits guest timeout event', ->
    st = Config.RELAY_SESSION_TIMEOUT
    Config.RELAY_SESSION_TIMEOUT = 1
    k1.on 'tmpguesttimeout', ->
      expect(k1.getGuestKey('TmpAlice')).is.null
      Config.RELAY_SESSION_TIMEOUT = st
    k1.addTempGuest('TmpAlice', '123')

  it 'clean up storage', ->
    Utils.all [r1, r2, spectre, jb, k1].map (r)->
      r.selfDestruct(true)
