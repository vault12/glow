# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Utils = require 'utils'

# Nacl driver for the js-nacl emscripten implementation run in a Web Worker
class JsNaclWebWorkerDriver

  constructor: (
    worker_path = '/dist/js_nacl_worker.js',
    js_nacl_path = '/node_modules/js-nacl/lib/nacl_factory.js',
    heap_size = 2 ** 23)->

    random_reqs =
      random_bytes: 32
      crypto_box_keypair: 32
      crypto_box_random_nonce: 24
      crypto_secretbox_random_nonce: 24

    hasCrypto = false
    api = []
    queues = {}
    worker = new Worker(worker_path)

    @.crypto_secretbox_KEYBYTES = 32 # TODO: get from js_nacl

    require('nacl').API.forEach (f)=>
      queue = []
      queues[f] = queue
      api.push(f)

      @[f] = ->
        p = Utils.promise (res, rej)->
          queue.push
            resolve: res
            reject: rej

        args = Array.prototype.slice.call(arguments)
        refs = []
        # args.forEach (arg)->
        #   refs.push(arg.buffer) if arg instanceof Uint8Array

        rnd = null
        if !hasCrypto
          n = random_reqs[f]
          if n
            rnd = new Uint8Array(32) # always use 32 otherwise stress tests fail
            crypto.getRandomValues(rnd)

        worker.postMessage({ cmd: f, args: args, rnd: rnd }, refs)
        p

    onmessage2 = (e)->
      queue = queues[e.data.cmd]
      if e.data.error
        queue.shift().reject(new Error(e.data.message))
      else
        queue.shift().resolve(e.data.res)

    worker.onmessage = (e)->
      throw new Error() unless e.data.cmd == 'init'
      hasCrypto = e.data.hasCrypto
      console.log('js nacl web worker initialized; hasCrypto: ' + hasCrypto)
      worker.onmessage = onmessage2

    worker.postMessage
      cmd: 'init'
      naclPath: js_nacl_path
      heapSize: heap_size
      api: api

module.exports = JsNaclWebWorkerDriver
window.JsNaclDriver = JsNaclWebWorkerDriver if window.__CRYPTO_DEBUG
