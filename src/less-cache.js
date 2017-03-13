const crypto = require('crypto')
const {basename, dirname, extname, join, relative} = require('path')

const _ = require('underscore-plus')
const fs = require('fs-plus')
let less = null // Defer until it is actually used
let lessFs = null // Defer until it is actually used
const walkdir = require('walkdir')

const cacheVersion = 1

module.exports =
class LessCache {
  // Create a new Less cache with the given options.
  //
  // options - An object with following keys
  //   * cacheDir: A string path to the directory to store cached files in (required)
  //
  //   * importPaths: An array of strings to configure the Less parser with (optional)
  //
  //   * resourcePath: A string path to use for relativizing paths. This is useful if
  //                   you want to make caches transferable between directories or
  //                   machines. (optional)
  //
  //   * fallbackDir: A string path to a directory containing a readable cache to read
  //                  from an entry is not found in this cache (optional)
  constructor ({cacheDir, importPaths, resourcePath, fallbackDir, syncCaches, lessSourcesByRelativeFilePath} = {}) {
    this.cacheDir = cacheDir
    this.importPaths = importPaths
    this.resourcePath = resourcePath
    this.fallbackDir = fallbackDir
    this.syncCaches = syncCaches
    this.lessSourcesByRelativeFilePath = lessSourcesByRelativeFilePath
    if (this.lessSourcesByRelativeFilePath == null) { this.lessSourcesByRelativeFilePath = {} }
    this.importsCacheDir = this.cacheDirectoryForImports(this.importPaths)
    if (this.fallbackDir) {
      this.importsFallbackDir = join(this.fallbackDir, basename(this.importsCacheDir))
    }
    this.stats = {
      hits: 0,
      misses: 0
    }
  }

  load () {
    return this.setImportPaths(this.importPaths, true)
  }

  cacheDirectoryForImports (importPaths = []) {
    if (this.resourcePath) {
      importPaths = importPaths.map(importPath => this.relativize(this.resourcePath, importPath))
    }
    return join(this.cacheDir, this.digestForContent(importPaths.join('\n')))
  }

  getDirectory () { return this.cacheDir }

  getImportPaths () { return _.clone(this.importPaths) }

  async getImportedFiles (importPaths) {
    let importedFiles = []
    for (let i = 0; i < importPaths.length; i++) {
      try {
        const filePaths = await this.getFilePathsAtImportPath(importPaths[i])
        importedFiles = importedFiles.concat(filePaths)
      } catch (error) {
        continue
      }
    }
    return importedFiles
  }

  getFilePathsAtImportPath (importPath) {
    return new Promise((resolve, reject) => {
      const filePaths = []
      const emitter = walkdir(importPath, (filePath, stat) => {
        if (stat.isFile()) {
          if (this.resourcePath) {
            filePath = this.relativize(this.resourcePath, filePath)
          }
          filePaths.push(filePath)
        }
      })
      const disposeEmitter = () => {
        emitter.removeAllListeners('error')
        emitter.removeAllListeners('end')
      }
      emitter.on('error', (error) => {
        disposeEmitter()
        reject(error)
      })
      emitter.on('end', () => {
        disposeEmitter()
        resolve(filePaths)
      })
    })
  }

  async setImportPaths (importPaths, firstLoad) {
    if (this.importPathsPromise) {
      this.importPathsPromise = this.importPathsPromise.then(() => this._setImportPaths(importPaths, firstLoad))
    } else {
      this.importPathsPromise = this._setImportPaths(importPaths, firstLoad)
    }

    return this.importPathsPromise
  }

  async _setImportPaths (importPaths = [], firstLoad = false) {
    const importedFiles = await this.getImportedFiles(importPaths)
    const pathsChanged = !_.isEqual(this.importPaths, importPaths)
    const filesChanged = !_.isEqual(this.importedFiles, importedFiles)
    if (pathsChanged) {
      this.importsCacheDir = this.cacheDirectoryForImports(importPaths)
      if (this.fallbackDir) {
        this.importsFallbackDir = join(this.fallbackDir, basename(this.importsCacheDir))
      }
    } else if (filesChanged && !firstLoad) {
      try {
        await deletePath(this.importsCacheDir)
      } catch (error) {
        if (error && error.code === 'ENOENT') {
          try {
            await deletePath(this.importsCacheDir) // Retry once
          } catch (error) {}
        }
      }
    }

    await this.writeJSON(join(this.importsCacheDir, 'imports.json'), {importedFiles})
    this.importedFiles = importedFiles
    this.importPaths = importPaths
  }

  observeImportedFilePaths (callback) {
    const importedPaths = []
    if (lessFs == null) { lessFs = require('less/lib/less-node/fs.js') }
    const originalFsReadFileSync = lessFs.readFileSync
    lessFs.readFileSync = (filePath, ...args) => {
      let relativeFilePath
      if (this.resourcePath) { relativeFilePath = this.relativize(this.resourcePath, filePath) }
      const content = this.lessSourcesByRelativeFilePath[relativeFilePath] != null ?
        this.lessSourcesByRelativeFilePath[relativeFilePath] :
        originalFsReadFileSync(filePath, ...args)
      importedPaths.push({path: relativeFilePath != null ? relativeFilePath : filePath, digest: this.digestForContent(content)})
      return content
    }

    try {
      callback()
    } finally {
      lessFs.readFileSync = originalFsReadFileSync
    }

    return importedPaths
  }

  readJSON (filePath) {
    return readFile(filePath).then((content) => JSON.parse(content))
  }

  writeJSON (filePath, object) {
    return writeFile(filePath, JSON.stringify(object))
  }

  async digestForPath (relativeFilePath) {
    let lessSource = this.lessSourcesByRelativeFilePath[relativeFilePath]
    if (lessSource == null) {
      let absoluteFilePath = null
      if (this.resourcePath && !fs.isAbsolute(relativeFilePath)) {
        absoluteFilePath = join(this.resourcePath, relativeFilePath)
      } else {
        absoluteFilePath = relativeFilePath
      }
      lessSource = await readFile(absoluteFilePath)
    }

    return this.digestForContent(lessSource)
  }

  digestForContent (content) {
    return crypto.createHash('SHA1').update(content, 'utf8').digest('hex')
  }

  relativize (from, to) {
    const relativePath = relative(from, to)
    if (relativePath.indexOf('..') === 0) {
      return to
    } else {
      return relativePath
    }
  }

  getCachePath (directory, filePath) {
    const cacheFile = `${basename(filePath, extname(filePath))}.json`
    let directoryPath = dirname(filePath)
    if (this.resourcePath) { directoryPath = this.relativize(this.resourcePath, directoryPath) }
    if (directoryPath) { directoryPath = this.digestForContent(directoryPath) }
    return join(directory, 'content', directoryPath, cacheFile)
  }

  async getCachedCss (filePath, digest) {
    let cacheEntry, fallbackDirUsed, path
    try {
      cacheEntry = await this.readJSON(this.getCachePath(this.importsCacheDir, filePath))
    } catch (error) {
      if (this.importsFallbackDir != null) {
        try {
          cacheEntry = await this.readJSON(this.getCachePath(this.importsFallbackDir, filePath))
          fallbackDirUsed = true
        } catch (error) {}
      }
    }

    if (!cacheEntry || digest !== cacheEntry.digest) {
      return
    }

    for (const {path, digest} of cacheEntry.imports) {
      try {
        const digestForPath = await this.digestForPath(path)
        if (digestForPath !== digest) {
          return
        }
      } catch (error) {
        return
      }
    }

    if (this.syncCaches) {
      if (fallbackDirUsed) {
        await this.writeJSON(this.getCachePath(this.importsCacheDir, filePath), cacheEntry)
      } else if (this.importsFallbackDir != null) {
        await this.writeJSON(this.getCachePath(this.importsFallbackDir, filePath), cacheEntry)
      }
    }

    return cacheEntry.css
  }

  async putCachedCss (filePath, digest, css, imports) {
    const cacheEntry = {digest, css, imports, version: cacheVersion}
    await this.writeJSON(this.getCachePath(this.importsCacheDir, filePath), cacheEntry)

    if (this.syncCaches && (this.importsFallbackDir != null)) {
      await this.writeJSON(this.getCachePath(this.importsFallbackDir, filePath), cacheEntry)
    }
  }

  parseLess (filePath, contents) {
    let css = null
    const options = {filename: filePath, syncImport: true, paths: this.importPaths}
    if (less == null) { less = require('less') }
    const imports = this.observeImportedFilePaths(() =>
      less.render(contents, options, function (error, result) {
        if (error != null) {
          throw error
        } else {
          css = result.css
        }
      })
    )
    return {imports, css}
  }

  // Read the Less file at the current path and return either the cached CSS or the newly
  // compiled CSS. This method caches the compiled CSS after it is generated. This cached
  // CSS will be returned as long as the Less file and any of its imports are unchanged.
  //
  // filePath: A string path to a Less file.
  //
  // Returns the compiled CSS for the given path.
  async readFile (absoluteFilePath) {
    let fileContents = null
    if (this.resourcePath && fs.isAbsolute(absoluteFilePath)) {
      const relativeFilePath = this.relativize(this.resourcePath, absoluteFilePath)
      fileContents = this.lessSourcesByRelativeFilePath[relativeFilePath]
    }

    if (fileContents == null) {
      fileContents = await readFile(absoluteFilePath)
    }

    return this.cssForFile(absoluteFilePath, fileContents)
  }

  // Return either cached CSS or the newly
  // compiled CSS from `lessContent`. This method caches the compiled CSS after it is generated. This cached
  // CSS will be returned as long as the Less file and any of its imports are unchanged.
  //
  // filePath: A string path to the Less file.
  // lessContent: The contents of the filePath
  //
  // Returns the compiled CSS for the given path and lessContent
  async cssForFile (filePath, lessContent) {
    await this.importPathsPromise

    let imports
    const digest = this.digestForContent(lessContent)
    let css = await this.getCachedCss(filePath, digest)
    if (css != null) {
      this.stats.hits++
      return css
    }

    this.stats.misses++
    ({imports, css} = this.parseLess(filePath, lessContent))
    await this.putCachedCss(filePath, digest, css, imports)
    return css
  }
}

function readFile (filePath) {
  return new Promise((resolve, reject) => {
    fs.readFile(filePath, 'utf8', (error, contents) => {
      if (error) {
        reject(error)
      } else {
        resolve(contents)
      }
    })
  })
}

function writeFile (filePath, contents) {
  return new Promise((resolve, reject) => {
    fs.writeFile(filePath, contents, (error) => {
      if (error) {
        reject(error)
      } else {
        resolve()
      }
    })
  })
}

function deletePath (path) {
  return new Promise((resolve, reject) => {
    fs.remove(path, (error) => {
      if (error) {
        reject(error)
      } else {
        resolve()
      }
    })
  })
}
