# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Utils   = require 'utils'

# === Utils helper ===

describe 'Utils functions', ->
  return unless window.__globalTest.runTests['utils']

  it 'ArrayBuffer to/from base64:', ->
    ab = new Uint8Array([0..255])
    check = (at) -> at[r].should.equal(r) for r in [0..255]
    check(ab)
    s = ab.toBase64()

    ab2 = s.fromBase64()
    check(ab2)
    ab.length.should.equal(ab2.length)

  it 'UTF16 strings to/form arrays', ->
    s = 'в военное время значение π достигало 4ех'
    a = s.toCodeArray()
    s2 = a.fromCharCodes()
    s2.should.equal s

    a8 = new Uint8Array(a) # 8 bit will erase data
    a16 = new Uint16Array(a) # 16 bit is ok
    a8.fromCharCodes().should.not.equal s
    a16.fromCharCodes().should.equal s

  it 'fillWith Uint8Array', ->
    a = new Uint8Array([97, 98, 99])
    a.fillWith 0
    b = new Uint8Array([0, 0, 0])
    a.should.deep.equal(b)

describe 'Integers to Arrays and back', ->
  return unless window.__globalTest.runTests['utils']

  it 'int32 <=> array', ->
    i = 0x89ABCDEF
    a = Utils.itoa i
    a.length.should.equal 4
    Utils.atoi(a).should.equal i

  it 'int64 <=> array', ->
    i = 0x0123456789ABCDEF
    a = Utils.itoa i
    a.length.should.equal 8
    Utils.atoi(a).should.equal i

describe 'Base64 functions', ->
  return unless window.__globalTest.runTests['utils']

  it 'btoa and atob ascii string:', ->
    bin = '123'
    b64 = btoa(bin)
    b64.should.equal 'MTIz'
    bin2 = atob(b64)
    bin2.should.equal bin

    bin = 'abc'
    b64 = btoa(bin)
    b64.should.equal 'YWJj'
    bin2 = atob(b64)
    bin2.should.equal bin

  it 'Uint8Array comparison:', ->
    a = new Uint8Array([0..4])
    b = new Uint8Array([0..4])
    a.should.deep.equal(b)

  it 'Uint8Array base64:', ->
    ab = new Uint8Array([0..4])
    s1 = ab.toBase64()
    s1.should.equal 'AAECAwQ='
    s2 = s1.fromBase64()
    s2.should.deep.equal(ab)

  it 'String toCodeArray', ->
    s = 'abc'
    a = s.toCodeArray()
    a.should.deep.equal([97, 98, 99])
    s2 = a.fromCharCodes()
    s2.should.equal s

  it 'String fromCharCodes', ->
    a = new Uint8Array([97, 98, 99])
    s = a.fromCharCodes()
    s.should.equal 'abc'
    a2 = s.toCodeArray()
    a2.should.deep.equal([97, 98, 99])
    a3 = new Uint8Array(a2)
    a3.should.deep.equal(a)
