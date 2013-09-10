fs = require 'fs'

{Parser} = require 'less'

exports.readFileSync = (filePath) ->
  parser = new Parser
    syncImport: true
    filename: filePath

  content = null
  parser.parse fs.readFileSync(filePath, 'utf8'), (error, tree) ->
    if error?
      throw error
    else
      content = tree.toCSS()
  content
