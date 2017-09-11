# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

RatchetBox = require 'rachetbox'
Nacl    = require 'nacl'
Relay   = require 'relay'
Utils   = require 'utils'

max_test = 5
# Assuming 500ms roundtrip, increase for remote relays
timeout = max_test * window.__globalTest.timeouts.tiny

describe 'Key Ratchet', ->
  return unless window.__globalTest.runTests['relay ratchet']
  @slow(window.__globalTest.slow)
  @timeout(timeout)

  before ->
    @skip() if __globalTest.offline

  r = new Relay(__globalTest.host)

  mbx = []
  # create test mailboxes
  it 'create ratchets', ->
    Utils.all [0...max_test].map (i)->
      RatchetBox.new("mbx_10_#{i}").then (m)->
        mbx.push(m)
    .then ->
      # good seeds for sequence generator
      Nacl.random(1).then (rnd)->
        seed = [233, 253, 167, 107, 161][rnd[0] % 5]
        # seed = 233
        seq = (idx) -> ((idx + 1) * 997 * seed) % max_test
        # propagate guest keys
        tasks = []
        k = 0
        for i in [0...max_test]
          for j in [0...3]
            k++ while (d = seq(i + j + seed + k)) is i
            tasks.push mbx[i].keyRing.addGuest("guest#{j}", mbx[d].getPubCommKey())
            tasks.push mbx[d].keyRing.addGuest("guest#{3 + j}", mbx[i].getPubCommKey())
        Utils.all(tasks)

  # ---- Simple test ----
  # Each mailbox will send a few msgs to only 1 recepient and they will then
  # move the ratchet one step forward
  window.__globalTest.idx101 = 0
  for k in [0...max_test]
    it "test #{k}", ->
      i = window.__globalTest.idx101++
      mbx[i].sendToVia('guest0', r, "ratchet #1 #{i}=>g0").then ->
        mbx[i].relaySend('guest0', "ratchet #2 #{i}=>g0", r).then ->
          mbx[i].relaySend('guest0', "ratchet #3 #{i}=>g0", r).then ->
            mbx[i].relayMessages(r).then (download)->
              if download.length > 0
                for m in download
                  expect(m.msg).to.contain 'ratchet' if m.msg?

  # get the last messages back
  window.__globalTest.idx102 = 0
  for k in [0...max_test]
    it "download #{k}", ->
      i = window.__globalTest.idx102++
      mbx[i].getRelayMessages(r).then (download)->
        l = mbx[i].relayNonceList(download)
        mbx[i].relayDelete(l, r)

  # delete mailboxes after a delay to let previous requests complete
  window.__globalTest.idx103 = 0
  window.__globalTest.idx104 = 0
  for k in [0...max_test]
    j = window.__globalTest.idx103++
    it "cleanup #{j}", ->
      mbx[window.__globalTest.idx104++].selfDestruct(true, true)
