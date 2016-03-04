# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Low level basic utilities and mixins
# zepto = require 'zepto' # minimalist js library. similar syntax to jQuery
Config = require 'config'

class Utils

  # --- Mixins ---

  # Wraps http://zeptojs.com/#$.extend - provided so that you can swap
  # zepto for another js library that doesn't have the same extend behavior.
  # Uses default impl if $.extend not available.
  @extend = (target, source) ->
    if $?.extend
      $.extend target, source
    else
      for key, val of source
        if source[key] isnt undefined
          target[key] = source[key]
      target

  @map = (array, func) ->
    if $?.map
      $?.map array, func
    else
      # http://caniuse.com/#search=map
      Array::map.apply array, [ func ]

  # convenience function for extending an object by class
  @include = (klass, mixin) ->
    @extend klass.prototype, mixin

  # extracts just the name portion as a string of an object's class
  @type = (obj) ->
    return 'undefined' if obj is undefined
    return 'null' if obj is null
    Object::toString.call(obj)
      .replace('[', '').replace(']', '').split(' ')[1]

  # --- Ajax ---

  @ajaxImpl: null

  # see: Main.setAjaxImpl()
  @setAjaxImpl: (ajaxImpl)->
    @ajaxImpl = ajaxImpl

  # wraps http://zeptojs.com/#$.ajax - provided so that if you can swap
  # zepto for another js library that doesn't have the same ajax behavior
  @ajax: (url, data) ->
    @setDefaultAjaxImpl() if not @ajaxImpl
    @ajaxImpl url, data

  @setDefaultAjaxImpl: ->
    # try to auto-set some default implementations here, if present
    # Axios + Promise; https://github.com/mzabriskie/axios
    if axios?
      @setAjaxImpl (url, data)->
        axios.request
          url: url
          method: 'post'
          headers:
            'Accept': 'text/plain'
            'Content-Type': 'text/plain'
          data: data
          responseType: 'text'
          timeout: Config.RELAY_AJAX_TIMEOUT
        .then (response)->
          response.data
    # Q.xhr + Q; https://github.com/nathanboktae/q-xhr
    else if Q?.xhr
      @setAjaxImpl (url, data)->
        Q.xhr
          method: 'POST'
          url: url
          headers:
            'Accept': 'text/plain'
            'Content-Type': 'text/plain'
          data: data
          responseType: 'text'
          timeout: Config.RELAY_AJAX_TIMEOUT
          disableUploadProgress: true # https://github.com/nathanboktae/q-xhr/issues/12
        .then (response)->
          response.data
    # Zepto; https://github.com/madrobby/zepto
    # Note: broken Promises - will not catch exceptions in .then/.done
    else if $?.ajax && $?.Deferred
      @setAjaxImpl (url, data)->
        $.ajax
          url: url
          type: 'POST'
          dataType: 'text'
          timeout: Config.RELAY_AJAX_TIMEOUT
          context: @
          error: console.log
          contentType: 'text/plain'
          data: data
    else
      throw new Error('Unable to set default Ajax implementation.')

  # --- Promises ---

  @promiseImpl: null

  # see: Main.setPromiseImpl()
  @setPromiseImpl: (promiseImpl)->
    @promiseImpl = promiseImpl

  @getPromiseImpl: ->
    @setDefaultPromiseImpl() if not @promiseImpl
    @promiseImpl

  @setDefaultPromiseImpl: ->
    if Promise?
      @setPromiseImpl
        promise: (resolver)->
          new Promise(resolver)
        all: (arr)->
          Promise.all(arr)
    else if Q?
      @setPromiseImpl
        promise: (resolver)->
          Q.promise(resolver)
        all: (arr)->
          Q.all(arr)
    else
      throw new Error('Unable to set default Promise implementation.')

  # --- Utilities ---

  # calls func after the specified delay in milliseconds
  @delay: (milliseconds, func) ->
    setTimeout(func, milliseconds)

  # splits an integer into an array of bytes
  @itoa: (n) ->
    return new Uint8Array(0 for i in [0..7]) if n <= 0
    [floor, pw, lg] = [Math.floor, Math.pow, Math.log] # aliases

    top = floor lg(n) / lg(256)
    new Uint8Array( floor(n / pw(256, i)) % 256 for i in [top..0] )

  # returns true if the rightmost n bits of a byte are 0
  @firstZeroBits: (byte, n) ->
    byte is ((byte >> n) << n)

  # check whether the rightmost difficulty bits of an Uint8Array are 0, where
  # the lowest indexes of the array represent those rightmost bits. Thus if
  # the difficulty is 17, then arr[0] and arr[1] should be 0, as should the
  # rightmost bit of arr[2]. This is used for our difficulty settings in Zax to
  # reduce burden on a busy server by ensuring clients have to do some
  # additional work during the session handshake
  @arrayZeroBits: (arr, diff) ->
    rmd = diff
    for i in [0..(1 + diff / 8)]
      a = arr[i]
      return true if rmd <= 0
      if rmd > 8
        rmd -= 8
        return false if a > 0
      else
        return @firstZeroBits(a, rmd)
    return false

  # Prints a current stack trace to the console
  @logStack: (err) ->
    err = new Error('stackLog') unless err
    s = err.stack.replace(/^[^\(]+?[\n$]/gm, '')
    .replace(/^\s+at\s+/gm, '')
    .replace(/^Object.<anonymous>\s*\(/gm, '{anonymous}()@')
    .split('\n')
    console.log "#{i}: #{sl}" for sl, i in s

  # Create a resolved Promise
  @resolve: (value)->
    @getPromiseImpl().promise (res, rej)-> res(value)

  # Create a rejected Promsie
  @reject: (error)->
    @getPromiseImpl().promise (res, rej)-> rej(error)

  # Create a deferred Promise
  @promise: (resolver)->
    @getPromiseImpl().promise (resolver)

  # Wait for all promises
  @all: (promises)->
    @getPromiseImpl().all(promises)

  # Keep executing promiseFunc on each element of the array,
  # until it returns a truish value.
  @serial: (arr, promiseFunc)->
    i = 0
    iter = (elem)=>
      promiseFunc(elem).then (res)->
        return res if res
        iter(arr[++i]) if i < arr.length
    iter(arr[++i])

  # Ensure every argument is truish
  @ENSURE_ERROR_MSG = 'invalid arguments'
  @ensure: ()->
    for a in arguments
      throw new Error(@ENSURE_ERROR_MSG) unless a

module.exports = Utils
window.Utils = Utils if window.__CRYPTO_DEBUG
