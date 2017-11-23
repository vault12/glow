var system = require('system');
var page = require('webpage').create();
var fs = require('fs');

// Required arguments
var relay_url = system.args[1];
var secret_key = system.args[2];
var guest_public_key = system.args[3];

// Options
var count = system.args[4];
var directory = system.args[5];
var file = system.args[6];
var number = system.args[7];
var public = system.args[8];
var silent = system.args[9];
var stdout = system.args[10];

var path = system.args[11];

page.open(path + '/phantomjs.html', function (status) {
  page.evaluate(function (relay_url, sk, pk, count, number, public) {
    // Initialize crypto storage
    glow.CryptoStorage.startStorageSystem(new glow.SimpleStorageDriver());

    // Input validation
    // ----------------------------------------
    try {
      sk = sk.fromBase64();
    } catch (e) {
      throw 'Provided secret key is not a valid base64-encoded string. Please run `glow download -k` to set the correct key.';
    }

    if (sk.length != 32) {
      throw 'Provided secret key is not a valid base64-encoded 32-byte key. Please run `glow download -k` to set the correct key.';
    }

    if (!public) {
      try {
        pk.fromBase64();
      } catch (e) {
        throw 'Provided guest public key is not a valid base64-encoded string.';
      }

      if (pk.fromBase64().length != 32) {
        throw 'Provided guest public key is not a valid base64-encoded 32-byte key.';
      }
    }

    if (number) {
      if (number == 'all') {
        number = 1000;
      } else {
        number = parseInt(number, 10);
      }
  
      if (isNaN(number) || number < 1) {
        throw 'Wrong value of -n option, consider using an integer or "all" keyword';
      }
    }

    // ----------------------------------------

    if (!count && !public) {
      alert('\nGlow file downloader');
      alert('==========================');
    }

    glow.MailBox.fromSecKey(sk, 'mailbox').then(function (mbx) {
      if (public) {
        alert('PK:  ' + mbx.keyRing.getPubCommKey());
        alert('HPK: ' + mbx.keyRing.hpk.toBase64());
        window.callPhantom();
        return;
      }

      mbx.keyRing.addGuest('sender', pk).then(function () {
        if (!count) {
          alert('Connecting to relay...');
        }
        var relay = new glow.Relay(relay_url);
        mbx.connectToRelay(relay).then(function () {
          if (!count) {
            alert('Retrieving messages...');
          }
          mbx.getRelayMessages(relay).then(function (messages) {

            // Filter messages sent from guest public key only
            var messagesToDownload = [];
            for (var i = 0; i < messages.length; i++) {
              if (messages[i].hasOwnProperty('uploadID')) {
                messagesToDownload.push(messages[i]);
              }
            }

            if (count) {
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

            if (number) {
              amountToDownload = Math.min(number, messagesToDownload.length);
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
        })
      })
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

  }, relay_url, secret_key, guest_public_key, count, number, public);
});

page.onAlert = function (data) {
  if (!stdout && !silent) {
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

  if (stdout) {
    system.stdout.write(data.content);
    return;
  }

  var fileToWrite = file || data.name;
  if (directory) {
    fileToWrite = directory + fs.separator + fileToWrite;
  }
  var stream = fs.open(fileToWrite, { 'mode': 'a', 'charset': 'ISO-8859-1' });
  stream.write(data.content);
  delete data;
  stream.close();
};
