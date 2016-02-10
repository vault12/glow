# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config       = require 'config'
Keys         = require 'keys'
Nacl         = require 'nacl'
Utils        = require 'utils'
EventEmitter = require('events').EventEmitter

class Relay extends EventEmitter
  # skip url for offline testing
  constructor: (@url = null) ->
    @_resetState() # until a succesful handshake
    @lastError = null

    # plugins can add their own commands to specific relays
    @RELAY_COMMANDS = ['count', 'upload', 'download', 'delete']

  openConnection: ->
    # exchange tokens with a relay and get a temp session key for this relay
    @getServerToken().then =>
      @getServerKey()

  getServerToken: ->
    throw new Error('getServerToken - no url') unless @url
    @lastError = null

    # Generate a clientToken. It will be used as part of handshake id with relay
    @clientToken = Nacl.random(Config.RELAY_TOKEN_LEN) unless @clientToken

    # sanity check the client token
    if @clientToken and @clientToken.length isnt Config.RELAY_TOKEN_LEN
      throw new Error("Token must be #{Config.RELAY_TOKEN_LEN} bytes")

    @_ajax('start_session', @clientToken.toBase64()).then (data) =>
      # relay responds with its own counter token. Until session is
      # established these 2 tokens are handshake id.
      lines = @_processData data
      @relayToken = lines[0].fromBase64()
      @diff = if lines.length is 2 then parseInt(lines[1]) else 0

      @_scheduleExpireSession()
      # Will remove after token expires on relay
      if @diff > 4
        console.log "Relay #{@url} requested difficulty #{@diff}. Session handshake may take longer."
      if @diff > 16
        console.log "Attempting handshake at difficulty #{@diff}! This may take a while"

  getServerKey: ->
    throw new Error('getServerKey - missing params') unless @url and @clientToken and @relayToken
    @lastError = null

    # After the clientToken is sent to reley, we use only the h2() of it
    @h2ClientToken = Nacl.h2(@clientToken).toBase64()

    handshake = @clientToken.concat @relayToken
    if @diff is 0
      sessionHandshake = Nacl.h2(handshake).toBase64()
    else
      nonce = Nacl.random 32
      until Utils.arrayZeroBits(Nacl.h2(handshake.concat nonce), @diff)
        nonce = Nacl.random 32
      sessionHandshake = nonce.toBase64()

    # We confirm handshake by sending back h2(clientToken, relay_token)
    @_ajax('verify_session', "#{@h2ClientToken}\r\n#{sessionHandshake}\r\n").then (d) =>
      # relay gives us back temp session key
      # masked by clientToken we started with
      relayPk = d.fromBase64()
      @relayKey = new Keys { boxPk: relayPk }
      @online = true
      # @_scheduleExpireSession Config.RELAY_SESSION_TIMEOUT
      # Will remove after the key expires on this relay

  connectMailbox: (mbx) ->
    throw new Error('connectMailbox - missing params') unless mbx? and @online and @relayKey? and @url?
    @lastError = null

    relayId = "relay_#{@url}" # also used in MailBox.isConnectedToRelay()
    clientTemp = mbx.createSessionKey(relayId).boxPk
    mbx.keyRing.addTempGuest relayId, @relayKey.strPubKey()
    delete @relayKey # now it belongs to the mailbox

    maskedClientTempPk = clientTemp.toBase64()

    # Alice creates a 32 byte session signature as
    # h₂(a_temp_pk,relay_token, clientToken)
    sign = clientTemp.concat(@relayToken).concat(@clientToken)
    h2Sign = Nacl.h2(sign)

    inner = mbx.encodeMessage relayId, h2Sign
    inner['pub_key'] = mbx.keyRing.getPubCommKey()
    outer = mbx.encodeMessage "relay_#{@url}", inner, true

    @_ajax('prove',
      "#{@h2ClientToken}\r\n" +
      "#{maskedClientTempPk}\r\n" +
      "#{outer.nonce}\r\n" +
      "#{outer.ctext}")
    .then (d)=>
      # console.log "#{@url} => #{d} messages"
      # return relayId, the mailbox emits 'sessionTimeout'
      # with that relayId (sess_id) as a parameter.
      relayId

  runCmd: (cmd, mbx, params = null) ->
    throw new Error('runCmd - missing params') unless cmd? and mbx?
    unless cmd in @RELAY_COMMANDS
      throw new Error("Relay #{@url} doesn't support #{cmd}")
    data =
      cmd: cmd
    data = Utils.extend data, params if params
    message = mbx.encodeMessage "relay_#{@url}", data, true

    @_ajax('command',
      "#{mbx.hpk().toBase64()}\r\n" +
      "#{message.nonce}\r\n" +
      "#{message.ctext}")
    .then (d)=>
      return if cmd in ['upload'] # no data in the response
      throw new Error("#{@url} - #{cmd} error") unless d?
      if cmd in ['count','download']
        @result = @_processResponse(d, mbx, cmd)
      else
        @result = JSON.parse d

  _processResponse: (d, mbx, cmd) ->
    datain = @_processData d
    unless datain.length is 2
      throw new Error("#{@url} - #{cmd}: Bad response")
    nonce = datain[0]
    ctext = datain[1]
    mbx.decodeMessage("relay_#{@url}", nonce, ctext, true)

  _processData: (d) ->
    datain = d.split('\r\n')
    datain = d.split('\n') unless datain.length >= 2
    return datain

  # Command wrappers

  count: (mbx) ->
    @runCmd('count', mbx)

  upload: (mbx, toHpk, payload) ->
    @runCmd('upload', mbx,
      to: toHpk.toBase64()
      payload: payload)

  download: (mbx) ->
    @runCmd('download', mbx)

  delete: (mbx, nonceList) ->
    @runCmd('delete', mbx,
      payload: nonceList)

  # Deletes all local session tokens
  # Our information has expired on the relay and a new session has to be
  # established with all new tokens
  _resetState: ->
    @clientToken = null
    @online = false
    @relayToken = null
    @relayKey = null
    @clientTokenExpiration = null
    @clientTokenExpirationStart = 0

  # Allows for preemptive session renewal to avoid
  # timeouts in the middle of a relay check
  timeToTokenExpiration: ->
    Math.max(Config.RELAY_TOKEN_TIMEOUT - (Date.now() - @clientTokenExpirationStart), 0)

  _scheduleExpireSession: ->
    clearTimeout(@clientTokenExpiration) if @clientTokenExpiration
    @clientTokenExpirationStart = Date.now()
    @clientTokenExpiration = setTimeout( =>
      @_resetState()
      @emit('relaytokentimeout')
    , Config.RELAY_TOKEN_TIMEOUT) # Token will expire on the relay

  _ajax: (cmd, data) =>
    Utils.ajax "#{@url}/#{cmd}", data
    # TODO update for various implementations or make them provide it extra:
    # .catch e
    #   console.error @lastError = "#{type}/#{xhr.status} - #{error}"
    #   @online = false
    #   throw e

module.exports = Relay
window.Relay = Relay if window.__CRYPTO_DEBUG
