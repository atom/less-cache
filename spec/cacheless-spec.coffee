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
        div {
          background-color: #0f0;
        }
        p {
          background-color: #00f;
        }
        body {
          color: #f00;
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
      fs.writeFileSync(join(fixturesDir, 'b.less'), 'b { display: block; }')
      css = cache.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        div {
          background-color: #0f0;
        }
        b {
          display: block;
        }
        body {
          color: #f00;
        }

      """
