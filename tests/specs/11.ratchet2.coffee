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

  @slow(window.__globalTest.slow)
  @timeout(window.__globalTest.timeouts.long)

  before ->
    @skip() if __globalTest.offline

  r = new Relay(__globalTest.host)

  max_test = 10
  max_guest = 3

  mbx = []
  # create test mailboxes
  it 'create ratchets', ->
    Utils.all [0...max_test].map (i)->
      RatchetBox.new("mbx_11_#{i}").then (m)->
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
          for j in [0...max_guest]
            k++ while (d = seq(i + j + seed + k)) is i
            tasks.push mbx[i].keyRing.addGuest("guest#{j}", mbx[d].getPubCommKey())
            tasks.push mbx[d].keyRing.addGuest("guest#{max_guest + j}", mbx[i].getPubCommKey())
        Utils.all(tasks)

  # send test messages and get a few back
  window.__globalTest.idx111 = 0
  for v in [0...max_guest]
    for k in [0...max_test]
      it "test #{k}", ->
        i = window.__globalTest.idx111++ % max_test
        Nacl.random(1).then (rnd)->
          j = rnd[0] % max_guest
          hpk_from = mbx[i].hpk()
          mbx[i]._gHpk("guest#{j}").then (gHpk)->
            hpk_to = gHpk.toBase64()
            mbx[i].sendToVia("guest#{j}", r, "ratchet #{hpk_from} mbx#{i}=>guest#{j} #{hpk_to}").then ->
              mbx[i].relayMessages(r).then (download)->
                if download.length > 0
                  for m in download
                    expect(m.msg).to.contain "ratchet" if m.msg?

  # get last messages back
  window.__globalTest.idx112 = 0
  for k in [0...max_test]
    it "download #{k}", ->
      i = window.__globalTest.idx112++
      mbx[i].getRelayMessages(r).then (download)->
        l = mbx[i].relayNonceList(download)
        mbx[i].relayDelete(l, r)

  # delete mailboxes after delay to
  # let previous requests complete
  window.__globalTest.idx113 = 0
  window.__globalTest.idx114 = 0
  for k in [0...max_test]
    j = window.__globalTest.idx113++
    it "cleanup #{j}", ->
      i = window.__globalTest.idx114++
      mbx[i].selfDestruct(true, true)
