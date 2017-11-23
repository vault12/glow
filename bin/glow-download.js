#! /usr/bin/env node --harmony
var co = require('co');
var prompt = require('co-prompt');
var program = require('commander');
var getStdin = require('get-stdin');
var chalk = require('chalk');
var phantomjs = require('phantomjs-prebuilt');
var Preferences = require("preferences");

var prefs = new Preferences('glow', { 'private_key': '' });

program
  .arguments('<relay_url> <guest_public_key>')
  .option('-c, --count', 'show number of messages without downloading them')
  .option('-d, --directory <directory>', 'directory to write downloaded file')
  .option('-f, --file <file>', 'file name to use instead of the original one')
  .option('-i, --interactive', 'interactive mode')
  .option('-k, --key', 'set private key')
  .option('-n, --number <number>', 'max. number of files to download ("all" to download all)')
  .option('-p, --public', 'show public key')
  .option('--silent', 'silent mode')
  .option('--stdout', 'stream output to stdout')
  .parse(process.argv);

if (program.key || !prefs.private_key.length) {
  getStdin().then(str => {
    if (str.length) {
      prefs.private_key = str.trim();
    } else {
      co(function* () {
        var private_key = yield prompt.password(colorMsg('Secret key', 'base64'));
        prefs.private_key = private_key;
      });
    }
  });
} else if (program.interactive) {
  co(function* () {
    program.relay_url = yield prompt(colorMsg('Relay URL', 'https://zax.example.com'));
    program.guest_public_key = yield prompt(colorMsg('Guest public key', 'base64'));
    program.number = yield prompt(colorMsg('Number of files to download', '1'));
    runPhantom();
  });
} else if (program.args.length < 2 && !program.public) {
  program.outputHelp();
} else {
  program.relay_url = program.args[0];
  program.guest_public_key = program.args[1];
  runPhantom();
}

function colorMsg(main, explanation) {
  return chalk.bold.green(main) + ' (' + chalk.whiteBright(explanation) + '): ';
}

function runPhantom() {
  var phantom = phantomjs.exec(
    '--web-security=no', // allow HTTPS requests with a headless browser
    '--output-encoding=ISO-8859-1', // write downloaded file in ASCII
    __dirname + '/download.js',
    program.relay_url,
    prefs.private_key,
    program.guest_public_key,
    program.count || '',
    program.directory || '',
    program.file || '',
    program.number || '',
    program.public || '',
    program.silent || '',
    program.stdout || '',
    __dirname);

  phantom.stdout.pipe(process.stdout);
  phantom.stderr.on('data', data => {
    console.log(chalk.red(data));
    process.exit(1);
  });
  phantom.on('exit', code => process.exit(code));
}
