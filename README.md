##### Atom and all repositories under Atom will be archived on December 15, 2022. Learn more in our [official announcement](https://github.blog/2022-06-08-sunsetting-atom/)
 # Less Cache [![CI](https://github.com/atom/less-cache/actions/workflows/ci.yml/badge.svg)](https://github.com/atom/less-cache/actions/workflows/ci.yml)
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
