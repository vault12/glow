
browserify  = require 'browserify'
browserSync = require('browser-sync').create() # live css reload & browser syncing
coffeeify   = require 'coffeeify'     # browserify plugin for coffescript support
                                      # breaks with latest coffeescript version, so forced legacy CS version in package.json
                                      # TODO: follow https://github.com/jnordberg/coffeeify/issues/41 for solution
gulp        = require 'gulp'          # streaming build system
subarg      = require 'subarg'        # allows us to parse arguments w/recursive contexts
uglify      = require 'gulp-uglify'   # minifies files with UglifyJS
rimraf      = require 'gulp-rimraf'   # delete files
rename      = require 'gulp-rename'   # delete files
coffee      = require 'gulp-coffee'
es          = require 'event-stream'  # merge multiple streams under one control object
source      = require 'vinyl-source-stream'
transform   = require 'vinyl-transform'
buffer      = require 'vinyl-buffer'
exorcist    = require 'exorcist'
glob        = require 'glob'
coffeelint  = require 'browserify-coffeelint'
global.argv = subarg(process.argv.slice(2)) # used for tunnel

conf =
  lib: ['src/main.coffee', 'theglow.js']
  tests: [['src/main.coffee'].concat(glob.sync('tests/**/*.coffee')), 'tests.js']
  watch: ['src/**/*.coffee', 'tests/**/*.coffee']
  workers: 'src/workers/*.coffee'
  dist_dir: 'dist/'
  build_dir: 'build/'

# produce non-minified versions of theglow and tests + source maps
gulp.task 'build', ['workers'], ->
  build false

# produce production-ready minified and non-minified versions of theglow
gulp.task 'dist', ->
  build true

build = (dist) ->
  dir = if dist then conf.dist_dir else conf.build_dir
  items = [conf.lib]
  items.push conf.tests if !dist
  # We merge the streams (that we create using `Array.map`)
  # using `es.merge` into a single stream object which is
  # necessary to return from the gulp task so that Gulp
  # only considers the task finished when all streams have finished.
  es.merge.apply null, items.map (entry) ->
    b = browserify(
      entries: entry[0]
      debug: true if !dist
      extensions: ['.coffee']
      paths: ['src'])
    b.exclude 'js-nacl'
    b.transform coffeelint,
      doEmitErrors: false
      doEmitWarnings: false
    b.transform coffeeify
    b = b.bundle()
    b = b.pipe source entry[1]
    b = b.pipe buffer()

    # comment out this to turn off source maps
    b = b.pipe transform(->
      exorcist dir + entry[1] + '.map', null, '../', './') if !dist
    
    b = b.pipe gulp.dest dir
    b = b.pipe rename entry[1].replace('.js', '.min.js') if dist
    b = b.pipe uglify() if dist
    b = b.pipe gulp.dest dir

# build web workers
gulp.task 'workers', ->
  gulp.src conf.workers
    .pipe coffee()
    .pipe gulp.dest conf.build_dir

# launch browser sync
gulp.task 'default', ['build'], ->
  browserSync.init
    server:
      baseDir: '.'
      index: 'index.html'
    notify: false
    tunnel: argv.tunnel
    online: true
    minify: false
  gulp.watch conf.watch, ['watch']

# rebuild sources and reload browser sync
gulp.task 'watch', ['build'], ->
  browserSync.reload()

# run single-run headless tests
gulp.task 'test', ['build'], ->
  # TODO node version -or- PhantomJS v2 test

# clear build directory
gulp.task 'clean', ->
  gulp.src conf.build_dir, read: false
    .pipe rimraf()
