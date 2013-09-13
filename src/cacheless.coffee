crypto = require 'crypto'
fs = require 'fs'
{basename, dirname, extname, join} = require 'path'

{Parser} = require 'less'
mkdir = require('mkdirp').sync
rm = require('rimraf').sync

cacheVersion = 1

module.exports =
class LessCache
  constructor: ({@importPaths, @cacheDir}={}) ->
    console.log @cacheDir

  setImportPaths: (@importPaths) ->
    rm(@cacheDir)

  observeImportedFilePaths: (callback) ->
    importedPaths = []
    originalFsReadFileSync = fs.readFileSync
    fs.readFileSync = (filePath, args...) =>
      content = originalFsReadFileSync(filePath, args...)
      importedPaths.push({path: filePath, digest: @digestForContent(content)})
      content

    try
      callback()
    finally
      fs.readFileSync = originalFsReadFileSync

    importedPaths

  digestForPath: (filePath) ->
    @digestForContent(fs.readFileSync(filePath))

  digestForContent: (content) ->
    crypto.createHash('SHA1').update(content).digest('hex')

  getCachePath: (filePath) ->
    cacheFile = "#{basename(filePath, extname(filePath))}.json"
    join(@cacheDir, dirname(filePath), cacheFile)

  getCachedCss: (filePath, digest) ->
    try
      cacheEntry = JSON.parse(fs.readFileSync(@getCachePath(filePath)))
    catch error
      return

    return unless digest is cacheEntry?.digest

    for {path, digest} in cacheEntry.imports
      try
        return if @digestForPath(path) isnt digest
      catch error
        return

    cacheEntry.css

  putCachedCss: (filePath, digest, css, imports) ->
    cachePath = @getCachePath(filePath)
    mkdir(dirname(cachePath))
    fs.writeFileSync(cachePath, JSON.stringify({digest, css, imports, version: cacheVersion}))

  readFileSync: (filePath) ->
    lessContent = fs.readFileSync(filePath, 'utf8')
    digest = crypto.createHash('SHA1').update(lessContent).digest('hex')
    cssContent = @getCachedCss(filePath, digest)

    unless cssContent?
      options = filename: filePath, syncImport: true, paths: @importPaths
      parser = new Parser(options)
      importedPaths = @observeImportedFilePaths =>
        parser.parse lessContent, (error, tree) =>
          if error?
            throw error
          else
            cssContent = tree.toCSS()

      @putCachedCss(filePath, digest, cssContent, importedPaths)

    cssContent
