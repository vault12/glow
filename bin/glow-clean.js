#! /usr/bin/env node --harmony
var co = require('co');
var prompt = require('co-prompt');
var program = require('commander');

var common = require('./_glow_common');

program
  .description('Delete all files in mailbox on the relay')
  .arguments('<relay_url>')
  .option('-i, --interactive', 'interactive mode')
  .parse(process.argv);

common.checkPrivateKey();

if (program.interactive) {
  co(function* () {
    var relay_url = yield prompt(common.message('Relay URL', 'https://zax.example.com'));
    common.runPhantom('clean', {
      relay_url: relay_url
    });
  });
} else if (program.args.length < 1) {
  program.outputHelp();
} else {
  common.runPhantom('clean', {
    relay_url: program.args[0]
  });
}
