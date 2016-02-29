# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect = require('chai').expect

Keys = require 'keys'
Nacl = require 'nacl'

# ----- Nacl -----
describe 'NACL', ->
  return unless window.__globalTest.runTests['nacl']

  it 'factory load/unload', (done)->
    jsnacl = Nacl.use()
    Nacl.makeSecretKey().then ->
      expect(jsnacl._instance).not.null
      setTimeout( ->
        s = if jsnacl._instance then 'OK!' else 'FAIL!'
      , 5 * 1000)
      setTimeout( ->
        s = if jsnacl._instance then 'FAIL!' else 'OK!'
      , 20 * 1000)
      done()

  it 'Hash₂ of utf8 strings', (done)->
    str = 'hello world | В военное время значение π достигало 4ех'
    Nacl.h2(str).then (hash1)->
      hash1str = hash1.fromCharCodes()
      expect(hash1).not.null
      expect(hash1).not.equal(str)
      expect(hash1.length).equal(32)

      str2 = 'hfllo world | В военное время значение π достигало 4ех'
      Nacl.h2(str2).then (hash2)->
        expect(hash2).not.null
        expect(hash2).not.equal(str2)
        expect(hash2.length).equal(32)
        expect(hash2.fromCharCodes()).not.equal(hash1str)

        str3 = 'hello world ' + '|' + ' В военное время значение π достигало 4ех'
        Nacl.h2(str3).then (hash3)->
          expect(hash3.fromCharCodes()).equal(hash1str)
          done()

  it 'Concat Strings', ->
    str4 = "apple pie | яблочный пирог"
    str5 = "peach pie | персиковый пирог"
    str6 = str4 + str5
    expect(str6.length).equal(54)
    expect(str6).equal "apple pie | яблочный пирогpeach pie | персиковый пирог"

  it 'Concat strings', (done)->
    Nacl.random(32).then (aUint8Array1)->
      Nacl.to_hex(aUint8Array1).then (str7)->
        Nacl.random(32).then (aUint8Array2)->
          Nacl.to_hex(aUint8Array2).then (str8)->
            str9 = str7 + str8
            expect(str9.length).equal(128)
            expect(str9).equal str7.concat str8
            done()

  it 'Concat arrays', (done)->
    Nacl.random(32).then (a1)->
      Nacl.random(32).then (a2)->
        a3 = a1.concat a2
        expect(a3.length).equal(64)

        concat = new Uint8Array(64)
        concat[i] = v for v,i in a1
        concat[i+a1.length] = v for v,i in a2
        expect(concat.equal a3).is.true

        Nacl.h2(a3).then (h2)->
          expect(h2.length).equal(32)
          done()

  it 'Concat H2 Nacl Strings', (done)->
    Nacl.h2('123').then (str1)->
      Nacl.h2('124').then (str2)->
        expect(str1.length).equal(32)
        expect(str2.length).equal(32)
        str = str1.concat str2
        expect(str.length).equal(64)
        Nacl.h2(str).then (h2)->
          expect(h2.length).equal(32)
          done()

# ----- Keys -----
describe 'Keys', ->
  return unless window.__globalTest.runTests['nacl']

  k1 = null
  k2 = null

  it 'create key', (done)->
    Nacl.makeSecretKey().then (_k1)->
      k1 = _k1
      Nacl.makeKeyPair().then (_k2)->
        k2 = _k2
        expect(k1).not.null
        expect(k2).not.null
        expect(k1).to.have.property 'key'
        expect(k1.key).not.be.empty
        expect(k2).to.have.property 'boxPk'
        expect(k2).to.have.property 'boxSk'
        done()

  it 'convert keys', ->
    k = k1
    s = k.toString()
    expect(s).is.not.null
    kc = Keys.fromString s
    expect(kc).is.not.null
    for b, i in k.key
      expect(b).equal(kc.key[i])

  it 'Keypair conversions', (done)->
    Nacl.use().crypto_box_keypair().then (_kp)->
      kp = new Keys(_kp)
      kps = Keys.keys2str(kp)
      kp2 = Keys.str2keys(kps)
      kp.should.deep.equal(kp2)
      done()

  it 'Recover secret key', (done)->
    Nacl.makeKeyPair().then (k)->
      readable_str = k.strSecKey()

      # recover key
      Nacl.fromSecretKey(readable_str.fromBase64()).then (k2)->
        expect(k2).deep.equal k
        done()
