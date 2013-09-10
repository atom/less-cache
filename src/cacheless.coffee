fs = require 'fs'

{Parser} = require 'less'
lessTree = require 'less/lib/less/tree'

module.exports =
class LessCache
  constructor: (@importPaths=[]) ->

  readFileSync: (filePath) ->
    options = filename: filePath, syncImport: true, paths: @importPaths
    parser = new Parser(options)

    content = null
    parser.parse fs.readFileSync(filePath, 'utf8'), (error, tree) ->
      if error?
        throw error
      else
        content = tree.toCSS()
    content
