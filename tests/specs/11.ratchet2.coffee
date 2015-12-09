# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

RatchetBox = require 'rachetbox'
Nacl    = require 'nacl'
Relay   = require 'relay'
Utils   = require 'utils'

describe 'Ratchet With Noise', ->
  return unless window.__globalTest.runTests['relay noise ratchet']

  # Work in progress: randomly delete messages
  # and instrument RatchetBox to recover from
  # key loss by restarting ratchet from identity key.
  #
  # For now it runs standard ratchet test sending
  # messages between random mailboxes

  @timeout(5000)
  # @timeout(10000) # if you are far from relay

  return done() if __globalTest.offline
  r = new Relay(__globalTest.host)

  max_test = 20
  max_guest = 3

  mbx = []
  # create test mailboxes
  for i in [0...max_test]
    mbx.push new RatchetBox("mbx_11_#{i}")

  # good seeds for sequence generator
  # seed = [233, 253, 167, 107, 161][Nacl.random(1)[0] % 5]
  seed = 233
  seq = (idx) -> ((idx + 1) * 997 * seed) % max_test
  # propagate guest keys
  k = 0
  for i in [0...max_test]
    for j in [0...max_guest]
      k++ while (d = seq(i + j + seed + k)) is i
      mbx[i].keyRing.addGuest("guest#{j}", mbx[d].getPubCommKey())
      mbx[d].keyRing.addGuest("guest#{max_guest + j}", mbx[i].getPubCommKey())

  # send test messages and get a few back
  window.__globalTest.idx111 = 0
  for v in [0...max_guest]
    for k in [0...max_test]
      it "test #{k}", (done) ->
        return done() if __globalTest.offline
        i = window.__globalTest.idx111++ % max_test
        j = Nacl.random(1)[0] % max_guest
        hpk_from  = mbx[i].hpk().toBase64()
        hpk_to    = mbx[i]._gHpk("guest#{j}").toBase64()
        mbx[i].sendToVia("guest#{j}", r, "ratchet #{hpk_from} mbx#{i}=>guest#{j} #{hpk_to}").done ->
          mbx[i].relayMessages().done ->
            if mbx[i].lastDownload.length > 0
              for m in mbx[i].lastDownload
                # console.log m
                expect(m.msg).to.contain "ratchet" if m.msg?
            done()

  # get last messages back
  window.__globalTest.idx112 = 0
  for k in [0...max_test]
    it "download #{k}", (done) ->
      return done() if __globalTest.offline
      i = window.__globalTest.idx112++
      mbx[i].getRelayMessages(r).done ->
        l = mbx[i].relayNonceList()
        # console.log l.length
        mbx[i].relayDelete(l).done ->
          done()

  # delete mailboxes after delay to
  # let previous requests complete
  window.__globalTest.idx113 = 0
  window.__globalTest.idx114 = 0
  for k in [0...max_test]
    j = window.__globalTest.idx113++
    it "cleanup #{j}", (done)->
      Utils.delay 100, ->
        i = window.__globalTest.idx114++
        mbx[i].selfDestruct(true,true)
        done()
