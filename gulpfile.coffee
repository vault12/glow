
browserify  = require 'browserify'
browserSync = require('browser-sync').create() # live css reload & browser syncing
coffee      = require 'gulp-coffee'   # removing this will add 10 secs to the build
coffeeify   = require 'coffeeify'
gulp        = require 'gulp'          # streaming build system
subarg      = require 'subarg'        # allows us to parse arguments w/recursive contexts
uglify      = require 'gulp-uglify'   # minifies files with UglifyJS
es          = require 'event-stream'  # merge multiple streams under one control object
source      = require 'vinyl-source-stream'
buffer      = require 'vinyl-buffer'
sourcemaps  = require 'gulp-sourcemaps'
glob        = require 'glob'
browserify_coffeelint = require 'browserify-coffeelint'
global.argv = subarg(process.argv.slice(2)) # used for tunnel

conf =
  lib: ['src/main.coffee', 'theglow.js']
  tests: [['src/main.coffee'].concat(glob.sync('tests/**/*.coffee')), 'tests.js']
  watch: ['src/**/*.coffee', 'tests/**/*.coffee']
  dist_dir: 'dist'

# produce theglow.js and tests.js, linted, compiled, browserified, uglified + source maps
gulp.task 'build', ->
  es.merge.apply null, [conf.lib, conf.tests].map (entry) ->
    browserify(
      entries: entry[0]
      debug: true
      extensions: ['.coffee']
      paths: ['src'])
    .exclude 'js-nacl'
    .transform browserify_coffeelint,
      doEmitErrors: true
      doEmitWarnings: true
    .transform coffeeify
    .bundle()
    .pipe source entry[1]
    .pipe(buffer())
    .pipe(sourcemaps.init({loadMaps: true}))
    .pipe(uglify())
    .pipe(sourcemaps.write('./'))
    .pipe gulp.dest conf.dist_dir

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
