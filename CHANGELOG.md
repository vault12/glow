### v4.1.3

* Add `upload` CLI command

### v4.1.2

* Delete actual files from relay with `clean` CLI command, not just metadata
* Better `download --directory` CLI command: relative and absolute paths, create directory if it doesn't exist, check if it's writable

### v4.1.1

* Change CLI commands syntax
* Add `clean` CLI command
* Add `key --generate` CLI command
* Minor fixes & enhancements

### v4.1.0

* Add CLI glow utility
* Use hash function with 64 bytes 0-pad
* Fix double JSON encoding/decoding for some commands

### v4.0.0

* Add commands and tests for file API
* Reset a session when request errors occur

### v3.0.3

* Added web worker to dist
* Published only build files on NPM

### v3.0.2

* Distribute NACL driver together with the library

### v3.0.1

* Run tests in CLI and Travis CI

### v3.0.0

* Sourcemap support 

### v2.0.7

* MailBox backup / restore

### v2.0.6

* patching npm error

### v2.0.5

* support for KeyRing backup / restore

### v2.0.4

* support for optional multiSet

### v2.0.3

* Mailbox hpk precompute
* Axios
* Nonce can accept int32 custom data

### v2.0.2

* Status message support for update calls

### v2.0.1

* Leveraging web workers

### v2.0.0

* Support for async access

### v1.1.4

* Force new session key
* Error msg fix

### v1.1.3

* Updated relay token timeout
* Updated relay session timeout

### v1.1.2

* Added easily configurable timeouts for remote vs local testing
* Added expiration events to 3 code points, using node/browserify EventEmitter class

### v1.1.1

* Fixing mailbox seed initialization
* Creating a minified version  

### v1.1.0

* Fixing guest persist bug
* Fixing js camelcase naming conventions


### v1.0.9

* Initial release
