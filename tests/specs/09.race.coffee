# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

Utils   = require 'utils'
MailBox = require 'mailbox'
Nacl    = require 'nacl'
Relay   = require 'relay'

max_test = 20
# Assuming 500ms roundtrip, increase for remote relays
timeout = max_test * window.__globalTest.timeouts.tiny

describe 'ZAX Race Conditions', ->
  return unless window.__globalTest.runTests['relay race']
  @slow(window.__globalTest.slow)
  @timeout(timeout)

  before ->
    @skip() if __globalTest.offline

  # Enable this test for multi-tab race condition testing. When run by itself,
  # it doesn't provide any value, since it will simply upload and delete
  # messages from the same mailbox. When run from multiple browsers against the
  # same relay, it will force a well-known relay mailbox into a race condition.
  r = new Relay(__globalTest.host)

  mbx = []
  target = null
  # create test mailboxes

  it 'create mailboxes', ->
    Utils.all [0...max_test].map (i)->
      MailBox.new("mbx_09_#{i}").then (m)->
        mbx.push(m)
    .then ->
      MailBox.fromSeed('Common Target').then (m)->
        target = m
        tasks = []
        # propagate guest keys
        for i in [0...max_test]
          tasks.push mbx[i].keyRing.addGuest('target', target.getPubCommKey())
          tasks.push target.keyRing.addGuest("guest#{i}", mbx[i].getPubCommKey())
        Utils.all(tasks)

  # send some test messages and get a few back
  window.__globalTest.idx901 = 0
  for k in [0...max_test]
    it "test #{k}", ->
      i = window.__globalTest.idx901++
      mbx[i].sendToVia('target', r, "test msg #{i}=>msg0").then ->
        mbx[i].relaySend('target', "test msg #{i}=>msg1", r).then ->
          mbx[i].relaySend('target', "test msg #{i}=>msg2", r)

  # get the last messages back
  it 'download', ->
    target.getRelayMessages(r).then (download)->
      ld = download
      if ld.length > 0
        expect(ld[0].msg).to.include 'test msg' if ld[0].msg
      if ld.length > 1
        expect(ld[1].msg).to.include 'test msg' if ld[1].msg

      # recursive delete of the rest of the mailbox messages
      # default download is 100 messages
      deleteBatch = ->
        target.relayMessages(r).then (download)->
          lst = target.relayNonceList(download)
          target.relayDelete(lst, r).then ->
            target.relayCount(r).then (count)->
              if count > 0
                console.log "messages left: #{count}"
                Utils.delay 1, deleteBatch

      deleteBatch()

  it 'cleanup', ->
    tasks = []
    for i in [0...max_test]
      tasks.push mbx[i].selfDestruct(true)
    Utils.all(tasks)
