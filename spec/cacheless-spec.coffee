fs = require 'fs'
{join} = require 'path'

tmp = require 'tmp'
fstream = require 'fstream'

cacheless = require '../src/cacheless'

describe "cacheless", ->
  [fixturesDir] = []

  beforeEach ->
    tmp.dir (error, tempDir) ->
      reader = fstream.Reader(join(__dirname, 'fixtures'))
      reader.on 'end', -> fixturesDir = tempDir
      reader.pipe(fstream.Writer(tempDir))

    waitsFor -> fixturesDir?

  describe ".readFileSync(filePath)", ->
    [css] = []

    beforeEach ->
      css = cacheless.readFileSync(join(fixturesDir, 'imports.less'))

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
      css = cacheless.readFileSync(join(fixturesDir, 'imports.less'))
      expect(css).toBe """
        b {
          display: block;
        }

      """
