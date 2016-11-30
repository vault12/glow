# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

Utils       = require 'utils'
Nacl        = require 'nacl'
Keys        = require 'keys'
KeyRing     = require 'keyring'
KeyRatchet  = require 'keyratchet'
Mailbox     = require 'mailbox'

# RatchetBox is a prototype to show a simple ratcheting schema implementation via Glow.
# By overload relay_send and relay_messages we can introduce a key ratchet between
# mailbox and its guests. All payload messages (object trees) are delivered along with
# system field 'next_key' that contains next public key in the ratchet. The guest
# confirm key with system field 'got_key'. Any message to guest or from guest advances
# the ratchet to next_key from that side.
#
# TODO: provision for loss of messages by introducing 'reset' field - mailboxes
# can singnal they dont have key material to decrypt laste message. That will revert
# ratchet to long term idenitiy key and will cause the start of new key chain.
class RatchetBox extends Mailbox

  # Returns a Promise
  _loadRatchets: (guest) ->
    # every guest will have a next confirmed key that we can reliably use, and
    # a next key we are awaiting confirmation for. In local storage we will
    # reference guests by the usual guest hpk=h2(pk)
    @_gHpk(guest).then (gHpk)=>
      gHpk = gHpk.toBase64()
      # if we have confirmed ratchet key we use it, otherwise
      # fallback to our @commKey
      KeyRatchet.new("local_#{gHpk}_for_#{@hpk().toBase64()}",
        @keyRing, @keyRing.commKey).then (krLocal)=>
        @krLocal = krLocal
        KeyRatchet.new("guest_#{gHpk}_for_#{@hpk().toBase64()}",
          @keyRing, @keyRing.getGuestKey guest).then (krGuest)=>
          @krGuest = krGuest

  # Returns a Promise
  relaySend: (relay, guest, m) ->
    Utils.ensure(relay, guest, m)
    # now we have 2 keys - the next key to send to a guest, and the last
    # confirmed key we can use for encryption - it may be the comm identity key
    # if we are at the start of a ratchet
    @_loadRatchets(guest).then =>
      # Save original message and include ratchet information along
      msg =
        org_msg: m
      # Add next key to org_msg unless its a key confirmation message
      msg['nextKey'] = @krLocal.nextKey.strPubKey() unless m.got_key
      # Full message or just a 'got_key' confirmation?
      # Use the confirmed ratchet key we got from the guest, or it will default
      # to her public commKey
      pk = @krGuest[if m.got_key then 'lastKey' else 'confirmedKey'].boxPk
      @rawEncodeMessage(msg, pk, @krLocal.confirmedKey.boxSk).then (encMsg)=>
        Nacl.h2(@_gPk(guest)).then (h2)=>
          relay.upload(@, h2, encMsg)

  # Returns a Promise
  _tryKeypair: (nonce, ctext, pk, sk) ->
    try
      return @rawDecodeMessage(nonce.fromBase64(), ctext.fromBase64(), pk, sk)
    catch e
      Utils.resolve(null)

  # Returns a Promise
  decodeMessage: (guest, nonce, ctext, session = false, skTag = null) ->
    return super(guest, nonce, ctext, session, skTag) if session
    Utils.ensure(guest, nonce, ctext)
    @_loadRatchets(guest).then =>
      # console.log "receiving from #{@_gPk(guest).toBase64()} => #{@getPubCommKey()} with #{@krGuest.confirmedKey.boxPk.toBase64()}"
      keyPairs = [
        # defult: confirmed local and guest
        [@krGuest.confirmedKey.boxPk, @krLocal.confirmedKey.boxSk],
        # Guest might not have switched to latest key yet
        [@krGuest.lastKey.boxPk, @krLocal.lastKey.boxSk],
        [@krGuest.confirmedKey.boxPk, @krLocal.lastKey.boxSk],
        [@krGuest.lastKey.boxPk, @krLocal.confirmedKey.boxSk]]
      Utils.serial keyPairs, (kp)=>
        @_tryKeypair(nonce, ctext, kp[0], kp[1])
      .then (r)=>
        console.log('RatchetBox decryption failed: message from ' +
          'unknown guest or ratchet out of sync') unless r
        r
      # TODO: Add ratchet key reset protocol for this guest here (send "reset" command)

  # Returns a Promise
  relayMessages: ->
    # First download pending messages
    super().then (download)=>
      # Now, lets process ratchet-related information in these messages
      sendConfs = []
      tasks = download.map (m)=>
        return unless m.fromTag
        @_loadRatchets(m.fromTag).then =>
          # If guests send use their nextKey for ratchet
          if m.msg?.nextKey
            # save nextKey for that guest
            nextKey = new Keys
              boxPk: m.msg.nextKey.fromBase64()
            next = @krGuest.confKey(nextKey).then (res)=>
              if res
                # send guest confirmation that we got it
                Nacl.h2_64(m.msg.nextKey).then (h2)=>
                  sendConfs.push
                    toTag: m.fromTag
                    key: m.msg.nextKey
                    msg:
                      got_key: h2
          (next || Utils.resolve()).then =>
            # If we got confirmation that our key is received
            # we should move it to nextKey for that guest
            if m.msg?.org_msg?.got_key
              m.msg = m.msg.org_msg
              # do we saved that key locally?
              next2 = @krLocal.isNextKeyHash(m.msg.got_key.fromBase64()).then (isHash)=>
                if isHash
                  Nacl.makeKeyPair().then (kp)=>
                    @krLocal.pushKey(kp)
              .then =>
                # we processed it, nothing else to do with this message
                m.msg = null
            (next2 || Utils.resolve()).then =>
              # restore usual download structure
              if m.msg
                m.msg = m.msg.org_msg
        # now we can send confirmations to guests that we got their key. Note
        # that got_key is a service message that wont advance the ratchet
        Utils.all(tasks).then =>
          Utils.serial sendConfs, (sc)=>
            @relaySend(sc.toTag,sc.msg).then =>
              false # make sure serial() continues

  # Returns a Promise
  selfDestruct: (overseerAuthorized, withRatchet = false) ->
    return unless overseerAuthorized
    if withRatchet
      Utils.all @keyRing.registry.map (guest)=>
        @_loadRatchets(guest).then =>
          @krLocal.selfDestruct(withRatchet).then =>
            @krGuest.selfDestruct(withRatchet)
      .then =>
        super(overseerAuthorized)

module.exports = RatchetBox
window.RatchetBox = RatchetBox if window.__CRYPTO_DEBUG
