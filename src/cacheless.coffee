crypto = require 'crypto'
fs = require 'fs'

{Parser} = require 'less'

module.exports =
class LessCache
  constructor: ({importPaths}={}) ->
    @setImportPaths(importPaths)

  setImportPaths: (@importPaths) ->
    @cssCache = {}

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

  getCachedCss: (filePath, digest) ->
    cacheEntry = @cssCache[filePath]
    return unless cacheEntry?
    return unless digest is cacheEntry.digest

    for {path, digest} in cacheEntry.imports
      try
        return if @digestForPath(path) isnt digest
      catch error
        return

    cacheEntry.css

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

      @cssCache[filePath] = {digest, css: cssContent, imports: importedPaths}

    cssContent
