express = require 'express'
connectFileCache = require 'connect-file-cache'
fs = require 'fs'
path = require 'path'
exists = fs.existsSync || path.existsSync
Snockets = require 'snockets'
spawn = require('child_process').spawn
mochaPhantomJSRunner = require('./mocha-phantomjs-runner')

class MochaServer
  constructor: ({
    @requirePaths, @testPaths, @recursive, @ui, @bail,
    @ignoreLeaks, @headless, @reporter, @compilers
    }) ->

    @bail ?= false
    @ignoreLeaks ?= false
    @compilers ?= {}

    @setUpCompilers(@compilers)

    @globals = null

    @app = express()
    @cache = connectFileCache()
    @app.use @cache.middleware
    @app.set "view engine", "jade"
    @app.set 'views', "#{__dirname}/../views"

    mochaDir = path.dirname require.resolve('mocha')
    cssPath = path.resolve mochaDir, 'mocha.css'
    css = fs.readFileSync cssPath
    jsPath = path.resolve mochaDir, 'mocha.js'
    js = fs.readFileSync jsPath
    @cache.set 'mocha.css', css
    @cache.set 'mocha.js', js

    @app.get "/", @show

  launch: ->
    if @headless
      @run =>
        mochaPhantomJSRunner.launch {
          @reporter
        }
    else
      @run()

  show: (request, response)=>
    files = @discoverFilesInPaths @requirePaths.concat(@testPaths)

    snockets = new Snockets
    scriptOrder = []
    for file in files
      for { filename, js } in snockets.getCompiledChain(file, async: false) when filename not in scriptOrder
        scriptOrder.push filename
        @cache.set filename, js

    response.render 'index', { scriptOrder , @ui, @bail, @ignoreLeaks }

  discoverFilesInPaths: (paths)->
    files = []
    for p in paths
      for discoveredFilePath in @discoverFiles(p)
        resolvedFilePath = path.resolve discoveredFilePath
        files.push resolvedFilePath unless resolvedFilePath in files
    files

  discoverFiles: (rootPath)->
    originalPath = rootPath

    rootPath = "#{originalPath}.js" unless exists rootPath
    rootPath = "#{originalPath}.coffee" unless exists rootPath
    stat = fs.statSync rootPath
    (return [rootPath]) if stat.isFile()

    files = []
    for file in fs.readdirSync rootPath
      do (file)=>
        file = path.join rootPath, file
        stat = fs.statSync file
        if stat.isDirectory()
          files = files.concat(@discoverFiles file) if @recursive
          return
        return if not stat.isFile() or not @shouldInclude(file)
        files.push file
    files

  setUpCompilers: (compilers)->
    for ext, compiler of compilers
      Snockets.compilers[ext] = require path.join process.cwd(), compiler

  fileMatchingRegExp: ->
    s = '^[^\.].*\.(js|coffee'
    for ext of @compilers
      s += '|' + ext
    s += ')$'
    new RegExp(s)

  shouldInclude: (file)->
    @re ||= @fileMatchingRegExp()
    @re.test(path.basename(file))

  run: (callback)->
    callback ?= -> console.log 'Tests available at http://localhost:8888'
    @app.listen 8888, callback

module.exports = exports = MochaServer
