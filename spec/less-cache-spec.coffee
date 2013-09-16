fs = require 'fs'
{join} = require 'path'

tmp = require 'tmp'
fstream = require 'fstream'

LessCache = require '../src/less-cache'

describe "LessCache", ->
  [cache, fixturesDir] = []

  beforeEach ->
    fixturesDir = null
    tmp.dir (error, tempDir) ->
      reader = fstream.Reader(join(__dirname, 'fixtures'))
      reader.on 'end', ->
        fixturesDir = tempDir
        cacheConfig =
          importPaths: [join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')]
          cacheDir: join(tempDir, 'cache')
        cache = new LessCache(cacheConfig)
      reader.pipe(fstream.Writer(tempDir))

    waitsFor -> fixturesDir?

  describe "::readFileSync(filePath)", ->
    [css] = []

    beforeEach ->
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))

    it "returns the compiled CSS for a given LESS file path", ->
      expect(css).toBe """
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }

      """

    it "returns the cached CSS for a given LESS file path", ->
      spyOn(cache, 'parseLess').andCallThrough()
      expect(cache.readFileSync(join(fixturesDir, 'imports.less'))).toBe """
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }

      """
      expect(cache.parseLess.callCount).toBe 0

    it "reflects changes to the file being read", ->
      fs.writeFileSync(join(fixturesDir, 'imports.less'), 'body { display: block; }')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        body {
          display: block;
        }

      """

    it "reflects changes to files imported by the file being read", ->
      fs.writeFileSync(join(fixturesDir, 'b.less'), '@b: 20;')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        body {
          a: 1;
          b: 20;
          c: 3;
          d: 4;
        }

      """

    xit "reflects changes to files on the import path", ->
      fs.writeFileSync(join(fixturesDir, 'imports-1', 'd.less'), '@d: 40;')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 40;
        }

      """

      fs.unlinkSync(join(fixturesDir, 'imports-1', 'c.less'))
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 40;
        }

      """

      fs.writeFileSync(join(fixturesDir, 'imports-1', 'd.less'), '@d: 400;')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 400;
        }

      """

    it "reflect changes to the import paths array", ->
      spyOn(cache, 'parseLess').andCallThrough()
      cache.setImportPaths([join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')])
      cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(cache.parseLess.callCount).toBe 0

      cache.setImportPaths([join(fixturesDir, 'imports-2'), join(fixturesDir, 'imports-1'), join(fixturesDir, 'import-does-not-exist')])
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        body {
          a: 1;
          b: 2;
          c: 30;
          d: 4;
        }

      """
      expect(cache.parseLess.callCount).toBe 1

      cache.parseLess.reset()
      cache.setImportPaths([join(fixturesDir, 'imports-1'), join(fixturesDir, 'imports-2')])
      expect(cache.readFileSync(join(fixturesDir, 'imports.less'))).toBe """
        body {
          a: 1;
          b: 2;
          c: 3;
          d: 4;
        }

      """
      expect(cache.parseLess.callCount).toBe 0

    it "reuses cached CSS across cache instances", ->
      cache2 = new LessCache(cacheDir: cache.getDirectory(), importPaths: cache.getImportPaths())
      spyOn(cache2, 'parseLess').andCallThrough()
      cache2.readFileSync(join(fixturesDir, 'imports.less'))
      expect(cache2.parseLess.callCount).toBe 0

    it "throws compile errors", ->
      expect(-> cache.readFileSync(join(fixturesDir, 'invalid.less'))).toThrow()

    it "throws file not found errors", ->
      expect(-> cache.readFileSync(join(fixturesDir, 'does-not-exist.less'))).toThrow()
