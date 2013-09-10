{join} = require 'path'

cacheless = require '../src/cacheless'

describe "cacheless", ->
  describe ".readFileSync(filePath)", ->
    it "returns the compiled CSS for a given LESS file path", ->
      css = cacheless.readFileSync(join(__dirname, 'fixtures', 'imports.less'))
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
