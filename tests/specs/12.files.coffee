__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect  = require('chai').expect

MailBox = require 'mailbox'
Relay   = require 'relay'
Nacl = require 'nacl'

# Base64-encoded version of tests/test.zip file
# Original file size: 765 bytes
# Length of Base64 representation: 1020 chars (765 / 6 * 8)
FILE_BASE64 = 'UEsDBBQACAAIADOrmUoAAAAAAAAAAAAAAAAIABAAdGVzdC50eHRVWAwAp5T/WKGU/1j1ARQAC0mtKFFIy8xJVUguSk0sSU1RSMsvUnDPyS9XKEktLgEAUEsHCFQVUxYhAAAAHwAAAFBLAwQKAAAAAAA2q5lKAAAAAAAAAAAAAAAACQAQAF9fTUFDT1NYL1VYDACnlP9Yp5T/WPUBFABQSwMEFAAIAAgAM6uZSgAAAAAAAAAAAAAAABMAEABfX01BQ09TWC8uX3Rlc3QudHh0VVgMAKeU/1ihlP9Y9QEUAGNgFWNnYGJg8E1MVvAPVohQgAKQGAMnEBsxMDAWAGkgn3ERA1HAMSQkCMIC6WAUADImoSlhhorzMzCIJ+fn6iUWFOSk6oWkVpS45iXnp2TmpUP0ywMJLQYGFYSa3NSSxJTEkkSr+GxfF8+S1NzQ4tSikMT0YrB6TyARycBgjkU9ULlPYlJqTnxiQWGxeXJedkZWmllqYmllYlKmcUpVemVuKlBzaUmaroW1obGJkaG5pYVJUkFOZnGJgcECDqiHGKEeYETzEOen9Csb5f9ft+XYoNe56FnnhkbpW33ShuomIWf52fsqVyz2EtBy3ijy9Gb2y2kL7/aeCDfaXs/St9f6hNHH1sa13nbL715rCPyudFX/c45NlPJZlZYnaxWO525duXcJAFBLBwhCvQ/MJgEAAKIBAABQSwECFQMUAAgACAAzq5lKVBVTFiEAAAAfAAAACAAMAAAAAAAAAABApIEAAAAAdGVzdC50eHRVWAgAp5T/WKGU/1hQSwECFQMKAAAAAAA2q5lKAAAAAAAAAAAAAAAACQAMAAAAAAAAAABA/UFnAAAAX19NQUNPU1gvVVgIAKeU/1inlP9YUEsBAhUDFAAIAAgAM6uZSkK9D8wmAQAAogEAABMADAAAAAAAAAAAQKSBngAAAF9fTUFDT1NYLy5fdGVzdC50eHRVWAgAp5T/WKGU/1hQSwUGAAAAAAMAAwDSAAAAFQIAAAAA'

# Original binary of tests/test.zip file
# Converted from Base64 for convenience
FILE_BINARY = window.atob FILE_BASE64

# Actual MD5 of test.zip, to verify the transfer on recipient side
FILE_MD5 = '5c03b7b871a4070572e73de9236bfd0b'

# Calculate original file size in bytes
FILE_SIZE = FILE_BINARY.length

# Arbitrary chunk size for testing purposes
# NOTE: for big files `max_chunk_size` value from `startFileUpload` response should be considered
CHUNK_SIZE = randNum 50, 200

# Using Math.ceil here, because if file size is not evenly divisible
# by CHUNK_SIZE, then we have one more chunk
NUMBER_OF_CHUNKS = Math.ceil(FILE_SIZE / CHUNK_SIZE)

describe 'File transfer, low level API', ->
  return unless window.__globalTest.runTests['relay files low level']
  @slow(window.__globalTest.slow)
  @timeout(window.__globalTest.timeouts.mid)

  [Alice, Bob] = [null, null]

  before ->
    @skip() if __globalTest.offline

    # Chunk iterators stored in global variables (to preserve chunk number inside the promise)
    window.__globalTest.uploadChunkIterator = 0
    window.__globalTest.downloadChunkIterator = 0
  
  after ->
    delete window.__globalTest.uploadChunkIterator
    delete window.__globalTest.downloadChunkIterator

  it 'create mailboxes', ->
    MailBox.new('Alice').then (mbx)->
      Alice = mbx
      MailBox.new('Bob').then (mbx)->
        Bob = mbx
        Alice.keyRing.addGuest('Bob', Bob.getPubCommKey()).then ->
          Bob.keyRing.addGuest('Alice', Alice.getPubCommKey())

  it 'start upload', ->
    r = new Relay(__globalTest.host)

    Nacl.makeSecretKey().then (sk)->
      __globalTest.originalSkey = sk.key

      metadata = JSON.stringify
        name: (randWord randNum 4,14) + '.zip'
        orig_size: FILE_SIZE
        md5: FILE_MD5
        created: randNum 1480000000, 1520000000
        modified: randNum 1480000000, 1520000000
        skey: __globalTest.originalSkey.toBase64()

      Alice.encodeMessage('Bob', metadata).then (encryptedMetadata) ->
        r.openConnection().then ->
          r.connectMailbox(Alice).then ->
            expect(Alice.sessionKeys).not.empty
            r.runCmd('startFileUpload', Alice,
              to: Bob.hpk()
              file_size: FILE_SIZE
              metadata: encryptedMetadata)
            .then (response) ->
              expect(response).to.contain.all.keys ['uploadID', 'max_chunk_size', 'storage_token']
              expect(response.uploadID).to.be.a 'string'
              expect(response.max_chunk_size).to.be.above 0

              __globalTest.uploadID = response.uploadID

              r.runCmd('fileStatus', Alice,
                uploadID: __globalTest.uploadID)
              .then (response) ->
                expect(response).to.contain.all.keys ['status', 'bytes_stored', 'file_size']
                expect(response.status).equal 'START'

  # Generate a set of tests to upload every chunk
  for k in [0...NUMBER_OF_CHUNKS]
    it "uploading chunk #{k}", ->
      r = new Relay(__globalTest.host)

      i = __globalTest.uploadChunkIterator++
      chunk = FILE_BINARY.substring(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE)

      Alice.encodeMessageSymmetric(chunk, __globalTest.originalSkey).then (msg) ->
        payload =
          uploadID: __globalTest.uploadID
          # Sequential number of the file part
          part: i
          nonce: msg.nonce
          ctext: msg.ctext

        # The last chunk
        if i == (NUMBER_OF_CHUNKS - 1)
          payload.last_chunk = true

        r.openConnection().then ->
          r.connectMailbox(Alice).then ->
            r.runCmd('uploadFileChunk', Alice, payload).then (response) ->
              expect(response.status).equal 'OK'

              r.runCmd('fileStatus', Alice,
                uploadID: __globalTest.uploadID)
              .then (response) ->
                expect(response).to.contain.all.keys ['status', 'bytes_stored', 'file_size', 'total_chunks']
                if payload.last_chunk
                  expect(response.total_chunks).to.equal NUMBER_OF_CHUNKS
                  expect(response.status).equal 'COMPLETE'
                else
                  expect(response.status).equal 'UPLOADING'

  it 'read fileReady message in recipient\'s mailbox', ->
    r = new Relay(__globalTest.host)
    r.openConnection().then ->
      r.connectMailbox(Bob).then ->
        r.runCmd('count', Bob).then (count) ->
          expect(count).equal 1
          r.runCmd('download', Bob).then (msgs)->
            encodedMetadata = JSON.parse msgs[0].data
            Bob.decodeMessage('Alice', encodedMetadata.nonce, encodedMetadata.ctext).then (decodedMetadata)->
              __globalTest.metadata = JSON.parse decodedMetadata
              expect(__globalTest.metadata.skey).equal __globalTest.originalSkey.toBase64()

  DECODED_FILE_BINARY = ''

  for k in [0...NUMBER_OF_CHUNKS]
    it "download chunk #{k}", ->
      r = new Relay(__globalTest.host)

      r.openConnection().then ->
        r.connectMailbox(Bob).then ->
          r.runCmd('downloadFileChunk', Bob,
            uploadID: __globalTest.uploadID,
            part: __globalTest.downloadChunkIterator++)
          .then (response) ->
            expect(response).to.contain.all.keys ['nonce', 'ctext']
            Bob.decodeMessageSymmetric(response.nonce, response.ctext, __globalTest.metadata.skey).then (msg)->
              DECODED_FILE_BINARY = DECODED_FILE_BINARY.concat(msg)

  it 'verify decoded file', ->
    # Compare contents
    expect(DECODED_FILE_BINARY).equal FILE_BINARY
    # Compare metadata
    expect(__globalTest.metadata.md5).equal FILE_MD5
    expect(__globalTest.metadata.orig_size).equal DECODED_FILE_BINARY.length

  it 'delete file', ->
    r = new Relay(__globalTest.host)
    r.openConnection().then ->
      r.connectMailbox(Bob).then ->
        r.runCmd('deleteFile', Bob,
          uploadID: __globalTest.uploadID)
        .then (response) ->
          expect(response.status).equal 'OK'

          r.runCmd('fileStatus', Alice,
            uploadID: __globalTest.uploadID)
          .then (response) ->
            expect(response.status).equal 'NOT_FOUND'

  it 'clear mailboxes', ->
    Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true)
