# Less Cache [![Build Status](https://travis-ci.org/atom/less-cache.svg?branch=master)](https://travis-ci.org/atom/less-cache)

Caches the compiled `.less` files as `.css`.

## Using

```sh
npm install less-cache
```

```javascript
const LessCache = require('less-cache')
const cache = new LessCache({cacheDir: '/tmp/less-cache'})

// This method returns a {Promise}, but you can avoid waiting on it as it will
// be waited upon automatically when calling `readFile` or `cssForFile` later.
cache.load()
const css1 = await cache.readFile('/Users/me/apps/static/styles.less')

// Similarly to `load`, this method will return a {Promise} and subsequent calls
// to `readFile` or `cssForFile` will automatically wait on it.
cache.setImportPaths(['path-1', 'path-2'])
const css2 = await cache.readFile('/Users/me/apps/static/styles.less')
```
