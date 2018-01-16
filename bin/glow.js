#! /usr/bin/env node --harmony

var program = require('commander');

program
  .version(require('../package.json').version) // Extract version info from package.json
  .description('Client library for interacting with Zax Cryptographic Relay (https://github.com/vault12/zax)')
  .command('clean <relay_url> <guest_public_key>', 'delete all files in mailbox on the relay')
  .command('count <relay_url> <guest_public_key> [options]', 'show number of pending files on the relay').alias('c')
  .command('download <relay_url> <guest_public_key> [options]', 'download file(s) from the relay').alias('d')
  .command('key [options]', 'show public key or h2(pk), generate a new keypair, set/update private key').alias('k')
  .command('upload <relay_url> <guest_public_key> <file_url> [options]', 'upload a file to the relay').alias('u')
  .parse(process.argv);
