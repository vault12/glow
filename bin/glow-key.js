#! /usr/bin/env node --harmony
var co = require('co');
var prompt = require('co-prompt');
var program = require('commander');
var getStdin = require('get-stdin');
var crypto = require('crypto');

var common = require('./_glow_common');

program
  .description('Show public key or h2(pk), generate a new keypair, set/update private key')
  .option('-g, --generate', 'generate a new keypair (WARNING: old private key will be overwritten)')
  .option('-k, --hpk', 'show HPK')
  .option('-p, --public', 'show public key')
  .option('-s, --set', 'set private key')
  .parse(process.argv);

if (program.generate) {
  crypto.randomBytes(32, (err, buf) => {
    common.setPrivateKey(buf.toString('base64'));
    common.runPhantom('key', {
      type: 'public'
    });
  });
} else if (program.set || !common.isPrivateKeySet()) {
  getStdin().then(str => {
    if (str.length) {
      common.setPrivateKey(str.trim());
    } else {
      co(function* () {
        var private_key = yield prompt.password(common.message('Private key', 'base64'));
        common.setPrivateKey(private_key);
      });
    }
  });
} else {
  var type = '';
  if (program.public) {
    type = 'public';
  } else if (program.hpk) {
    type = 'hpk';
  }
  common.runPhantom('key', {
    type: type
  });
}
