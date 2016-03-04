// Copyright (c) 2015 Vault12, Inc.
// MIT License https://opensource.org/licenses/MIT

// The Web Worker script for JsNaclWebWorkerDriver

var js_nacl;
var hasCrypto = !!self.Crypto;

if(hasCrypto) {
  self.window = self;
}
else {
  self.rnd_queue = []
  self.window = {
    crypto: {
      getRandomValues: function(a) {
        buff = self.rnd_queue.shift()
        if(!buff) {
          console.log('no random ' + a.length);
          throw new Error('no random ' + a.length);
        }
        diff = buff.length - a.length;
        if(diff)
          a.set(buff.subarray(diff));
        else
          a.set(buff);
      }
    }
  }
}

var api = {
  init: function(e) {

    importScripts(e.data.naclPath);
    js_nacl = nacl_factory.instantiate(e.data.heapSize);

    e.data.api.forEach(function(f) {
      api[f] = function(e) {
        try {

          // console.log(f);
          if(self.rnd_queue && e.data.rnd)
            self.rnd_queue.push(e.data.rnd);

          res = js_nacl[f].apply(js_nacl, e.data.args);
          refs = []
          // rez = typeof(res) === 'object' ? res : { k: res };
          // for(var k in rez)
          //   if(rez[k] instanceof Uint8Array)
          //     refs.push(rez[k].buffer)
          self.postMessage({ cmd: f, res: res }, refs);
        }
        catch(e) {
          self.postMessage({ cmd: f, error: true, message: e.stack || e.message || e });
        }
      }
    });
    self.postMessage({ cmd: 'init', hasCrypto: hasCrypto });
  }
};

self.addEventListener('message', function(e) {
  func = api[e.data.cmd]
  if(!func)
    throw new Error('invalid command');
  func(e);
});
