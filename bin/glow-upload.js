#! /usr/bin/env node --harmony
var co = require('co');
var prompt = require('co-prompt');
var program = require('commander');

var common = require('./_glow_common');

program
  .description('Upload file to the relay')
  .arguments('<relay_url> <guest_public_key> <file_url>')
  .option('-i, --interactive', 'interactive mode')
  .parse(process.argv);

common.checkPrivateKey();

if (program.interactive) {
  co(function* () {
    var relay_url = yield prompt(common.message('Relay URL', 'https://zax.example.com'));
    var guest_public_key = yield prompt(common.message('Guest public key', 'base64'));
    var file_url = yield prompt(common.message('File location', 'documents/report.pdf'));
    common.runPhantom('upload', {
      relay_url: relay_url,
      guest_public_key: guest_public_key,
      file_url: file_url
    });
  });
} else if (program.args.length < 3) {
  program.outputHelp();
} else {
  common.runPhantom('upload', {
    relay_url: program.args[0],
    guest_public_key: program.args[1],
    file_url: program.args[2]
  });
}
