crypto = require 'crypto'
{basename, dirname, extname, join, relative} = require 'path'

_ = require 'underscore-plus'
fs = require 'fs-plus'
less = require('less') # Defer until it is actually used
lessFs = less.fs # Defer until it is actually used
walkdir = require('walkdir').sync

cacheVersion = 1

module.exports =
class LessCache
  @digestForContent: (content) ->
    crypto.createHash('SHA1').update(content, 'utf8').digest('hex')

  # Create a new Less cache with the given options.
  #
  # options - An object with following keys
  #   * cacheDir: A string path to the directory to store cached files in (required)
  #
  #   * importPaths: An array of strings to configure the Less parser with (optional)
  #
  #   * resourcePath: A string path to use for relativizing paths. This is useful if
  #                   you want to make caches transferable between directories or
  #                   machines. (optional)
  #
  #   * fallbackDir: A string path to a directory containing a readable cache to read
  #                  from an entry is not found in this cache (optional)
  constructor: (params={}) ->
    {
      @cacheDir, @importPaths, @resourcePath, @fallbackDir, @syncCaches,
      @lessSourcesByRelativeFilePath, @importedFilePathsByRelativeImportPath
    } = params

    @lessSourcesByRelativeFilePath ?= {}
    @importedFilePathsByRelativeImportPath ?= {}
    @importsCacheDir = @cacheDirectoryForImports(@importPaths)
    if @fallbackDir
      @importsFallbackDir = join(@fallbackDir, basename(@importsCacheDir))

    try
      {@importedFiles} = @readJson(join(@importsCacheDir, 'imports.json'))

    @setImportPaths(@importPaths)

    @stats =
      hits: 0
      misses: 0

  cacheDirectoryForImports: (importPaths=[]) ->
    if @resourcePath
      importPaths = importPaths.map (importPath) =>
        @relativize(@resourcePath, importPath)
    join(@cacheDir, LessCache.digestForContent(importPaths.join('\n')))

  getDirectory: -> @cacheDir

  getImportPaths: -> _.clone(@importPaths)

  getImportedFiles: (importPaths) ->
    importedFiles = []
    for absoluteImportPath in importPaths
      importPath = null
      if @resourcePath?
        importPath = @relativize(@resourcePath, absoluteImportPath)
      else
        importPath = absoluteImportPath

      importedFilePaths = @importedFilePathsByRelativeImportPath[importPath]
      if importedFilePaths?
        importedFiles = importedFiles.concat(importedFilePaths)
      else
        try
          walkdir absoluteImportPath, no_return: true, (filePath, stat) =>
            return unless stat.isFile()
            if @resourcePath?
              importedFiles.push(@relativize(@resourcePath, filePath))
            else
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
      try
        fs.removeSync(@importsCacheDir)
      catch error
        if error?.code is 'ENOENT'
          try
            fs.removeSync(@importsCacheDir) # Retry once

    @writeJson(join(@importsCacheDir, 'imports.json'), {importedFiles})

    @importedFiles = importedFiles
    @importPaths = importPaths

  readJson: (filePath) -> JSON.parse(fs.readFileSync(filePath))

  writeJson: (filePath, object) -> fs.writeFileSync(filePath, JSON.stringify(object))

  digestForPath: (relativeFilePath) ->
    lessSource = @lessSourcesByRelativeFilePath[relativeFilePath]
    if lessSource?
      lessSource.digest
    else
      absoluteFilePath = null
      if @resourcePath and not fs.isAbsolute(relativeFilePath)
        absoluteFilePath = join(@resourcePath, relativeFilePath)
      else
        absoluteFilePath = relativeFilePath
      LessCache.digestForContent(fs.readFileSync(absoluteFilePath))

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
    directoryPath = LessCache.digestForContent(directoryPath) if directoryPath
    join(directory, 'content', directoryPath, cacheFile)

  getCachedCss: (filePath, digest) ->
    try
      cacheEntry = @readJson(@getCachePath(@importsCacheDir, filePath))
    catch error
      if @importsFallbackDir?
        try
          cacheEntry = @readJson(@getCachePath(@importsFallbackDir, filePath))
          fallbackDirUsed = true

    return unless digest is cacheEntry?.digest

    for {path, digest} in cacheEntry.imports
      try
        return if @digestForPath(path) isnt digest
      catch error
        return

    if @syncCaches
      if fallbackDirUsed
        @writeJson(@getCachePath(@importsCacheDir, filePath), cacheEntry)
      else if @importsFallbackDir?
        @writeJson(@getCachePath(@importsFallbackDir, filePath), cacheEntry)

    cacheEntry.css

  putCachedCss: (filePath, digest, css, imports) ->
    cacheEntry = {digest, css, imports, version: cacheVersion}
    @writeJson(@getCachePath(@importsCacheDir, filePath), cacheEntry)

    if @syncCaches and @importsFallbackDir?
      @writeJson(@getCachePath(@importsFallbackDir, filePath), cacheEntry)

  parseLess: (filePath, contents) ->
    entryPath = filePath.replace(/[^\/\\]*$/, '')
    options = {filename: filePath, syncImport: true, paths: @importPaths}
    rootFileInfo = {
      filename: filePath,
      rootpath: '',
      currentDirectory: entryPath,
      entryPath: entryPath,
      rootFilename: filePath
    }
    context = new less.contexts.Parse(options)
    importManager = new less.ImportManager(context, rootFileInfo)

    css = null
    parser = new less.Parser(context, importManager, rootFileInfo).parse contents, (err, rootNode) ->
      if err?
        throw error
      else
        {css} = new less.ParseTree(rootNode, importManager).toCSS(options)

    imports = []
    for filename, content of importManager.contents
      if filename isnt filePath
        imports.push({path: filename, digest: LessCache.digestForContent(content)})

  # Read the Less file at the current path and return either the cached CSS or the newly
  # compiled CSS. This method caches the compiled CSS after it is generated. This cached
  # CSS will be returned as long as the Less file and any of its imports are unchanged.
  #
  # filePath: A string path to a Less file.
  #
  # Returns the compiled CSS for the given path.
  readFileSync: (absoluteFilePath) ->
    lessSource = null
    if @resourcePath and fs.isAbsolute(absoluteFilePath)
      relativeFilePath = @relativize(@resourcePath, absoluteFilePath)
      lessSource = @lessSourcesByRelativeFilePath[relativeFilePath]

    if lessSource?
      @cssForFile(absoluteFilePath, lessSource.content, lessSource.digest)
    else
      @cssForFile(absoluteFilePath, fs.readFileSync(absoluteFilePath, 'utf8'))

  # Return either cached CSS or the newly
  # compiled CSS from `lessContent`. This method caches the compiled CSS after it is generated. This cached
  # CSS will be returned as long as the Less file and any of its imports are unchanged.
  #
  # filePath: A string path to the Less file.
  # lessContent: The contents of the filePath
  #
  # Returns the compiled CSS for the given path and lessContent
  cssForFile: (filePath, lessContent, digest) ->
    digest ?= LessCache.digestForContent(lessContent)
    css = @getCachedCss(filePath, digest)
    if css?
      @stats.hits++
      return css

    @stats.misses++
    {imports, css} = @parseLess(filePath, lessContent)
    @putCachedCss(filePath, digest, css, imports)
    css
