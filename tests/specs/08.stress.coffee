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
  @slow(window.__globalTest.slow)
  @timeout(timeout)

  before ->
    @skip() if __globalTest.offline

  r = new Relay(__globalTest.host)

  mbx = []
  # create test mailboxes
  it 'create mailboxes', ->
    Utils.all [0...max_test].map (i)->
      MailBox.new("mbx_08_#{i}").then (m)->
        mbx.push(m)
    .then ->
      # propagate guest keys
      # good seeds for sequence generator
      Nacl.random(1).then (rnd)->
        seed = [233, 253, 167, 107, 161][rnd[0] % 5]
        seq = (idx) -> ((idx + 1) * 997 * seed) % max_test
        tasks = []
        for i in [0...max_test]
          for j in [0...3]
            d = seq(i + j + seed)
            # add key i => d
            tasks.push mbx[i].keyRing.addGuest("guest#{j}", mbx[d].getPubCommKey())
            # add key d <= i
            tasks.push mbx[d].keyRing.addGuest("guest#{3 + j}", mbx[i].getPubCommKey())
            # console.log "#{j} <=> #{d}"
        Utils.all(tasks)

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
    it "test #{k}", ->
      i = window.__globalTest.idx801++
      mbx[i].sendToVia('guest0', r, "test msg #{i}=>g0").then ->
        mbx[i].relaySend('guest1', "test msg #{i}=>g1", r).then ->
          mbx[i].relaySend('guest2', "test msg #{i}=>g2", r).then ->
            mbx[i].relayMessages(r).then (download)->
              if download.length > 0
                expect(download[0].msg).to.include 'test'
              if download.length > 1
                expect(download[1].msg).to.include 'test'

  # get the last messages back
  window.__globalTest.idx802 = 0
  for k in [0...max_test]
    it "download #{k}", ->
      i = window.__globalTest.idx802++
      mbx[i].getRelayMessages(r).then (download)->
        l = mbx[i].relayNonceList(download)
        mbx[i].relayDelete(l, r)

  it 'cleanup', ->
    tasks = []
    for i in [0...max_test]
      tasks.push mbx[i].selfDestruct(true)
    Utils.all(tasks)
