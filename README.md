# Less Cache [![Build Status](https://travis-ci.org/atom/less-cache.png)](https://travis-ci.org/atom/less-cache)

Caches the compiled `.less` files as `.css`.

## Using

```sh
npm install less-cache
```

```coffeescript
LessCache = require 'less-cache'

cache = new LessCache(cacheDir: '/tmp/less-cache')
css = cache.readFileSync('/Users/me/apps/static/styles.less')
```
