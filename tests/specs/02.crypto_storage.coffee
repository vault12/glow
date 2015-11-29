# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect        = require('chai').expect

CryptoStorage = require 'crypto_storage'
Keys          = require 'keys'

# ----- Cryptographic Storage -----
describe 'Storage service', ->
  return unless window.__global_test.run_tests['crypto']
  
  ST = new CryptoStorage({}) # dummy key

  it 'tagging', ->
    ST.tag('hello world').should.equal('hello world.v1.stor.vlt12')
    ST.tag('1234567890').should.equal('1234567890.v1.stor.vlt12')
    expect(ST.tag(null)).is.null

  it 'low level write/read', ->
    ST._set 'hello world', 'wello horld'
    expect(ST._local_get 'hello world').is.null
    expect(ST._local_get ST.tag 'hello world').equal('wello horld')
    expect(ST._set null, '123').is.null
    expect(ST._set '123', null).is.null
    ST._set('hello world', 'wello horld').should.equal ST._get('hello world')
    ST._local_remove ST.tag 'hello world'
    expect(ST._get 'hello world').is.null

  it 'make new key', ->
    ST = new CryptoStorage()
    expect(ST.storage_key).not.null

    ST._local_remove 'storage_key.v1.stor.vlt12'
    ST2 = new CryptoStorage()
    expect(ST2.storage_key).not.null

    ST.storage_key.key.should.not.equal(ST2.storage_key.key)

    ST2 = new CryptoStorage(ST.storage_key)
    ST.storage_key.key.should.equal(ST2.storage_key.key)

  secret1 = 'hello world'
  secret2 =
      a: 1
      b: 'big'
      c:
        val: 'secret'
      d: [1, 2, 3, 'big', 'secrets']
      f: 'в военное время значение π достигало 4ех'

  it 'encrypted write/read', ->
    ST.save('hello',secret1)
    ST.get('hello').should.equal(secret1)

    ST.save('hello2', secret2)
    s2 = ST.get('hello2')
    s2.should.deep.equal(secret2)

    ST.remove 'hello'
    ST.remove 'hello2'

    expect(ST._get('hello')).is.null
    expect(ST._get('hello2')).is.null

  it 'restore with key', ->
    ST = new CryptoStorage()
    ST.newKey()
    ST.save('hello', secret2)
    key = ST.storage_key.toString() # b64 string

    ST2 = new CryptoStorage(Keys.fromString(key))
    s2 = ST2.get('hello')
    s2.should.deep.equal(secret2)

    ST.remove 'hello'
    expect(ST._get('hello')).is.null

  it 'clean storage key', ->
    ST = new CryptoStorage()
    expect(ST._local_get 'storage_key.v1.stor.vlt12').
      not.null
    ST.selfDestruct(true)
    expect(ST._local_get 'storage_key.v1.stor.vlt12').
      is.null
