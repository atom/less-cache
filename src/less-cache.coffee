crypto = require 'crypto'
nodeFs = require 'fs'
{basename, dirname, extname, join, relative} = require 'path'

_ = require 'underscore-plus'
fs = require 'fs-plus'
{Parser} = require 'less'
walkdir = require('walkdir').sync

cacheVersion = 1

module.exports =
class LessCache
  # Create a new LESS cache with the given options.
  #
  # options - An object with following keys
  #   * cacheDir: A string path to the directory to store cached files in (required)
  #
  #   * importPaths: An array of strings to configure the LESS parser with (optional)
  #
  #   * resourcePath: A string path to use for relativizing paths. This is useful if
  #                   you want to make caches transferable between directories or
  #                   machines. (optional)
  #
  #   * fallbackDir: A string path to a directory containing a readable cache to read
  #                  from an entry is not found in this cache (optional)
  constructor: ({@cacheDir, @importPaths, @resourcePath, @fallbackDir}={}) ->
    @importsCacheDir = @cacheDirectoryForImports(@importPaths)
    if @fallbackDir
      @importsFallbackDir = join(@fallbackDir, basename(@importsCacheDir))

    try
      {@importedFiles} = @readJson(join(@importsCacheDir, 'imports.json'))

    @setImportPaths(@importPaths)

  # Private:
  cacheDirectoryForImports: (importPaths=[]) ->
    if @resourcePath
      importPaths = importPaths.map (importPath) =>
        @relativize(@resourcePath, importPath)
    join(@cacheDir, @digestForContent(importPaths.join('\n')))

  getDirectory: -> @cacheDir

  getImportPaths: -> _.clone(@importPaths)

  # Private:
  getImportedFiles: (importPaths) ->
    importedFiles = []
    for importPath in importPaths
      try
        walkdir importPath, no_return: true, (filePath, stat) =>
          return unless stat.isFile()
          filePath = @relativize(@resourcePath, filePath) if @resourcePath
          importedFiles.push(filePath)
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
      fs.removeSync(@importsCacheDir) if fs.existsSync(@importsCacheDir)

    fs.makeTreeSync(@importsCacheDir)
    @writeJson(join(@importsCacheDir, 'imports.json'), {importedFiles})

    @importedFiles = importedFiles
    @importPaths = importPaths

  # Private:
  observeImportedFilePaths: (callback) ->
    importedPaths = []
    originalFsReadFileSync = nodeFs.readFileSync
    nodeFs.readFileSync = (filePath, args...) =>
      content = originalFsReadFileSync(filePath, args...)
      filePath = @relativize(@resourcePath, filePath) if @resourcePath
      importedPaths.push({path: filePath, digest: @digestForContent(content)})
      content

    try
      callback()
    finally
      nodeFs.readFileSync = originalFsReadFileSync

    importedPaths

  # Private:
  readJson: (filePath) -> JSON.parse(fs.readFileSync(filePath))

  # Private:
  writeJson: (filePath, object) -> fs.writeFileSync(filePath, JSON.stringify(object))

  # Private:
  digestForPath: (filePath) ->
    @digestForContent(fs.readFileSync(filePath))

  # Private:
  digestForContent: (content) ->
    crypto.createHash('SHA1').update(content, 'utf8').digest('hex')

  # Private:
  relativize: (from, to) ->
    relativePath = relative(from, to)
    if relativePath.indexOf('..') is 0
      to
    else
      relativePath

  # Private:
  getCachePath: (directory, filePath) ->
    cacheFile = "#{basename(filePath, extname(filePath))}.json"
    directoryPath = dirname(filePath)
    directoryPath = @relativize(@resourcePath, directoryPath) if @resourcePath
    directoryPath = @digestForContent(directoryPath) if directoryPath
    join(directory, 'content', directoryPath, cacheFile)

  # Private:
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
        path = join(@resourcePath, path) if @resourcePath and not fs.isAbsolute(path)
        return if @digestForPath(path) isnt digest
      catch error
        return

    cacheEntry.css

  # Private:
  putCachedCss: (filePath, digest, css, imports) ->
    cachePath = @getCachePath(@importsCacheDir, filePath)
    fs.makeTreeSync(dirname(cachePath))
    @writeJson(cachePath, {digest, css, imports, version: cacheVersion})

  # Private:
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

  # Read the LESS file at the current path and return either the cached CSS or the newly
  # compiled CSS. This method caches the compiled CSS after it is generated. This cached
  # CSS will be returned as long as the LESS file and any of its imports are unchanged.
  #
  # filePath: A string path to a LESS file.
  #
  # Returns the compiled CSS for the given path.
  readFileSync: (filePath) ->
    less = fs.readFileSync(filePath, 'utf8')
    digest = @digestForContent(less)
    css = @getCachedCss(filePath, digest)
    unless css?
      {imports, css} = @parseLess(filePath, less)
      @putCachedCss(filePath, digest, css, imports)

    css
