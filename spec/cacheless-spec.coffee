{join} = require 'path'

tmp = require 'tmp'
fstream = require 'fstream'

cacheless = require '../src/cacheless'

describe "cacheless", ->
  [directoryPath] = []

  beforeEach ->
    tmp.dir (error, tempDirPath) ->
      reader = fstream.Reader(join(__dirname, 'fixtures'))
      reader.on 'end', -> directoryPath = tempDirPath
      reader.pipe(fstream.Writer(tempDirPath))

    waitsFor -> directoryPath?

  describe ".readFileSync(filePath)", ->
    it "returns the compiled CSS for a given LESS file path", ->
      css = cacheless.readFileSync(join(directoryPath, 'imports.less'))
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
