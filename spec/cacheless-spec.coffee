fs = require 'fs'
{join} = require 'path'

tmp = require 'tmp'
fstream = require 'fstream'

LessCache = require '../src/cacheless'

describe "LessCache", ->
  [cache, fixturesDir] = []

  beforeEach ->
    fixturesDir = null
    cache = new LessCache()
    tmp.dir (error, tempDir) ->
      reader = fstream.Reader(join(__dirname, 'fixtures'))
      reader.on 'end', -> fixturesDir = tempDir
      reader.pipe(fstream.Writer(tempDir))

    waitsFor -> fixturesDir?

  describe "::readFileSync(filePath)", ->
    [css] = []

    beforeEach ->
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))

    it "returns the compiled CSS for a given LESS file path", ->
      expect(css).toBe """
        body {
          font-family: 'Arial';
          display: block;
          border-width: 0;
        }

      """

    it "reflects changes to the file being read", ->
      fs.writeFileSync(join(fixturesDir, 'imports.less'), 'b { display: block; }')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        b {
          display: block;
        }

      """

    it "reflects changes to files imported by the file being read", ->
      fs.writeFileSync(join(fixturesDir, 'b.less'), '@b-display: inline;')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        body {
          font-family: 'Arial';
          display: inline;
          border-width: 0;
        }

      """
