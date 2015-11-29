# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

RatchetBox = require 'rachetbox'
Nacl    = require 'nacl'
Relay   = require 'relay'
Utils   = require 'utils'

max_test = 5
timeout = max_test * 500 # Assuming 500ms roundtrip, increase for remote relays

describe 'Key Ratchet', ->
  return unless window.__global_test.run_tests['relay ratchet']
  @timeout(timeout)

  r = new Relay(__global_test.host)

  mbx = []
  # create test mailboxes
  for i in [0...max_test]
    mbx.push new RatchetBox("mbx_10_#{i}")

  # good seeds for sequence generator
  seed = [233, 253, 167, 107, 161][Nacl.random(1)[0] % 5]
  # seed = 233
  seq = (idx) -> ((idx + 1) * 997 * seed) % max_test
  # propagate guest keys
  k = 0
  for i in [0...max_test]
    for j in [0...3]
      k++ while (d = seq(i + j + seed + k)) is i
      mbx[i].keyRing.addGuest("guest#{j}", mbx[d].getPubCommKey())
      mbx[d].keyRing.addGuest("guest#{3 + j}", mbx[i].getPubCommKey())

  # ---- Simple test ----
  # Each mailbox will send a few msgs to only 1 recepient and they will then
  # move the ratchet one step forward
  window.__global_test.idx101 = 0
  for k in [0...max_test]
    it "test #{k}", (done) ->
      return done() if __global_test.offline
      i = window.__global_test.idx101++
      mbx[i].sendToVia('guest0', r, "ratchet #1 #{i}=>g0").done ->
        mbx[i].relay_send('guest0', "ratchet #2 #{i}=>g0").done ->
          mbx[i].relay_send('guest0', "ratchet #3 #{i}=>g0").done ->
            mbx[i].relay_messages().done ->
              if mbx[i].lastDownload.length > 0
                for m in mbx[i].lastDownload
                  expect(m.msg).to.contain 'ratchet' if m.msg?
              done()

  # get the last messages back
  window.__global_test.idx102 = 0
  for k in [0...max_test]
    it "download #{k}", (done) ->
      return done() if __global_test.offline
      i = window.__global_test.idx102++
      mbx[i].getRelayMessages(r).done ->
        l = mbx[i].relay_nonce_list()
        mbx[i].relay_delete(l).done ->
          done()

  # delete mailboxes after a delay to let previous requests complete
  window.__global_test.idx103 = 0
  window.__global_test.idx104 = 0
  for k in [0...max_test]
    j = window.__global_test.idx103++
    it "cleanup #{j}", (done) ->
      Utils.delay timeout + 1000, ->
        i = window.__global_test.idx104++
        mbx[i].selfDestruct(true,true)
      done()
