# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config       = require 'config'
Keys         = require 'keys'
Nacl         = require 'nacl'
Utils        = require 'utils'
EventEmitter = require('events').EventEmitter

class Relay extends EventEmitter

  # skip url for offline testing
  # Synchronous
  constructor: (@url = null)->
    @_resetState() # until a succesful handshake
    # plugins can add their own commands to specific relays
    @RELAY_COMMANDS = ['count', 'upload', 'download', 'delete']

  # Returns a Promise
  openConnection: ->
    # exchange tokens with a relay and get a temp session key for this relay
    @getServerToken().then =>
      @getServerKey()

  # Returns a Promise
  getServerToken: ->
    Utils.ensure(@url)
    # Generate a clientToken. It will be used as part of handshake id with relay
    unless @clientToken
      next = Nacl.random(Config.RELAY_TOKEN_LEN).then (clientToken)=>
        @clientToken = clientToken
    next = (next || Utils.resolve()).then =>
      # sanity check the client token
      if @clientToken and @clientToken.length isnt Config.RELAY_TOKEN_LEN
        throw new Error("Token must be #{Config.RELAY_TOKEN_LEN} bytes")
      # avoid resetting the @clientToken in case the following ajax call takes
      # a longer time to complete
      clearTimeout(@clientTokenExpiration) if @clientTokenExpiration
      # make ajax request
      @_ajax('start_session', @clientToken.toBase64()).then (data)=>
        # Will remove after token expires on relay
        # Call before assigning @relayToken to prevent accidental
        # reset of the newly assigned value.
        @_scheduleExpireSession()
        # relay responds with its own counter token. Until session is
        # established these 2 tokens are handshake id.
        lines = @_processData(data)
        @relayToken = lines[0].fromBase64()
        @diff = if lines.length is 2 then parseInt(lines[1]) else 0
        if @diff > 4
          console.log "Relay #{@url} requested difficulty #{@diff}. Session handshake may take longer."
        if @diff > 16
          console.log "Attempting handshake at difficulty #{@diff}! This may take a while"

  # Returns a Promise
  getServerKey: ->
    Utils.ensure(@url, @clientToken, @relayToken)
    # After the clientToken is sent to reley, we use only the h2() of it
    Nacl.h2(@clientToken).then (h2ClientToken)=>
      @h2ClientToken = h2ClientToken.toBase64()
      # compute session handshake
      handshake = @clientToken.concat(@relayToken)
      if @diff is 0
        next = Nacl.h2(handshake).then (h2)=>
          sessionHandshake = h.toBase64()
      else
        ensureNonceDiff = =>
          Nacl.random(32).then (nonce)=>
            Nacl.h2(handshake.concat(nonce)).then (h2)=>
              return nonce if Utils.arrayZeroBits(h2, @diff)
              ensureNonceDiff()
        next = ensureNonceDiff().then (nonce)=>
          sessionHandshake = nonce.toBase64()
      # make ajax request
      next.then =>
        # We confirm handshake by sending back h2(clientToken, relay_token)
        @_ajax('verify_session', "#{@h2ClientToken}\r\n#{sessionHandshake}\r\n").then (d)=>
          # relay gives us back temp session key
          # masked by clientToken we started with
          relayPk = d.fromBase64()
          @relayKey = new Keys { boxPk: relayPk }
          @online = true
          # @_scheduleExpireSession Config.RELAY_SESSION_TIMEOUT
          # Will remove after the key expires on this relay

  # Synchronous
  relayId: ->
    Utils.ensure(@url)
    "relay_#{@url}"

  # Returns a Promise
  connectMailbox: (mbx)->
    Utils.ensure(mbx, @online, @relayKey, @url)
    relayId = @relayId()
    clientTemp = mbx.createSessionKey(relayId, true).then (key)=>
      clientTemp = key.boxPk
      mbx.keyRing.addTempGuest(relayId, @relayKey.strPubKey())
      delete @relayKey # now it belongs to the mailbox
      maskedClientTempPk = clientTemp.toBase64()
      # Alice creates a 32 byte session signature as
      # h₂(a_temp_pk,relay_token, clientToken)
      sign = clientTemp.concat(@relayToken).concat(@clientToken)
      Nacl.h2(sign).then (h2Sign)=>
        mbx.encodeMessage(relayId, h2Sign).then (inner)=>
          inner['pub_key'] = mbx.keyRing.getPubCommKey()
          mbx.encodeMessage("relay_#{@url}", inner, true).then (outer)=>
            @_ajax('prove',
              "#{@h2ClientToken}\r\n" +
              "#{maskedClientTempPk}\r\n" +
              "#{outer.nonce}\r\n" +
              "#{outer.ctext}")
            .then (d)=>
              # console.log "#{@url} => #{d} messages"
              # return relayId, the mailbox emits 'relaysessiontimeout'
              # with that relayId (sess_id) as a parameter.
              relayId

  # Returns a Promise
  runCmd: (cmd, mbx, params = null)->
    Utils.ensure(cmd, mbx)
    unless cmd in @RELAY_COMMANDS
      throw new Error("Relay #{@url} doesn't support #{cmd}")
    data =
      cmd: cmd
    data = Utils.extend(data, params) if params
    mbx.encodeMessage("relay_#{@url}", data, true).then (message)=>
      mbx.hpk().then (hpk)=>
        @_ajax('command',
          "#{hpk.toBase64()}\r\n" +
          "#{message.nonce}\r\n" +
          "#{message.ctext}")
        .then (d)=>
          return if cmd is 'upload' # no data in the response
          throw new Error("#{@url} - #{cmd} error") unless d?
          if cmd in ['count', 'download']
            @_processResponse(d, mbx, cmd)
          else
            JSON.parse(d)

  # Returns a Promise
  _processResponse: (d, mbx, cmd)->
    datain = @_processData d
    unless datain.length is 2
      throw new Error("#{@url} - #{cmd}: Bad response")
    nonce = datain[0]
    ctext = datain[1]
    mbx.decodeMessage("relay_#{@url}", nonce, ctext, true)

  # Synchronous
  _processData: (d)->
    datain = d.split('\r\n')
    datain = d.split('\n') unless datain.length >= 2
    datain

  # Command wrappers

  # Returns a Promise
  count: (mbx)->
    @runCmd('count', mbx)

  # Returns a Promise
  upload: (mbx, toHpk, payload)->
    @runCmd('upload', mbx,
      to: toHpk.toBase64()
      payload: payload)

  # Returns a Promise
  download: (mbx)->
    @runCmd('download', mbx)

  # Returns a Promise
  delete: (mbx, nonceList)->
    @runCmd('delete', mbx,
      payload: nonceList)

  # Deletes all local session tokens
  # Our information has expired on the relay and a new session has to be
  # established with all new tokens
  # Synchronous
  _resetState: ->
    @clientToken = null
    @online = false
    @relayToken = null
    @relayKey = null
    @clientTokenExpiration = null
    @clientTokenExpirationStart = 0

  # Allows for preemptive client token renewal to avoid
  # timeouts in the middle of a relay check
  # Synchronous
  timeToTokenExpiration: ->
    Math.max(Config.RELAY_TOKEN_TIMEOUT - (Date.now() - @clientTokenExpirationStart), 0)

  # Allows for preemptive mailbox session renewal to avoid
  # timeouts in the middle of a relay check
  # Synchronous
  timeToSessionExpiration: (mbx)->
    mbx.timeToSessionExpiration("relay_#{@url}")

  # Synchronous
  _scheduleExpireSession: ->
    clearTimeout(@clientTokenExpiration) if @clientTokenExpiration
    @clientTokenExpirationStart = Date.now()
    @clientTokenExpiration = setTimeout =>
      @_resetState()
      @emit('relaytokentimeout')
    , Config.RELAY_TOKEN_TIMEOUT # Token will expire on the relay

  # Returns a Promise
  _ajax: (cmd, data)=>
    Utils.ajax("#{@url}/#{cmd}", data)

module.exports = Relay
window.Relay = Relay if window.__CRYPTO_DEBUG
