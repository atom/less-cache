const fs = require('fs')
const {dirname, join} = require('path')

const tmp = require('tmp')
const temp = require('temp').track()
const fstream = require('fstream')
const dedent = require('dedent')

const LessCache = require('../src/less-cache')

describe('LessCache', function () {
  let [cache, fixturesDir] = []

  beforeEach(function () {
    fixturesDir = null
    tmp.dir(function (error, tempDir) {
      const reader = fstream.Reader(join(__dirname, 'fixtures'))
      reader.on('end', function () {
        fixturesDir = tempDir
        const cacheConfig = {
          importPaths: [join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')],
          cacheDir: join(tempDir, 'cache')
        }
        return cache = new LessCache(cacheConfig)
      })
      return reader.pipe(fstream.Writer(tempDir))
    })

    return waitsFor(() => fixturesDir != null)
  })

  describe('::cssForFile(filePath)', function () {
    let filePath = null
    const fileLess = dedent`
      @import "a";
      @import "b";
      @import "c";
      @import "d";

      body {
        a: @a;
        b: @b;
        c: @c;
        d: @d;
      }
    `

    beforeEach(() => filePath = join(fixturesDir, 'imports.less'))

    return it('returns the compiled CSS for a given path and Less content', function () {
      const css = cache.cssForFile(filePath, fileLess)
      expect(css).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
    })
  })

  describe('::readFileSync(filePath)', function () {
    let [css] = []

    beforeEach(function () {
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(cache.stats.hits).toBe(0)
      expect(cache.stats.misses).toBe(1)
    })

    it('returns the compiled CSS for a given Less file path', () =>
      expect(css).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
    )

    it('returns the cached CSS for a given Less file path', function () {
      spyOn(cache, 'parseLess').andCallThrough()
      expect(cache.readFileSync(join(fixturesDir, 'imports.less'))).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
      expect(cache.parseLess.callCount).toBe(0)
      expect(cache.stats.hits).toBe(1)
      expect(cache.stats.misses).toBe(1)
    })

    it('reflects changes to the file being read', function () {
      fs.writeFileSync(join(fixturesDir, 'imports.less'), 'body { display: block; }')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe(dedent`
        body {
          display: block;
        }\n
      `)
    })

    it('reflects changes to files imported by the file being read', function () {
      fs.writeFileSync(join(fixturesDir, 'b.less'), '@b: 20;')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe(dedent`
        body {
          a: 1;
          b: 20;
          c: 3;
          d: 4;
        }\n
      `)
    })

    it('reflects changes to files on the import path', function () {
      fs.writeFileSync(join(fixturesDir, 'imports-1', 'd.less'), '@d: 40;')
      cache.setImportPaths(cache.getImportPaths())
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 40;
        }\n
      `)

      fs.unlinkSync(join(fixturesDir, 'imports-1', 'c.less'))
      cache.setImportPaths(cache.getImportPaths())
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 40;
        }\n
      `)

      fs.writeFileSync(join(fixturesDir, 'imports-1', 'd.less'), '@d: 400;')
      cache.setImportPaths(cache.getImportPaths())
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 400;
        }\n
      `)
    })

    it('reflect changes to the import paths array', function () {
      spyOn(cache, 'parseLess').andCallThrough()
      cache.setImportPaths([join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')])
      cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(cache.parseLess.callCount).toBe(0)

      cache.setImportPaths([join(fixturesDir, 'imports-2'), join(fixturesDir, 'imports-1'), join(fixturesDir, 'import-does-not-exist')])
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 4;
        }\n
      `)
      expect(cache.parseLess.callCount).toBe(1)

      cache.parseLess.reset()
      cache.setImportPaths([join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')])
      expect(cache.readFileSync(join(fixturesDir, 'imports.less'))).toBe(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
      expect(cache.parseLess.callCount).toBe(0)
    })

    it('reuses cached CSS across cache instances', function () {
      const cache2 = new LessCache({cacheDir: cache.getDirectory(), importPaths: cache.getImportPaths()})
      spyOn(cache2, 'parseLess').andCallThrough()
      cache2.readFileSync(join(fixturesDir, 'imports.less'))
      expect(cache2.parseLess.callCount).toBe(0)
    })

    it('throws compile errors', () => expect(() => cache.readFileSync(join(fixturesDir, 'invalid.less'))).toThrow())

    it('throws file not found errors', () => expect(() => cache.readFileSync(join(fixturesDir, 'does-not-exist.less'))).toThrow())

    it('relativizes cache paths based on the configured resource path', function () {
      const cache2 = new LessCache({cacheDir: cache.getDirectory(), importPaths: cache.getImportPaths(), resourcePath: fixturesDir})
      expect(fs.existsSync(join(cache2.importsCacheDir, 'content', 'imports.json'))).toBeFalsy()
      cache2.readFileSync(join(fixturesDir, 'imports.less'))
      expect(fs.existsSync(join(cache2.importsCacheDir, 'content', 'imports.json'))).toBeTruthy()
    })

    return it('uses the fallback directory when no cache entry is found in the primary directory', function () {
      const cache2 = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'cache2'),
        importPaths: cache.getImportPaths(),
        fallbackDir: cache.getDirectory(),
        resourcePath: fixturesDir
      })
      cache2.readFileSync(join(fixturesDir, 'imports.less'))

      const cache3 = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'cache3'),
        importPaths: cache2.getImportPaths(),
        fallbackDir: cache2.getDirectory(),
        resourcePath: fixturesDir
      })

      spyOn(cache3, 'parseLess').andCallThrough()
      cache3.readFileSync(join(fixturesDir, 'imports.less'))
      expect(cache3.parseLess.callCount).toBe(0)
    })
  })

  describe('when syncCaches option is set to true', function () {
    it('writes the cache entry to the fallback cache when initially uncached', function () {
      const fallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })

      cache = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        syncCaches: true,
        fallbackDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })

      const cacheCss = cache.readFileSync(join(fixturesDir, 'a.less'))
      expect(cache.stats.hits).toBe(0)
      expect(cache.stats.misses).toBe(1)

      const fallbackCss = fallback.readFileSync(join(fixturesDir, 'a.less'))
      expect(fallback.stats.hits).toBe(1)
      expect(fallback.stats.misses).toBe(0)

      expect(cacheCss).toBe(fallbackCss)
    })

    it('writes the cache entry to the fallback cache when read from the main cache', function () {
      cache = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        resourcePath: fixturesDir
      })

      const fallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })

      const cacheWithFallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        syncCaches: true,
        fallbackDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })

      // Prime main cache
      cache.readFileSync(join(fixturesDir, 'a.less'))

      // Read from main cache with write to fallback
      cacheWithFallback.readFileSync(join(fixturesDir, 'a.less'))

      // Read from fallback cache
      fallback.readFileSync(join(fixturesDir, 'a.less'))

      expect(fallback.stats.hits).toBe(1)
      expect(fallback.stats.misses).toBe(0)
    })

    return it('writes the cache entry to the main cache when read from the fallback cache', function () {
      cache = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        resourcePath: fixturesDir
      })

      const fallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })

      const cacheWithFallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        syncCaches: true,
        fallbackDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })

      // Prime fallback cache
      fallback.readFileSync(join(fixturesDir, 'a.less'))

      // Read from fallback with write to main cache
      cacheWithFallback.readFileSync(join(fixturesDir, 'a.less'))

      // Read from main cache
      cache.readFileSync(join(fixturesDir, 'a.less'))

      expect(cache.stats.hits).toBe(1)
      expect(cache.stats.misses).toBe(0)
    })
  })

  return describe('when providing a resource path and less sources by relative file path', () =>
    it("reads from the provided sources first, and falls back to reading from disk if a valid source isn't available", function () {
      const cacheDir = temp.mkdirSync()
      const cache1 = new LessCache({
        cacheDir,
        importPaths: [join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')],
        resourcePath: fixturesDir,
        lessSourcesByRelativeFilePath: {
          'imports.less': dedent`
            @import "a";
            @import "b";
            @import "c";
            @import "d";

            some-selector {
              prop-1: @a;
              prop-2: @b;
              prop-3: @c;
              prop-4: @d;
            }\n
          `
        }
      })

      expect(cache1.readFileSync(join(fixturesDir, 'imports.less'))).toBe(dedent`
        some-selector {
          prop-1: 1;
          prop-2: 2;
          prop-3: 3;
          prop-4: 4;
        }\n
      `)

      const cache2 = new LessCache({
        cacheDir,
        importPaths: [join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')],
        resourcePath: fixturesDir,
        lessSourcesByRelativeFilePath: {
          'imports.less': dedent`
            @import "a";
            @import "b";
            @import "c";
            @import "d";

            some-selector {
              prop-1: @a;
              prop-2: @b;
              prop-3: @c;
              prop-4: @d;
            }\n
          `,
          'imports-1/c.less': '@c: "changed";\n'
        }})

      expect(cache2.readFileSync(join(fixturesDir, 'imports.less'))).toBe(dedent`
        some-selector {
          prop-1: 1;
          prop-2: 2;
          prop-3: "changed";
          prop-4: 4;
        }\n
      `)
    })
  )
})
