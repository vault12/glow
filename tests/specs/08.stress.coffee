# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

Utils   = require 'utils'
MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

# increase this number in multiple browser
# sessions to stress test the relay
# max_test = 50
max_test = 5
# Assuming 500ms roundtrip, increase for remote relays
timeout = max_test * window.__globalTest.timeouts.tiny

describe 'Stress Test', ->
  return unless window.__globalTest.runTests['relay stress']
  return done() if window.__globalTest.offline

  @timeout(timeout)
  r = new Relay(__globalTest.host)

  mbx = []
  # create test mailboxes
  for i in [0...max_test]
    mbx.push new MailBox("mbx_08_#{i}")

  # propagate guest keys
  # good seeds for sequence generator
  seed = [233, 253, 167, 107, 161][Nacl.random(1)[0] % 5]
  seq = (idx) -> ((idx + 1) * 997 * seed) % max_test
  for i in [0...max_test]
    for j in [0...3]
      d = seq(i + j + seed)
      # add key i => d
      mbx[i].keyRing.addGuest("guest#{j}", mbx[d].getPubCommKey())
      # add key d <= i
      mbx[d].keyRing.addGuest("guest#{3 + j}", mbx[i].getPubCommKey())
      # console.log "#{j} <=> #{d}"

  # Tests 08-11 are built using a different schema. Instead of declaring a
  # singular test with mocha's 'it' function, we programmatically generate a
  # set of tests, which is convinient when you need to run hundreds of them for
  # stress testing. When tests are run by mocha all internal variables are
  # reset and as a result can not be used for indexing. Thus we are declaring
  # globally unique variables in the global namespace to work as test indexes
  # after the tests are declared.
  window.__globalTest.idx801 = 0

  # send test messages and get a few back
  for k in [0...max_test]
    it "test #{k}", (done) ->
      return done() if __globalTest.offline
      i = window.__globalTest.idx801++
      mbx[i].sendToVia('guest0', r, "test msg #{i}=>g0").done ->
        mbx[i].relaySend('guest1', "test msg #{i}=>g1").done ->
          mbx[i].relaySend('guest2', "test msg #{i}=>g2").done ->
            mbx[i].relayMessages().done ->
              if mbx[i].lastDownload.length > 0
                expect(mbx[i].lastDownload[0].msg).to.include 'test'
              if mbx[i].lastDownload.length > 1
                expect(mbx[i].lastDownload[1].msg).to.include 'test'
              done()

  # get the last messages back
  window.__globalTest.idx802 = 0
  for k in [0...max_test]
    it "download #{k}", (done) ->
      return done() if __globalTest.offline
      i = window.__globalTest.idx802++
      mbx[i].getRelayMessages(r).done ->
        l = mbx[i].relayNonceList()
        mbx[i].relayDelete(l).done ->
          done()

  it 'cleanup', (done) ->
    Utils.delay timeout + 1000, ->
      for i in [0...max_test]
        mbx[i].selfDestruct(true)
    done()
