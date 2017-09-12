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
    # already occurred errors counter
    # relay is marked as disabled after RELAY_RETRY_REQUEST_ATTEMPTS
    @retriesCount = 0

    if @url and localStorage
      # timestamp until which relay will remain disabled
      @blockedTill = localStorage.getItem("blocked_#{@url}") or 0

    @_resetState() # until a succesful handshake
    # plugins can add their own commands to specific relays
    @RELAY_COMMANDS = [
      # message commands
      'count', 'upload', 'download', 'messageStatus', 'delete',
      # file commands
      'startFileUpload', 'uploadFileChunk', 'downloadFileChunk', 'fileStatus', 'deleteFile',
      # reserved for future use
      'getEntropy']

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
      @_request('start_session', @clientToken.toBase64()).then (data)=>
        # Will remove after token expires on relay
        # Call before assigning @relayToken to prevent accidental
        # reset of the newly assigned value.
        @_scheduleExpireSession()
        # relay responds with its own counter token. Until session is
        # established these 2 tokens are handshake id.
        lines = @_processData(data)
        @relayToken = lines[0].fromBase64()
        throw new Error("Wrong start_session from #{@url}") if lines.length != 2
        @diff = parseInt(lines[1])
        # console.log "diff #{@diff}"
        if @diff > 10
          console.log "Relay #{@url} requested difficulty #{@diff}. Session handshake may take longer."
        if @diff > 16
          console.log "Attempting handshake at difficulty #{@diff}! This may take a while"
        data

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
          h2.toBase64()
      else
        ensureNonceDiff = =>
          Nacl.random(32).then (nonce)=>
            Nacl.h2(handshake.concat(nonce)).then (h2)=>
              return nonce if Utils.arrayZeroBits(h2, @diff)
              ensureNonceDiff()
        next = ensureNonceDiff().then (nonce)=>
          nonce.toBase64()
      # make ajax request
      next.then (sessionHandshake)=>
        # We confirm handshake by sending back h2(clientToken, relay_token)
        @_request('verify_session', @h2ClientToken, sessionHandshake).then (d)=>
          # relay gives us back temp session key
          # masked by clientToken we started with
          relayPk = d.fromBase64()
          @relayKey = new Keys { boxPk: relayPk }
          @online = true
          delete @diff
          d
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
    mbx.createSessionKey(relayId, true).then (key)=>
      @_request('prove', mbx, key.boxPk).then (d)=>
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
    
    @_request('command', mbx, data).then (d)=>
      # no data in the response; return msg obj for tests.nonce
      throw new Error("#{@url} - #{cmd} error") unless d?
      @_processResponse(d, mbx, cmd, params)
    .catch (err)=>
      throw new Error("#{@url} - #{cmd} - #{err.message}")

  # Returns a Promise
  _request: (type, param1, param2)->
    Utils.ensure(type, param1)
    if @blockedTill? and @blockedTill > Date.now()
      throw new Error('Relay disabled till ' + new Date(parseInt(@blockedTill, 10)))

    if @retriesCount >= Config.RELAY_RETRY_REQUEST_ATTEMPTS
      @retriesCount = 0
      @blockedTill = Date.now() + Config.RELAY_BLOCKING_TIME
      localStorage.setItem("blocked_#{@url}", @blockedTill) if localStorage
      throw new Error('Relay out of reach')

    switch type
      when 'start_session'
        request = @_ajax('start_session', param1)
      when 'verify_session'
        request = @_ajax('verify_session', param1, param2)
      when 'prove'
        mbx = param1
        clientTempPk = param2
        mbx.keyRing.addTempGuest(@relayId(), @relayKey.strPubKey())
        delete @relayKey # now it belongs to the mailbox
        # Alice creates a 32 byte session signature as
        # h₂(a_temp_pk, relayToken, clientToken)
        sign = clientTempPk.concat(@relayToken).concat(@clientToken)
        request = Nacl.h2(sign).then (h2Sign)=>
          mbx.encodeMessage(@relayId(), h2Sign).then (inner)=>
            inner['pub_key'] = mbx.keyRing.getPubCommKey()
            mbx.encodeMessage(@relayId(), inner, true).then (outer)=>
              @_ajax('prove', @h2ClientToken, clientTempPk.toBase64(), outer.nonce, outer.ctext)
      when 'command'
        if param2.cmd == 'uploadFileChunk'
          # do not encode file chunk contents, as it's already encoded with symmetric encryption
          ctext = param2.ctext
          # clone payload object (original one may be reused in `catch` block)
          payload = Utils.extend {}, param2
          delete payload.ctext
          request = param1.encodeMessage(@relayId(), payload, true).then (message)=>
            @_ajax('command', param1.hpk(), message.nonce, message.ctext, ctext)
        else
          request = param1.encodeMessage(@relayId(), param2, true).then (message)=>
            @_ajax('command', param1.hpk(), message.nonce, message.ctext)
      else
        throw new Error("Unknown request type #{type}")

    request
    .then (data)=>
      # reset error counter if the request was successful
      @retriesCount = 0
      @blockedTill = 0
      data
    .catch (err)=>
      throw new Error('Bad Request') unless err.response?.status in [401, 500]
      # retry the request if there's a session error (401 Unauthorized)
      # or server is temporarily down (500 Internal Server Error)
      @retriesCount++
      @_resetState()
      # simply try to restart a session if there was an issue while establishing it
      if type is 'start_session'
        @getServerToken()
      else if type is 'verify_session'
        @openConnection()
      # otherwise, restart a session and run the same command again
      else if type is 'prove'
        @openConnection().then =>
          @connectMailbox(param1)
      else
        @openConnection().then =>
          @connectMailbox(param1).then =>
            @_request(type, param1, param2)

  # Returns a decrypt promise or direct response data
  _processResponse: (d, mbx, cmd, params)->
    datain = @_processData String(d)

    if cmd is 'delete'
      return JSON.parse(d)

    if cmd is 'upload'
      unless datain.length is 1 and datain[0].length is Config.RELAY_TOKEN_B64
        throw new Error("#{@url} - #{cmd}: Bad response")
      params.storage_token = d
      return params

    if cmd is 'messageStatus'
      unless datain.length is 1
        throw new Error("#{@url} - #{cmd}: Bad response")
      return parseInt datain[0]

    if cmd is 'downloadFileChunk'
      unless datain.length is 3
        throw new Error("#{@url} - #{cmd}: Bad response")
      nonce = datain[0]
      ctext = datain[1]
      return mbx.decodeMessage(@relayId(), nonce, ctext, true).then (response)=>
        response = JSON.parse(response)
        response.ctext = datain[2]
        response

    # rest of commands
    unless datain.length is 2
      throw new Error("#{@url} - #{cmd}: Bad response")
    nonce = datain[0]
    ctext = datain[1]
    
    if cmd in ['startFileUpload', 'fileStatus', 'uploadFileChunk', 'deleteFile']
      mbx.decodeMessage(@relayId(), nonce, ctext, true).then (response)=>
        JSON.parse(response)
    else
      mbx.decodeMessage(@relayId(), nonce, ctext, true)

  # Synchronous
  _processData: (d)->
    datain = d.split('\r\n')
    datain = d.split('\n') unless datain.length >= 2
    datain

  # Returns a Promise
  _ajax: (cmd, data...)=>
    Utils.ajax("#{@url}/#{cmd}", data.join('\r\n'))

  # --- Command wrappers ---

  # Returns a Promise
  count: (mbx)->
    @runCmd('count', mbx)

  # Returns a Promise
  upload: (mbx, toHpk, payload)->
    @runCmd('upload', mbx,
      to: toHpk.toBase64()
      payload: payload)

  # Returns a Promise
  messageStatus: (mbx, storage_token)->
    @runCmd('messageStatus', mbx,
      token: storage_token)

  # Returns a Promise
  download: (mbx)->
    @runCmd('download', mbx)

  # Returns a Promise
  delete: (mbx, nonceList)->
    @runCmd('delete', mbx,
      payload: nonceList)

  # Returns a Promise
  startFileUpload: (mbx, toHpk, fileSize, metadata)->
    @runCmd('startFileUpload', mbx,
      to: toHpk.toBase64()
      file_size: fileSize
      metadata: metadata)

  # Returns a Promise
  uploadFileChunk: (mbx, uploadID, part, totalParts, payload)->
    @runCmd('uploadFileChunk', mbx,
      uploadID: uploadID
      part: part
      # marker of last chunk, sent only once
      last_chunk: (totalParts - 1 == part)
      nonce: payload.nonce
      ctext: payload.ctext)

  # Returns a Promise
  fileStatus: (mbx, uploadID)->
    @runCmd('fileStatus', mbx,
      uploadID: uploadID)

  # Returns a Promise
  downloadFileChunk: (mbx, uploadID, chunk)->
    @runCmd('downloadFileChunk', mbx,
      uploadID: uploadID
      part: chunk)

  # Returns a Promise
  deleteFile: (mbx, uploadID)->
    @runCmd('deleteFile', mbx,
      uploadID: uploadID)

  # --- Token/session expiration ---

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
    mbx.timeToSessionExpiration(@relayId())

  # Synchronous
  _scheduleExpireSession: ->
    clearTimeout(@clientTokenExpiration) if @clientTokenExpiration
    @clientTokenExpirationStart = Date.now()
    @clientTokenExpiration = setTimeout =>
      @_resetState()
      @emit('relaytokentimeout')
    , Config.RELAY_TOKEN_TIMEOUT # Token will expire on the relay

module.exports = Relay
window.Relay = Relay if window.__CRYPTO_DEBUG
