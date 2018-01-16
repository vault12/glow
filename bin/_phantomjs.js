var system = require('system');
var page = require('webpage').create();
var fs = require('fs');

var command = system.args[1];
var params = JSON.parse(system.args[2]);

// Create directory if it doesn't exist, and convert it to absolute path
if (command === 'download' && params.directory) {
  if (params.directory.substr(-1) != fs.separator) {
    params.directory += fs.separator;
  }
  if (!fs.isAbsolute(params.directory)) {
    params.directory = fs.workingDirectory + fs.separator + params.directory;
  }
  if (!fs.isWritable(params.directory)) {
    if (fs.exists(params.directory)) {
      system.stderr.write(params.directory + ' is not writable.');
    } else if (!fs.makeTree(params.directory)) {
      system.stderr.write('Can\'t create directory ' + params.directory);
    }
  }
}

if (command === 'upload') {
  if (!fs.isAbsolute(params.file_url)) {
    params.file_url = fs.workingDirectory + fs.separator + params.file_url;
  }
  if (!fs.isReadable(params.file_url)) {
    if (fs.exists(params.file_url)) {
      system.stderr.write(params.file_url + ' is not readable.');
    } else {
      system.stderr.write(params.file_url + ' does not exist.');
    }
  }
  params.contents = fs.read(params.file_url, {
    mode: 'r',
    charset: 'latin1'
  });
  params.filename = params.file_url.substring(params.file_url.lastIndexOf(fs.separator) + 1);
  params.size = fs.size(params.file_url);
  params.modified = fs.lastModified(params.file_url).getTime() / 1000;
}

page.open(params.__dirname + '/_phantomjs.html', function (status) {
  if (status !== 'success') {
    system.stderr.write('Unable to launch Glow. Please reinstall the package');
  }
  page.evaluate(function (command, params) {
    // Initialize crypto storage
    glow.CryptoStorage.startStorageSystem(new glow.SimpleStorageDriver());

    // Input validation
    // ----------------------------------------
    try {
      params.private_key = params.private_key.fromBase64();
    } catch (e) {
      throw 'Provided private key is not a valid base64-encoded string. Please run `glow key -s` to set the correct key.';
    }

    if (params.private_key.length != 32) {
      throw 'Provided private key is not a valid base64-encoded 32-byte key. Please run `glow key -s` to set the correct key.';
    }

    if (command !== 'key') {
      try {
        params.guest_public_key.fromBase64();
      } catch (e) {
        throw 'Provided guest public key is not a valid base64-encoded string.';
      }

      if (params.guest_public_key.fromBase64().length != 32) {
        throw 'Provided guest public key is not a valid base64-encoded 32-byte key.';
      }
    }

    if (params.number) {
      if (params.number == 'all') {
        params.number = 1000;
      } else {
        params.number = parseInt(params.number, 10);
      }

      if (isNaN(params.number) || params.number < 1) {
        throw 'Wrong value of -n option, consider using an integer or "all" keyword.';
      }
    }

    // ----------------------------------------

    if (command === 'download') {
      alert('\nGlow file downloader');
      alert('==========================');
    }

    glow.MailBox.fromSecKey(params.private_key, 'mailbox').then(function (mbx) {
      if (command === 'key') {
        switch (params.type) {
          case 'public':
            alert(mbx.keyRing.getPubCommKey());
            break;
          case 'hpk':
            alert(mbx.keyRing.hpk.toBase64());
            break;
          default:
            alert('PK:  ' + mbx.keyRing.getPubCommKey());
            alert('HPK: ' + mbx.keyRing.hpk.toBase64());
        }
        window.callPhantom();
        return;
      }

      var relay = new glow.Relay(params.relay_url);

      mbx.keyRing.addGuest('sender', params.guest_public_key).then(function () {
        if (command === 'download') {
          alert('Connecting to relay...');
        }

        if (command === 'upload') {
          alert('Starting upload...');
          mbx.startFileUpload('sender', relay, {
            name: params.filename,
            orig_size: params.size,
            modified: params.modified
          }).then(function(res) {
            alert('Upload ID ' + res.uploadID);
            mbx.uploadFileChunk(relay, res.uploadID, params.contents, 0, 1, res.skey).then(function(res2) {
              alert('Uploading chunk 1...');
              mbx.getFileStatus(relay, res.uploadID).then(function(status) {
                if (status.status === 'COMPLETE') {
                  alert('Done!');
                  alert('=====================');
                } else {
                  alert('Upload error');
                }
                window.callPhantom();
              });
            });
          });
          return;
        }

        mbx.getRelayMessages(relay).then(function (messages) {

          // Filter messages sent from guest public key only
          var messagesToDownload = [];
          for (var i = 0; i < messages.length; i++) {
            if (messages[i].hasOwnProperty('uploadID')) {
              messagesToDownload.push(messages[i]);
            }
          }

          if (command === 'clean') {
            var fileCounter = 0;
            var promise = Array.apply(null, { length: messagesToDownload.length }).map(Function.call, Number).reduce(function (acc) {
              return acc.then(function (res) {
                return mbx.deleteFile(relay, messagesToDownload[fileCounter].uploadID).then(function (result) {
                  fileCounter++;
                  res.push(1);
                  return res;
                });
              });
            }, Promise.resolve([]));

            promise.then(function (total) {
              // `total` files deleted
              mbx.clean(relay).then(function () {
                window.callPhantom();
              });
            });

            return;
          }

          if (command === 'count') {
            alert(messagesToDownload.length);
            // terminate PhantomJS
            window.callPhantom();
            return;
          }

          if (!messagesToDownload.length) {
            alert('Mailbox empty');
            window.callPhantom();
            return;
          }

          var amountToDownload = 1;

          if (params.number) {
            amountToDownload = Math.min(params.number, messagesToDownload.length);
          }

          var fileCounter = 0;

          var promise = Array.apply(null, { length: amountToDownload }).map(Function.call, Number).reduce(function (acc) {
            return acc.then(function (res) {
              alert('Downloading file ' + (fileCounter + 1) + '/' + amountToDownload + ', ' + messagesToDownload[fileCounter].name + '...');
              return downloadFile(relay, mbx, messagesToDownload[fileCounter]).then(function (result) {
                fileCounter++;
                res.push(result);
                return res;
              });
            });
          }, Promise.resolve([]));

          promise.then(function (total) {
            var total = total.reduce(function (a, b) { return a + b; }, 0);
            alert(total + ' file' + (total == 1 ? '' : 's') + ' downloaded');
            window.callPhantom();
          });

        });
      });
    });

    function downloadFile(relay, mbx, msg) {
      return new Promise(function (resolve) {
        mbx.getFileStatus(relay, msg.uploadID).then(function (status) {
          if (status.status === 'COMPLETE') {

            var chunkCounter = 0;
            var promise = Array.apply(null, { length: status.total_chunks }).map(Function.call, Number).reduce(function (acc) {
              return acc.then(function (res) {
                alert('Downloading chunk ' + (chunkCounter + 1) + '/' + status.total_chunks + '...');
                return mbx.downloadFileChunk(relay, msg.uploadID, chunkCounter, msg.skey).then(function (chunk) {
                  chunkCounter++;
                  window.callPhantom({ name: msg.name, content: chunk });
                  res.push(1);
                  return res;
                });
              });
            }, Promise.resolve([]));

            promise.then(function (total) {
              var total = total.reduce(function (a, b) { return a + b; }, 0);
              alert(total + ' chunks downloaded, deleting file...');
              // Delete file itself
              mbx.deleteFile(relay, msg.uploadID).then(function () {
                // Delete file status message in mailbox
                mbx.relayDelete([msg.nonce], relay).then(function () {
                  alert('Done!');
                  alert('=====================');
                  resolve(1);
                });
              });
            });

          } else if (status.status === 'NOT_FOUND') {
            mbx.relayDelete([msg.nonce], relay).then(function () {
              alert(msg.name + ' is not found');
              resolve(0);
            });
          } else {
            alert(msg.name + ' is not ready to be downloaded');
            resolve(0);
          }
        });
      });
    }

  }, command, params);
});

page.onAlert = function (data) {
  if (!params.stdout && !params.silent) {
    console.log(data);
  }
};

page.onError = function (msg, trace) {
  system.stderr.write(msg);
}

page.onCallback = function (data) {
  if (!data) {
    phantom.exit(0);
  }

  if (params.stdout) {
    system.stdout.write(data.content);
    return;
  }

  var fileToWrite = params.file || data.name;
  if (params.directory) {
    fileToWrite = params.directory + fileToWrite;
  }
  var stream = fs.open(fileToWrite, { 'mode': 'a', 'charset': 'ISO-8859-1' });
  stream.write(data.content);
  delete data;
  stream.close();
};

page.onResourceError = function (resourceError) {
  system.stderr.write('Unable to connect to ' + resourceError.url + '. Make sure it\'s a valid Zax relay.');
};

page.onResourceTimeout = function (request) {
  system.stderr.write('Request timed out when trying to connect to ' + request.url + '. Make sure it\'s a valid Zax relay.');
};
