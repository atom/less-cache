crypto = require 'crypto'
fs = require 'fs'
{basename, dirname, extname, join, relative} = require 'path'

_ = require 'underscore'
{Parser} = require 'less'
mkdir = require('mkdirp').sync
rm = require('rimraf').sync
walkdir = require('walkdir').sync

cacheVersion = 1

module.exports =
class LessCache
  constructor: ({@cacheDir, @importPaths, @resourcePath, @fallbackDir}={}) ->
    @importsCacheDir = @cacheDirectoryForImports(@importPaths)
    if @fallbackDir
      @importsFallbackDir = join(@fallbackDir, basename(@importsCacheDir))

    try
      {@importedFiles} = @readJson(join(@importsCacheDir, 'imports.json'))

    @setImportPaths(@importPaths)

  cacheDirectoryForImports: (importPaths=[]) ->
    if @resourcePath
      importPaths = importPaths.map (importPath) =>
        @relativize(@resourcePath, importPath)
    join(@cacheDir, @digestForContent(importPaths.join('\n')))

  getDirectory: -> @cacheDir

  getImportPaths: -> _.clone(@importPaths)

  getImportedFiles: (importPaths) ->
    importedFiles = []
    for importPath in importPaths
      try
        walkdir importPath, no_return: true, (filePath, stat) ->
          importedFiles.push(filePath) if stat.isFile()
      catch error
        continue

    importedFiles

  setImportPaths: (importPaths=[]) ->
    importedFiles = @getImportedFiles(importPaths)

    pathsChanged = not _.isEqual(@importPaths, importPaths)
    filesChanged = not _.isEqual(@importedFiles, importedFiles)
    if pathsChanged
      @importsCacheDir = @cacheDirectoryForImports(importPaths)
      if @fallbackDir
        @importsFallbackDir = join(@fallbackDir, basename(@importsCacheDir))
    else if filesChanged
      rm(@importsCacheDir)

    mkdir(@importsCacheDir)
    @writeJson(join(@importsCacheDir, 'imports.json'), {importedFiles})

    @importedFiles = importedFiles
    @importPaths = importPaths

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

  readJson: (filePath) -> JSON.parse(fs.readFileSync(filePath))

  writeJson: (filePath, object) -> fs.writeFileSync(filePath, JSON.stringify(object))

  digestForPath: (filePath) ->
    @digestForContent(fs.readFileSync(filePath))

  digestForContent: (content) ->
    crypto.createHash('SHA1').update(content, 'utf8').digest('hex')

  relativize: (from, to) ->
    relativePath = relative(from, to)
    if relativePath.indexOf('..') is 0
      to
    else
      relativePath

  getCachePath: (directory, filePath) ->
    cacheFile = "#{basename(filePath, extname(filePath))}.json"
    directoryPath = dirname(filePath)
    directoryPath = @relativize(@resourcePath, directoryPath) if @resourcePath
    join(directory, 'content', directoryPath, cacheFile)

  getCachedCss: (filePath, digest) ->
    try
      cacheEntry = @readJson(@getCachePath(@importsCacheDir, filePath))
    catch error
      if @importsFallbackDir?
        try
          cacheEntry = @readJson(@getCachePath(@importsFallbackDir, filePath))

    return unless digest is cacheEntry?.digest

    for {path, digest} in cacheEntry.imports
      try
        return if @digestForPath(path) isnt digest
      catch error
        return

    cacheEntry.css

  putCachedCss: (filePath, digest, css, imports) ->
    cachePath = @getCachePath(@importsCacheDir, filePath)
    mkdir(dirname(cachePath))
    @writeJson(cachePath, {digest, css, imports, version: cacheVersion})

  parseLess: (filePath, less) ->
    css = null
    options = filename: filePath, syncImport: true, paths: @importPaths
    parser = new Parser(options)
    imports = @observeImportedFilePaths =>
      parser.parse less, (error, tree) =>
        if error?
          throw error
        else
          css = tree.toCSS()
    {imports, css}

  readFileSync: (filePath) ->
    less = fs.readFileSync(filePath, 'utf8')
    digest = @digestForContent(less)
    css = @getCachedCss(filePath, digest)
    unless css?
      {imports, css} = @parseLess(filePath, less)
      @putCachedCss(filePath, digest, css, imports)

    css
