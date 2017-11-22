#! /usr/bin/env node --harmony

var program = require('commander');

program
  .version(require('../package.json').version) // Extract version info from package.json
  .command('download <relay_url> <guest_public_key>', 'download file(s) from the relay').alias('d')
  .parse(process.argv);
