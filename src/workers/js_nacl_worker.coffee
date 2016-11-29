# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
# The Web Worker script for JsNaclWebWorkerDriver

hasCrypto = ! !self.Crypto
if hasCrypto
  self.window = self
else
  self.rnd_queue = []
  self.window = crypto: getRandomValues: (a) ->
    buff = self.rnd_queue.shift()
    if !buff
      console.log 'no random ' + a.length
      throw new Error('no random ' + a.length)
    diff = buff.length - (a.length)
    if diff
      a.set buff.subarray(diff)
    else
      a.set buff
    return

api = init: (e) ->
  importScripts e.data.naclPath
  js_nacl = nacl_factory.instantiate(e.data.heapSize)
  e.data.api.forEach (f) ->

    api[f] = (e) ->
      try
        if self.rnd_queue and e.data.rnd
          self.rnd_queue.push e.data.rnd
        self.postMessage
          cmd: f
          res: js_nacl[f].apply(js_nacl, e.data.args)
      catch e
        self.postMessage
          cmd: f
          error: true
          message: e.stack or e.message or e
      return

    return
  self.postMessage
    cmd: 'init'
    hasCrypto: hasCrypto
  return

self.addEventListener 'message', (e) ->
  func = api[e.data.cmd]
  if !func
    throw new Error('invalid command')
  func e
  return