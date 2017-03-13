const expect = require('expect.js')
const sinon = require('sinon')

const fs = require('fs-plus')
const {dirname, join} = require('path')

const temp = require('temp').track()
const dedent = require('dedent')

const LessCache = require('../src/less-cache')

describe('LessCache', function () {
  let [cache, fixturesDir] = []

  beforeEach(function () {
    fixturesDir = temp.path()
    fs.copySync(join(__dirname, 'fixtures'), fixturesDir)
    cache = new LessCache({
      importPaths: [join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')],
      cacheDir: join(fixturesDir, 'cache')
    })
    cache.load()
  })

  describe('::cssForFile(filePath)', function () {
    it('returns the compiled CSS for a given path and Less content', async function () {
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
      const css = await cache.cssForFile(join(fixturesDir, 'imports.less'), fileLess)
      expect(css).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
    })
  })

  describe('::readFile(filePath)', function () {
    let [css] = []

    beforeEach(async function () {
      css = await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(cache.stats.hits).to.be(0)
      expect(cache.stats.misses).to.be(1)
    })

    it('returns the compiled CSS for a given Less file path', () =>
      expect(css).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
    )

    it('returns the cached CSS for a given Less file path', async function () {
      sinon.spy(cache, 'parseLess')
      expect(await cache.readFile(join(fixturesDir, 'imports.less'))).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
      expect(cache.parseLess.callCount).to.be(0)
      expect(cache.stats.hits).to.be(1)
      expect(cache.stats.misses).to.be(1)
    })

    it('reflects changes to the file being read', async function () {
      fs.writeFileSync(join(fixturesDir, 'imports.less'), 'body { display: block; }')
      css = await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(css).to.be(dedent`
        body {
          display: block;
        }\n
      `)
    })

    it('reflects changes to files imported by the file being read', async function () {
      fs.writeFileSync(join(fixturesDir, 'b.less'), '@b: 20;')
      css = await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(css).to.be(dedent`
        body {
          a: 1;
          b: 20;
          c: 3;
          d: 4;
        }\n
      `)
    })

    it('reflects changes to files on the import path', async function () {
      fs.writeFileSync(join(fixturesDir, 'imports-1', 'd.less'), '@d: 40;')
      cache.setImportPaths(cache.getImportPaths())
      css = await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(css).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 40;
        }\n
      `)

      fs.unlinkSync(join(fixturesDir, 'imports-1', 'c.less'))
      cache.setImportPaths(cache.getImportPaths())
      css = await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(css).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 40;
        }\n
      `)

      fs.writeFileSync(join(fixturesDir, 'imports-1', 'd.less'), '@d: 400;')
      cache.setImportPaths(cache.getImportPaths())
      css = await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(css).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 400;
        }\n
      `)
    })

    it('reflect changes to the import paths array', async function () {
      sinon.spy(cache, 'parseLess')
      cache.setImportPaths([join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')])
      await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(cache.parseLess.callCount).to.be(0)

      cache.setImportPaths([join(fixturesDir, 'imports-2'), join(fixturesDir, 'imports-1'), join(fixturesDir, 'import-does-not-exist')])
      css = await cache.readFile(join(fixturesDir, 'imports.less'))
      expect(css).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 4;
        }\n
      `)
      expect(cache.parseLess.callCount).to.be(1)

      cache.parseLess.reset()
      cache.setImportPaths([join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')])
      expect(await cache.readFile(join(fixturesDir, 'imports.less'))).to.be(dedent`
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }\n
      `)
      expect(cache.parseLess.callCount).to.be(0)
    })

    it('reuses cached CSS across cache instances', async function () {
      const cache2 = new LessCache({cacheDir: cache.getDirectory(), importPaths: cache.getImportPaths()})
      cache2.load()
      sinon.spy(cache2, 'parseLess')
      await cache2.readFile(join(fixturesDir, 'imports.less'))
      expect(cache2.parseLess.callCount).to.be(0)
    })

    it('throws compile errors', async function () {
      let threwError = false
      try {
        await cache.readFile(join(fixturesDir, 'invalid.less'))
      } catch (e) {
        threwError = true
      }
      expect(threwError).to.be(true)
    })

    it('throws file not found errors', async function () {
      let threwError = false
      try {
        await cache.readFile(join(fixturesDir, 'does-not-exist.less'))
      } catch (e) {
        threwError = true
      }
      expect(threwError).to.be(true)
    })

    it('relativizes cache paths based on the configured resource path', async function () {
      const cache2 = new LessCache({cacheDir: cache.getDirectory(), importPaths: cache.getImportPaths(), resourcePath: fixturesDir})
      await cache2.load()
      expect(fs.existsSync(join(cache2.importsCacheDir, 'content', 'imports.json'))).to.be(false)
      await cache2.readFile(join(fixturesDir, 'imports.less'))
      expect(fs.existsSync(join(cache2.importsCacheDir, 'content', 'imports.json'))).to.be(true)
    })

    it('uses the fallback directory when no cache entry is found in the primary directory', async function () {
      const cache2 = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'cache2'),
        importPaths: cache.getImportPaths(),
        fallbackDir: cache.getDirectory(),
        resourcePath: fixturesDir
      })
      cache2.load()
      await cache2.readFile(join(fixturesDir, 'imports.less'))

      const cache3 = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'cache3'),
        importPaths: cache2.getImportPaths(),
        fallbackDir: cache2.getDirectory(),
        resourcePath: fixturesDir
      })
      cache3.load()

      sinon.spy(cache3, 'parseLess')
      await cache3.readFile(join(fixturesDir, 'imports.less'))
      expect(cache3.parseLess.callCount).to.be(0)
    })
  })

  describe('when syncCaches option is set to true', function () {
    it('writes the cache entry to the fallback cache when initially uncached', async function () {
      const fallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })
      fallback.load()

      cache = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        syncCaches: true,
        fallbackDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })
      cache.load()

      const cacheCss = await cache.readFile(join(fixturesDir, 'a.less'))
      expect(cache.stats.hits).to.be(0)
      expect(cache.stats.misses).to.be(1)

      const fallbackCss = await fallback.readFile(join(fixturesDir, 'a.less'))
      expect(fallback.stats.hits).to.be(1)
      expect(fallback.stats.misses).to.be(0)

      expect(cacheCss).to.be(fallbackCss)
    })

    it('writes the cache entry to the fallback cache when read from the main cache', async function () {
      cache = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        resourcePath: fixturesDir
      })
      cache.load()

      const fallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })
      fallback.load()

      const cacheWithFallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        syncCaches: true,
        fallbackDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })
      cacheWithFallback.load()

      // Prime main cache
      await cache.readFile(join(fixturesDir, 'a.less'))

      // Read from main cache with write to fallback
      await cacheWithFallback.readFile(join(fixturesDir, 'a.less'))

      // Read from fallback cache
      await fallback.readFile(join(fixturesDir, 'a.less'))

      expect(fallback.stats.hits).to.be(1)
      expect(fallback.stats.misses).to.be(0)
    })

    it('writes the cache entry to the main cache when read from the fallback cache', async function () {
      cache = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        resourcePath: fixturesDir
      })
      cache.load()

      const fallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })
      fallback.load()

      const cacheWithFallback = new LessCache({
        cacheDir: join(dirname(cache.getDirectory()), 'synced'),
        syncCaches: true,
        fallbackDir: join(dirname(cache.getDirectory()), 'fallback'),
        resourcePath: fixturesDir
      })
      cacheWithFallback.load()

      // Prime fallback cache
      await fallback.readFile(join(fixturesDir, 'a.less'))

      // Read from fallback with write to main cache
      await cacheWithFallback.readFile(join(fixturesDir, 'a.less'))

      // Read from main cache
      await cache.readFile(join(fixturesDir, 'a.less'))

      expect(cache.stats.hits).to.be(1)
      expect(cache.stats.misses).to.be(0)
    })
  })

  return describe('when providing a resource path and less sources by relative file path', () =>
    it("reads from the provided sources first, and falls back to reading from disk if a valid source isn't available", async function () {
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
      cache1.load()

      expect(await cache1.readFile(join(fixturesDir, 'imports.less'))).to.be(dedent`
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
      cache2.load()

      expect(await cache2.readFile(join(fixturesDir, 'imports.less'))).to.be(dedent`
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
