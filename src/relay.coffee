# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config = require 'config'
Keys = require 'keys'
Nacl = require 'nacl'
Utils = require 'utils'

class Relay
  # skip url for offline testing
  constructor: (@url = null) ->
    @_reset_state() # until a succesful handshake
    @lastError = null

    # plugins can add their own commands to specific relays
    # TODO: why not re-use what is in config?
    @RELAY_COMMANDS = ['count', 'upload', 'download', 'delete']

  openConnection: ->
    # exchange tokens with a relay and get a temp session key for this relay
    @getServerToken().then =>
      @getServerKey()

  getServerToken: ->
    throw new Error('getServerToken - no url') unless @url
    @lastError = null

    # Generate a client_token. It will be used as part of handshake id with relay
    @client_token = Nacl.random(Config.RELAY_TOKEN_LEN) unless @client_token

    # sanity check the client token
    if @client_token and @client_token.length isnt Config.RELAY_TOKEN_LEN
      throw new Error("Token must be #{Config.RELAY_TOKEN_LEN} bytes")

    @_ajax('start_session', @client_token.toBase64()).then (data)=>
      # relay responds with its own counter token. Until session is
      # established these 2 tokens are handshake id.
      lines = @_processData data
      @relay_token = lines[0].fromBase64()
      @diff = if lines.length == 2 then parseInt(lines[1]) else 0
      @h2_relay_token = Nacl.h2 @relay_token
      @_schedule_expire_session Config.RELAY_TOKEN_TIMEOUT
      # Will remove after token expires on relay
      if @diff > 4
        console.log "Relay #{@url} requested difficulty #{@diff}. Session handshake may take longer."
      if @diff > 16
        console.log "Attempting handshake at difficulty #{@diff}! This may take a while"

  getServerKey: ->
    throw new Error('getServerKey - missing params') unless @url and @client_token and @relay_token
    @lastError = null

    # After the client_token is sent to reley, we use only the h2() of it
    @h2_client_token = Nacl.h2(@client_token).toBase64()

    handshake = @client_token.concat @relay_token
    if @diff is 0
      sess_hs = Nacl.h2(handshake).toBase64()
    else
      nonce = Nacl.random 32
      until Utils.arrayZeroBits(Nacl.h2(handshake.concat nonce), @diff)
        nonce = Nacl.random 32
      sess_hs = nonce.toBase64()

    # We confirm handshake by sending back h2(client_token, relay_token)
    @_ajax('verify_session', "#{@h2_client_token}\r\n#{sess_hs}\r\n").then (d)=>
      # relay gives us back temp session key
      # masked by client_token we started with
      relay_pk = d.fromBase64()
      @relay_key = new Keys { boxPk: relay_pk }
      @online = true
      # @_schedule_expire_session Config.RELAY_SESSION_TIMEOUT
      # Will remove after the key expires on this relay

  connectMailbox: (mbx) ->
    throw new Error('connectMailbox - missing params') unless mbx? and @online and @relay_key? and @url?
    @lastError = null

    relay_id = "relay_#{@url}"
    client_temp = mbx.createSessionKey(relay_id).boxPk
    mbx.keyRing.addTempGuest relay_id, @relay_key.strPubKey()
    delete @relay_key # now it belongs to the mailbox

    masked_client_temp_pk = client_temp.toBase64()

    # Alice creates a 32 byte session signature as
    # h₂(a_temp_pk,relay_token, client_token)
    sign = client_temp.concat(@relay_token).concat(@client_token)
    h2_sign = Nacl.h2(sign)

    inner = mbx.encodeMessage relay_id, h2_sign
    inner['pub_key'] = mbx.keyRing.getPubCommKey()
    outer = mbx.encodeMessage "relay_#{@url}", inner, true

    @_ajax('prove',
      "#{@h2_client_token}\r\n" +
      "#{masked_client_temp_pk}\r\n" +
      "#{outer.nonce}\r\n" +
      "#{outer.ctext}")
    .then (d)=>
      # console.log "#{@url} => #{d} messages"

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

  delete: (mbx,nonce_list) ->
    @runCmd('delete', mbx,
      payload: nonce_list)

  # Deletes all local session tokens
  # Our information has expired on the relay and a new session has to be
  # established with all new tokens
  _reset_state: ->
    @client_token = null
    @online = false
    @relay_token = null
    @relay_key = null
    @client_token_expiration = null

  _schedule_expire_session: (tout) ->
    clearTimeout(@client_token_expiration) if @client_token_expiration
    @client_token_expiration = setTimeout( =>
      @_reset_state()
    , tout) # Token will expire on the relay

  _ajax: (cmd,data) =>
    Utils.ajax "#{@url}/#{cmd}", data
    # TODO update for various implementations or make them provide it extra:
    # .catch e
    #   console.error @lastError = "#{type}/#{xhr.status} - #{error}"
    #   @online = false
    #   throw e

module.exports = Relay
window.Relay = Relay if window.__CRYPTO_DEBUG
