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

  _loadRatchets: (guest) ->
    # every guest will have a next confirmed key that we can reliably use, and
    # a next key we are awaiting confirmation for. In local storage we will
    # reference guests by the usual guest hpk=h2(pk)
    gHpk = @_gHpk(guest).toBase64()

    # if we have confirmed ratchet key we use it, otherwise
    # fallback to our @commKey
    @krLocal = new KeyRatchet("local_#{gHpk}_for_#{@hpk().toBase64()}",
      @keyRing, @keyRing.commKey)

    @krGuest = new KeyRatchet("guest_#{gHpk}_for_#{@hpk().toBase64()}",
      @keyRing, @keyRing.getGuestKey guest)

  relaySend: (guest, m) ->
    throw new Error('rbx: relaySend - no open relay') unless @lastRelay
    throw new Error('rbx: relaySend - missing params') unless guest and m

    # now we have 2 keys - the next key to send to a guest, and the last
    # confirmed key we can use for encryption - it may be the comm identity key
    # if we are at the start of a ratchet
    @_loadRatchets(guest)

    # Save original message and include ratchet information along
    msg = {org_msg: m}
    # Add next key to org_msg unless its a key confirmation message
    msg['nextKey'] = @krLocal.nextKey.strPubKey() unless m.got_key?

    # Full message or just a 'got_key' confirmation?
    if not m.got_key?
      # Use the confirmed ratchet key we got from the guest, or it will default
      # to her public commKey
      encMsg = @rawEncodeMessage(msg, @krGuest.confirmedKey.boxPk, @krLocal.confirmedKey.boxSk)
      @lastMsg = encMsg
    else
      # sending key confirmation using last key
      encMsg = @rawEncodeMessage(msg, @krGuest.lastKey.boxPk, @krLocal.confirmedKey.boxSk)

    # console.log "sent #{@getPubCommKey()} => #{@_gPk(guest).toBase64()} with #{@krGuest.confirmedKey.boxPk.toBase64()} | nonce = #{encMsg.nonce}"
    @lastRelay.upload(@, Nacl.h2(@_gPk guest), encMsg)

  _tryKeypair: (nonce, ctext, pk, sk) ->
    try
      return @rawDecodeMessage nonce.fromBase64(),
        ctext.fromBase64(), pk, sk
    catch e
      return null

  decodeMessage: (guest, nonce, ctext, session = false, skTag = null) ->
    return super(guest, nonce, ctext, session, skTag) if session
    throw new Error('decodeMessage: missing params') unless guest? and nonce? and ctext?
    @_loadRatchets(guest)
    # console.log "receiving from #{@_gPk(guest).toBase64()} => #{@getPubCommKey()} with #{@krGuest.confirmedKey.boxPk.toBase64()}"

    keyPairs = [
      # defult: confirmed local and guest
      [@krGuest.confirmedKey.boxPk, @krLocal.confirmedKey.boxSk],

      # Guest might not have switched to latest key yet
      [@krGuest.lastKey.boxPk, @krLocal.lastKey.boxSk],
      [@krGuest.confirmedKey.boxPk, @krLocal.lastKey.boxSk],
      [@krGuest.lastKey.boxPk, @krLocal.confirmedKey.boxSk]]

    for kp, i in keyPairs
      # console.log "key pair #{i}" if i>0
      r = @_tryKeypair nonce, ctext, kp[0], kp[1]
      return r if r?

    console.log 'RatchetBox decryption failed: message from unknown guest or ratchet out of sync'
    # TODO: Add ratchet key reset protocol for this guest here (send "reset" command)
    return null

  relayMessages: ->
    # First download pending messages
    super().then =>
      # Now, lets process ratchet-related information in these messages
      sendConfs = []

      for m in @lastDownload
        continue unless m.fromTag

        @_loadRatchets(m.fromTag)

        # If guests send use their nextKey for ratchet
        if m.msg?.nextKey?
          # save nextKey for that guest
          if @krGuest.confKey new Keys {boxPk: m.msg.nextKey.fromBase64()}
            # send guest confirmation that we got it
            sendConfs.push
              toTag: m.fromTag
              key: m.msg.nextKey
              msg:
                got_key: Nacl.h2_64(m.msg.nextKey)

        # If we got confirmation that our key is received
        # we should move it to nextKey for that guest

        if m.msg?.org_msg?.got_key?
          m.msg = m.msg.org_msg
          # do we saved that key locally?
          if @krLocal.isNextKeyHash m.msg.got_key.fromBase64()
            @krLocal.pushKey Nacl.makeKeyPair()
          m.msg = null
          # we processed it, nothing else to do with this message

        # restore usual @lastDownload structure
        if m.msg?
          m.msg = m.msg.org_msg

      # now we can send confirmations to guests that we got their key. Note
      # that got_key is a service message that wont advance the ratchet
      sendNext = =>
        if sendConfs.length > 0
          sc = sendConfs.shift()
          @relaySend(sc.toTag,sc.msg).then =>
            sendNext()
      sendNext()

  selfDestruct: (overseerAuthorized, withRatchet = false) ->
    return unless overseerAuthorized
    if withRatchet
      for guest in @keyRing.registry
        @_loadRatchets(guest)
        @krLocal.selfDestruct(withRatchet)
        @krGuest.selfDestruct(withRatchet)
    super(overseerAuthorized)

module.exports = RatchetBox
window.RatchetBox = RatchetBox if window.__CRYPTO_DEBUG
