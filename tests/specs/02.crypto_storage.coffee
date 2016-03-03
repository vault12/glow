# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
window.__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect = require('chai').expect
CryptoStorage = require 'crypto_storage'
Keys = require 'keys'
Utils = require 'utils'

# ----- Cryptographic Storage -----
describe 'Storage service', ->
  return unless window.__globalTest.runTests['crypto']

  ST = null

  it 'constructs', (done)->
    handle done, CryptoStorage.new({}).then (_ST)-> # dummy key
      ST = _ST
      done()

  it 'tagging', ->
    ST.tag('hello world').should.equal('hello world.v1.stor.vlt12')
    ST.tag('1234567890').should.equal('1234567890.v1.stor.vlt12')
    expect(ST.tag(null)).is.null

  it 'low level write/read', (done)->
    handle done, ST._set('hello world', 'wello horld').then ->
      ST._localGet('hello world').then (ret)->
        expect(ret).is.null
        ST._localGet(ST.tag('hello world')).then (ret)->
          expect(ret).equal('wello horld')
          expect(-> ST._set(null, '123')).to.throw(Utils.ENSURE_ERROR_MSG)
          ST._set('123', null).then (ret)->
            expect(ret).is.null
            ST._get('hello world').then (ret)->
              ST._set('hello world', 'wello horld').then (ret2)->
                ret2.should.equal(ret)
                ST._localRemove(ST.tag('hello world')).then ->
                  ST._get('hello world').then (ret)->
                    expect(ret).is.null
                    done()

  it 'make new key', (done)->
    handle done, CryptoStorage.new().then (_ST)->
      ST = _ST
      expect(ST.storageKey).not.null

      ST._localRemove('storage_key.v1.stor.vlt12').then ->
        CryptoStorage.new().then (ST2)->
          expect(ST2.storageKey).not.null

          ST.storageKey.key.should.not.equal(ST2.storageKey.key)

          CryptoStorage.new(ST.storageKey).then (ST2)->
            ST.storageKey.key.should.equal(ST2.storageKey.key)
            done()

  secret1 = 'hello world'
  secret2 =
      a: 1
      b: 'big'
      c:
        val: 'secret'
      d: [1, 2, 3, 'big', 'secrets']
      f: 'в военное время значение π достигало 4ех'

  it 'encrypted write/read', (done)->
    handle done, ST.save('hello', secret1).then ->
      ST.get('hello').then (ret)->
        ret.should.equal(secret1)

        ST.save('hello2', secret2).then ->
          ST.get('hello2').then (s2)->
            s2.should.deep.equal(secret2)

            ST.remove('hello').then ->
              ST.remove('hello2').then ->

                ST._get('hello').then (ret)->
                  expect(ret).is.null
                  ST._get('hello2').then (ret)->
                    expect(ret).is.null
                    done()

  it 'restore with key', (done)->
    handle done, CryptoStorage.new().then (ST)->
      ST.newKey().then ->
        ST.save('hello', secret2).then ->
          key = ST.storageKey.toString() # b64 string

          CryptoStorage.new(Keys.fromString(key)).then (ST2)->
            ST2.get('hello').then (s2)->
              s2.should.deep.equal(secret2)

              ST.remove('hello').then ->
                ST._get('hello').then (ret)->
                  expect(ret).is.null
                  done()

  it 'clean storage key', (done)->
    handle done, CryptoStorage.new().then (ST)->
      ST._localGet('storage_key.v1.stor.vlt12').then (ret)->
        expect(ret).not.null
        ST.selfDestruct(true).then ->
          ST._localGet('storage_key.v1.stor.vlt12').then (ret)->
            expect(ret).is.null
            done()
