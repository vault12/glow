__CRYPTO_DEBUG = true # Expose #theglow objects as window globals

expect   = require('chai').expect

MailBox  = require 'mailbox'
Relay    = require 'relay'
Utils    = require 'utils'

# Base64-encoded version of tests/test.zip file,
# to use for testing purposes.
# Original file size: 765 bytes
# Length of Base64 representation: 1020 chars (765 / 6 * 8)
FILE_BASE64 = 'UEsDBBQACAAIADOrmUoAAAAAAAAAAAAAAAAIABAAdGVzdC50eHRVWAwAp5T/WKGU/1j1ARQAC0mtKFFIy8xJVUguSk0sSU1RSMsvUnDPyS9XKEktLgEAUEsHCFQVUxYhAAAAHwAAAFBLAwQKAAAAAAA2q5lKAAAAAAAAAAAAAAAACQAQAF9fTUFDT1NYL1VYDACnlP9Yp5T/WPUBFABQSwMEFAAIAAgAM6uZSgAAAAAAAAAAAAAAABMAEABfX01BQ09TWC8uX3Rlc3QudHh0VVgMAKeU/1ihlP9Y9QEUAGNgFWNnYGJg8E1MVvAPVohQgAKQGAMnEBsxMDAWAGkgn3ERA1HAMSQkCMIC6WAUADImoSlhhorzMzCIJ+fn6iUWFOSk6oWkVpS45iXnp2TmpUP0ywMJLQYGFYSa3NSSxJTEkkSr+GxfF8+S1NzQ4tSikMT0YrB6TyARycBgjkU9ULlPYlJqTnxiQWGxeXJedkZWmllqYmllYlKmcUpVemVuKlBzaUmaroW1obGJkaG5pYVJUkFOZnGJgcECDqiHGKEeYETzEOen9Csb5f9ft+XYoNe56FnnhkbpW33ShuomIWf52fsqVyz2EtBy3ijy9Gb2y2kL7/aeCDfaXs/St9f6hNHH1sa13nbL715rCPyudFX/c45NlPJZlZYnaxWO525duXcJAFBLBwhCvQ/MJgEAAKIBAABQSwECFQMUAAgACAAzq5lKVBVTFiEAAAAfAAAACAAMAAAAAAAAAABApIEAAAAAdGVzdC50eHRVWAgAp5T/WKGU/1hQSwECFQMKAAAAAAA2q5lKAAAAAAAAAAAAAAAACQAMAAAAAAAAAABA/UFnAAAAX19NQUNPU1gvVVgIAKeU/1inlP9YUEsBAhUDFAAIAAgAM6uZSkK9D8wmAQAAogEAABMADAAAAAAAAAAAQKSBngAAAF9fTUFDT1NYLy5fdGVzdC50eHRVWAgAp5T/WKGU/1hQSwUGAAAAAAMAAwDSAAAAFQIAAAAA'

# Original binary of tests/test.zip file
# Converted from Base64 for convenience
FILE_BINARY = window.atob FILE_BASE64

# Calculate original file size in bytes
FILE_SIZE = FILE_BINARY.length

# Arbitrary chunk size for testing purposes
# NOTE: for big files `max_chunk_size` value from `startFileUpload` response should be considered
CHUNK_SIZE = randNum 50, 200

# Using Math.ceil here, because if file size is not evenly divisible
# by CHUNK_SIZE, then we have one more chunk
NUMBER_OF_CHUNKS = Math.ceil(FILE_SIZE / CHUNK_SIZE)

describe 'File transfer, wrapper API', ->
  return unless window.__globalTest.runTests['relay files wrapper']
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

    metadata =
      name: (randWord randNum 4,14) + '.zip'
      orig_size: FILE_SIZE
      created: randNum 1480000000, 1520000000
      modified: randNum 1480000000, 1520000000

    Alice.startFileUpload('Bob', r, metadata).then (response) ->
      expect(response).to.contain.all.keys ['uploadID', 'max_chunk_size', 'storage_token', 'skey']
      expect(response.uploadID).to.be.a 'string'
      window.__globalTest.uploadID = response.uploadID
      window.__globalTest.skey = response.skey

  for k in [0...NUMBER_OF_CHUNKS]
    it "uploading chunk #{k}", ->
      r = new Relay(__globalTest.host)
      
      i = __globalTest.uploadChunkIterator++
      chunk = FILE_BINARY.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE)

      Alice.uploadFileChunk(r, __globalTest.uploadID, chunk, i, NUMBER_OF_CHUNKS, __globalTest.skey).then (response) ->
        expect(response.status).equal 'OK'

  it 'check file status and retrieve metadata', ->
    r = new Relay(__globalTest.host)

    Alice.getFileStatus(r, __globalTest.uploadID).then (responseAlice) ->
      expect(responseAlice.status).equal 'COMPLETE'
      Bob.getFileStatus(r, __globalTest.uploadID).then (responseBob) ->
        expect(responseBob.status).equal 'COMPLETE'
        # Bob downloads metadata, to get secret key required to decrypt file chunks
        Bob.getFileMetadata(r, __globalTest.uploadID).then (metadata) ->
          window.__globalTest.metadata = metadata

  DECODED_FILE_BINARY = ''

  for k in [0...NUMBER_OF_CHUNKS]
    it "download chunk #{k}", ->
      r = new Relay(__globalTest.host)

      i = __globalTest.downloadChunkIterator++
      Bob.downloadFileChunk(r, __globalTest.uploadID, i, __globalTest.metadata.skey).then (chunk) ->
        DECODED_FILE_BINARY = DECODED_FILE_BINARY.concat(chunk)

  it 'verify decoded file', ->
    # Compare contents
    expect(DECODED_FILE_BINARY).equal FILE_BINARY

  it 'delete file', ->
    r = new Relay(__globalTest.host)
    Bob.deleteFile(r, __globalTest.uploadID).then (response) ->
      expect(response.status).equal 'OK'

  it 'clear mailboxes', ->
    Alice.selfDestruct(true).then ->
      Bob.selfDestruct(true)
