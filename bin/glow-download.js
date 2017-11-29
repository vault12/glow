#! /usr/bin/env node --harmony
var co = require('co');
var prompt = require('co-prompt');
var program = require('commander');

var common = require('./_glow_common');

program
  .description('Download file(s) from the relay')
  .arguments('<relay_url> <guest_public_key>')
  .option('-d, --directory <directory>', 'directory to write downloaded file')
  .option('-f, --file <file>', 'file name to use instead of the original one')
  .option('-i, --interactive', 'interactive mode')
  .option('-n, --number <number>', 'max. number of files to download ("all" to download all)', '1')
  .option('--silent', 'silent mode')
  .option('--stdout', 'stream output to stdout')
  .parse(process.argv);

common.checkPrivateKey();

if (program.interactive) {
  co(function* () {
    var relay_url = yield prompt(common.message('Relay URL', 'https://zax.example.com'));
    var guest_public_key = yield prompt(common.message('Guest public key', 'base64'));
    program.number = yield prompt(common.message('Number of files to download', '1'));
    common.runPhantom('download', {
      relay_url: relay_url,
      guest_public_key: guest_public_key,
      directory: program.directory,
      file: program.file,
      number: program.number
    });
  });
} else if (program.args.length < 2) {
  program.outputHelp();
} else {
  common.runPhantom('download', {
    relay_url: program.args[0],
    guest_public_key: program.args[1],
    directory: program.directory,
    file: program.file,
    number: program.number,
    silent: program.silent,
    stdout: program.stdout
  });
}
