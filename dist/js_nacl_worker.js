(function() {
  var api, hasCrypto;

  hasCrypto = !!self.Crypto;

  if (hasCrypto) {
    self.window = self;
  } else {
    self.rnd_queue = [];
    self.window = {
      crypto: {
        getRandomValues: function(a) {
          var buff, diff;
          buff = self.rnd_queue.shift();
          if (!buff) {
            console.log('no random ' + a.length);
            throw new Error('no random ' + a.length);
          }
          diff = buff.length - a.length;
          if (diff) {
            a.set(buff.subarray(diff));
          } else {
            a.set(buff);
          }
        }
      }
    };
  }

  api = {
    init: function(e) {
      var js_nacl;
      importScripts(e.data.naclPath);
      js_nacl = nacl_factory.instantiate(e.data.heapSize);
      e.data.api.forEach(function(f) {
        api[f] = function(e) {
          try {
            if (self.rnd_queue && e.data.rnd) {
              self.rnd_queue.push(e.data.rnd);
            }
            self.postMessage({
              cmd: f,
              res: js_nacl[f].apply(js_nacl, e.data.args)
            });
          } catch (error) {
            e = error;
            self.postMessage({
              cmd: f,
              error: true,
              message: e.stack || e.message || e
            });
          }
        };
      });
      self.postMessage({
        cmd: 'init',
        hasCrypto: hasCrypto
      });
    }
  };

  self.addEventListener('message', function(e) {
    var func;
    func = api[e.data.cmd];
    if (!func) {
      throw new Error('invalid command');
    }
    func(e);
  });

}).call(this);
