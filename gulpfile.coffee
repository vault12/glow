
browserify  = require 'browserify'
browserSync = require('browser-sync').create() # live css reload & browser syncing
coffeeify   = require 'coffeeify'     # browserify plugin for coffescript support
                                      # breaks with latest coffeescript version, so forced legacy CS version in package.json
                                      # TODO: follow https://github.com/jnordberg/coffeeify/issues/41 for solution
gulp        = require 'gulp'          # streaming build system
subarg      = require 'subarg'        # allows us to parse arguments w/recursive contexts
uglify      = require 'gulp-uglify'   # minifies files with UglifyJS
rimraf      = require 'gulp-rimraf'   # delete files
es          = require 'event-stream'  # merge multiple streams under one control object
source      = require 'vinyl-source-stream'
transform   = require 'vinyl-transform'
buffer      = require 'vinyl-buffer'
sourcemaps  = require 'gulp-sourcemaps'
exorcist    = require 'exorcist'
glob        = require 'glob'
browserify_coffeelint = require 'browserify-coffeelint'
global.argv = subarg(process.argv.slice(2)) # used for tunnel

conf =
  lib: ['src/main.coffee', 'theglow.js']
  tests: [['src/main.coffee'].concat(glob.sync('tests/**/*.coffee')), 'tests.js']
  watch: ['src/**/*.coffee', 'src/**/*.js', 'tests/**/*.coffee']
  dist_dir: 'dist/'
  clean: ['dist/*.js', 'dist/*.map']

# produce non-minified versions of theglow and tests + source maps
gulp.task 'build', ->
  build false

# produce minified version of theglow
gulp.task 'dist', ->
  build true

build = (minify)->
  items = [conf.lib]
  items.push conf.tests if !minify
  # We merge the streams (that we create using `Array.map`)
  # using `es.merge` into a single stream object which is
  # necessary to return from the gulp task so that Gulp
  # only considers the task finished when all streams have finished.
  es.merge.apply null, items.map (entry) ->
    b = browserify(
      entries: entry[0]
      debug: true
      extensions: ['.coffee']
      paths: ['src'])
    b.exclude 'js-nacl'
    b.transform browserify_coffeelint,
      doEmitErrors: false
      doEmitWarnings: false
    b.transform coffeeify
    target = entry[1]
    target = target.replace('.js', '.min.js') if minify
    b = b.bundle()
    b = b.pipe source target
    b = b.pipe buffer()
    b = b.pipe transform(->
      exorcist conf.dist_dir + target + '.map', null, '../') if !minify
    b = b.pipe uglify() if minify
    b = b.pipe gulp.dest conf.dist_dir

# launch browser sync
gulp.task 'default', ['build'], ->
  browserSync.init
    server:
      baseDir: '.'
      index: 'dist/index.html'
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

gulp.task 'clean', ->
  gulp.src conf.clean, read: false
    .pipe rimraf()
