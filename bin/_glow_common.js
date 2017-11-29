var chalk = require('chalk');
var phantomjs = require('phantomjs-prebuilt');
var Preferences = require("preferences");

var settings = new Preferences('glow', { 'private_key': '' });

// colored messages
exports.message = (msg, explanation) => chalk.bold.green(msg) + ' (' + chalk.whiteBright(explanation) + '): ';
exports.error = (msg) => chalk.red(msg)

exports.isPrivateKeySet = () => (settings.private_key.length > 0)
exports.checkPrivateKey = () => {
  if (!exports.isPrivateKeySet()) {
    console.log(exports.error('Private key is not set. Please run `glow key` to set your key.'));
    process.exit(1);
  }
}
exports.setPrivateKey = (sk) => {
  settings.private_key = sk;
}

exports.runPhantom = (command, params) => {
  params.__dirname = __dirname;
  params.private_key = settings.private_key;

  var phantom = phantomjs.exec(
    '--web-security=no', // allow HTTPS requests with a headless browser
    '--output-encoding=ISO-8859-1', // write downloaded file in ASCII
    __dirname + '/_phantomjs.js',
    command,
    JSON.stringify(params));

  phantom.stdout.pipe(process.stdout);
  phantom.stderr.on('data', data => {
    console.log(exports.error(data));
    process.exit(1);
  });
  phantom.on('exit', code => process.exit(code));
}
