# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT

# Extends several low level data types with utility functions
Utils = require 'utils'

# --- Extending functions of String class ---
Utils.include String,
  # string to an array of byte values
  toCodeArray: ->
    (s.charCodeAt() for s in @)

  # UTF8 conversions
  toUTF8: ->
    unescape encodeURIComponent @
  fromUTF8: ->
    decodeURIComponent escape @

  # Each char code to a Uint8Array
  toUint8Array: ->
    new Uint8Array @.toUTF8().toCodeArray()

  toUint8ArrayRaw: ->
    new Uint8Array @.toCodeArray()

  # From base64 string to Uint8Array
  fromBase64: ->
    new Uint8Array (atob @).toCodeArray()

  # Trim line feed chars
  trimLines: ->
    @.replace('\r\n', '').replace('\n', '').replace('\r', '')
# ---

# --- Extending functions of Array , Uint8Array , Uint16Array classes ---
for C in [Array , Uint8Array , Uint16Array]
  Utils.include C,
    # From JS arrays of char codes to a string
    # UTF16 chars above ASCII will generate codes above 255
    fromCharCodes: ->
      (String.fromCharCode(c) for c in @).join('')

    # From array of char codes to a base64 string
    toBase64: ->
      btoa @fromCharCodes()

    xorWith: (a) ->
      return null unless @.length is a.length
      new Uint8Array(c ^ a[i] for c, i in @)

    equal: (a2) ->
      return false if @.length isnt a2.length
      for v,i in @
        return false if v isnt a2[i]
      return true

    sample: ->
      return null unless @length > 0
      @[Math.floor(Math.random()*@length)]

Utils.include Uint8Array,
  # creates a new Uint8Array that is the concat of self & anotherArray
  concat: (anotherArray) ->
    tmp = new Uint8Array(@byteLength + anotherArray.byteLength)
    tmp.set(new Uint8Array(@), 0)
    tmp.set(anotherArray, @byteLength)
    return tmp

  # .fill() for setting the whole array to a particular value
  fillWith: (val) ->
    for v, i in @
      @[i] = val
    @ # allows call chaining
# --- end mixins ---

module.exports = {} # Nothing to export
