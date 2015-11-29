# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

Utils       = require 'utils'
Nacl        = require 'nacl'
Keys        = require 'keys'
KeyRing     = require 'keyring'
KeyRatchet  = require 'keyratchet'
Mailbox     = require 'mailbox'

class RatchetBox extends Mailbox

  _loadRatchets: (guest) ->
    # every guest will have a next confirmed key that we can reliably use, and
    # a next key we are awaiting confirmation for. In local storage we will
    # reference guests by the usual guest hpk=h2(pk)
    gHpk = @_gHpk(guest).toBase64()

    # if we have confirmed ratchet key we use it, otherwise
    # fallback to our @comm_key
    @kr_local = new KeyRatchet("local_#{gHpk}_for_#{@hpk().toBase64()}",
      @keyRing, @keyRing.comm_key)

    @kr_guest = new KeyRatchet("guest_#{gHpk}_for_#{@hpk().toBase64()}",
      @keyRing, @keyRing.getGuestKey guest)

  relay_send: (guest, m) ->
    throw new Error('rbx: relay_send - no open relay') unless @lastRelay
    throw new Error('rbx: relay_send - missing params') unless guest and m

    # now we have 2 keys - the next key to send to a guest, and the last
    # confirmed key we can use for encryption - it may be the comm identity key
    # if we are at the start of a ratchet
    @_loadRatchets(guest)

    # Save original message and include ratchet information along
    msg = {org_msg: m}
    # Add next key to org_msg unless its a key confirmation message
    msg['next_key'] = @kr_local.next_key.strPubKey() unless m.got_key?

    # Full message or just a 'got_key' confirmation?
    if not m.got_key?
      # Use the confirmed ratchet key we got from the guest, or it will default
      # to her public comm_key
      enc_msg = @rawEncodeMessage(msg, @kr_guest.conf_key.boxPk, @kr_local.conf_key.boxSk)
      @lastMsg = enc_msg
    else
      # sending key confirmation using last key
      enc_msg = @rawEncodeMessage(msg, @kr_guest.last_key.boxPk, @kr_local.conf_key.boxSk)

    # console.log "sent #{@getPubCommKey()} => #{@_gPk(guest).toBase64()} with #{@kr_guest.conf_key.boxPk.toBase64()} | nonce = #{enc_msg.nonce}"
    @lastRelay.upload(@,Nacl.h2(@_gPk guest), enc_msg)

  _try_keypair: (nonce, ctext, pk, sk) ->
    try
      return @rawDecodeMessage nonce.fromBase64(),
        ctext.fromBase64(), pk, sk
    catch e
      return null

  decodeMessage: (guest, nonce, ctext, session = false, skTag = null) ->
    return super(guest, nonce, ctext, session, skTag) if session
    throw new Error('decodeMessage: missing params') unless guest? and nonce? and ctext?
    @_loadRatchets(guest)
    # console.log "receiving from #{@_gPk(guest).toBase64()} => #{@getPubCommKey()} with #{@kr_guest.conf_key.boxPk.toBase64()}"

    key_pairs = [
      # defult: confirmed local and guest
      [@kr_guest.conf_key.boxPk, @kr_local.conf_key.boxSk],

      # Guest might not have switched to latest key yet
      [@kr_guest.last_key.boxPk, @kr_local.last_key.boxSk],
      [@kr_guest.conf_key.boxPk, @kr_local.last_key.boxSk],
      [@kr_guest.last_key.boxPk, @kr_local.conf_key.boxSk]]

    for kp, i in key_pairs
      # console.log "key pair #{i}" if i>0
      r = @_try_keypair nonce, ctext, kp[0], kp[1]
      return r if r?

    console.log 'RatchetBox decryption failed: message from unknown guest or ratchet out of sync'
    # TODO: Add ratchet key reset protocol for this guest here (send "reset" command)
    return null

  relay_messages: ->
    # First download pending messages
    super().then =>
      # Now, lets process ratchet-related information in these messages
      send_confs = []

      for m in @lastDownload
        continue unless m.fromTag

        @_loadRatchets(m.fromTag)

        # If guests send use their next_key for ratchet
        if m.msg?.next_key?
          # save next_key for that guest
          if @kr_guest.confKey new Keys {boxPk: m.msg.next_key.fromBase64()}
            # send guest confirmation that we got it
            send_confs.push
              toTag: m.fromTag
              key: m.msg.next_key
              msg:
                got_key: Nacl.h2_64(m.msg.next_key)

        # If we got confirmation that our key is received
        # we should move it to next_key for that guest

        if m.msg?.org_msg?.got_key?
          m.msg = m.msg.org_msg
          # do we saved that key locally?
          if @kr_local.isNextKeyHash m.msg.got_key.fromBase64()
            @kr_local.pushKey Nacl.makeKeyPair()
          m.msg = null
          # we processed it, nothing else to do with this message

        # restore usual @lastDownload structure
        if m.msg?
          m.msg = m.msg.org_msg

      # now we can send confirmations to guests that we got their key. Note
      # that got_key is a service message that wont advance the ratchet
      sendNext = =>
        if send_confs.length > 0
          sc = send_confs.shift()
          @relay_send(sc.toTag,sc.msg).then =>
            sendNext()
      sendNext()

  selfDestruct: (overseerAuthorized, withRatchet = false) ->
    return unless overseerAuthorized
    if withRatchet
      for guest in @keyRing.registry
        @_loadRatchets(guest)
        @kr_local.selfDestruct(withRatchet)
        @kr_guest.selfDestruct(withRatchet)
    super(overseerAuthorized)

module.exports = RatchetBox
window.RatchetBox = RatchetBox if window.__CRYPTO_DEBUG
