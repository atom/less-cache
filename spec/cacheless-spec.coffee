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
    it "returns the compiled CSS for a given LESS file path", ->
      css = cacheless.readFileSync(join(fixturesDir, 'imports.less'))
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
