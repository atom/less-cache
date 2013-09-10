crypto = require 'crypto'
fs = require 'fs'

{Parser} = require 'less'
lessTree = require 'less/lib/less/tree'

module.exports =
class LessCache
  constructor: ({@importPaths}={}) ->
    @cssCache = {}

  setImportPaths: (@importPaths) ->

  readFileSync: (filePath) ->
    lessContent = fs.readFileSync(filePath, 'utf8')
    digest = crypto.createHash('SHA1').update(lessContent).digest('hex')
    cacheEntry = @cssCache[filePath] ? {}
    if cacheEntry.digest is digest
      cacheEntry.css
    else
      cssContent = null
      options = filename: filePath, syncImport: true, paths: @importPaths
      parser = new Parser(options)
      parser.parse lessContent, (error, tree) =>
        if error?
          throw error
        else
          cssContent = tree.toCSS()
          @cssCache[filePath] = {digest, css: cssContent}
      cssContent
