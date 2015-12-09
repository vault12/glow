# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

Utils   = require 'utils'
MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

max_test = 50
timeout = max_test * 500 # Assuming 500ms roundtrip, increase for remote relays

describe 'ZAX Race Conditions', ->
  return unless window.__globalTest.runTests['relay race']
  # Enable this test for multi-tab race condition testing. When run by itself,
  # it doesn't provide any value, since it will simply upload and delete
  # messages from the same mailbox. When run from multiple browsers against the
  # same relay, it will force a well-known relay mailbox into a race condition.
  return done() if __globalTest.offline
  r = new Relay(__globalTest.host)
  @timeout(timeout)

  mbx = []
  # create test mailboxes
  for i in [0...max_test]
    mbx.push new MailBox("mbx_09_#{i}")

  target = MailBox.fromSeed('Common Target')

  # propagate guest keys
  for i in [0...max_test]
    mbx[i].keyRing.addGuest('target', target.getPubCommKey())
    target.keyRing.addGuest("guest#{i}", mbx[i].getPubCommKey())

  # send some test messages and get a few back
  window.__globalTest.idx901 = 0
  for k in [0...max_test]
    it "test #{k}", (done) ->
      i = window.__globalTest.idx901++
      mbx[i].sendToVia('target', r, "test msg #{i}=>msg0").done ->
        mbx[i].relaySend('target', "test msg #{i}=>msg1").done ->
          mbx[i].relaySend('target', "test msg #{i}=>msg2").done ->
            done()

  # get the last messages back
  it 'download', (done) ->
    target.getRelayMessages(r).done ->
      ld = target.lastDownload
      if ld.length > 0
        expect(ld[0].msg).to.include 'test msg' if ld[0].msg?
      if ld.length > 1
        expect(ld[1].msg).to.include 'test msg' if ld[1].msg?

      # recursive delete of the rest of the mailbox messages
      # default download is 100 messages
      deleteBatch = ->
        target.relayMessages(r).done ->
          lst = target.relayNonceList()
          target.relayDelete(lst).done ->
            target.relayCount().done ->
              if target.count > 0
                console.log "messages left: #{target.count}"
                Utils.delay 1, deleteBatch
              done() if target.count is 0

      deleteBatch()

  it 'cleanup', (done) ->
    Utils.delay timeout + 1000, ->
      for i in [0...max_test]
        mbx[i].selfDestruct(true)
    done()
