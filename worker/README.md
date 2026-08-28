# Download worker

Streams binary releases from `yznts.cc/dl/...` out of private GitHub release
assets, so closed source projects are distributed from this domain instead of
from a repository page.

The browser never sees GitHub: the worker holds a read only token, resolves
the release by tag, and pipes the asset back with the right filename. Range
requests pass through, so downloads resume.

## Deploy

```sh
cd worker
npx wrangler login
npx wrangler secret put GITHUB_TOKEN   # paste the token described below
npx wrangler deploy
```

The token is a fine-grained personal access token with **Contents: read-only**
on the private repos being served (`yznts/babel` today). It needs nothing
else. The same token, stored as the `RELEASES_TOKEN` secret in this repo, lets
the release sync workflow read the release metadata.

## Adding a project

Add it to `PROJECTS` in `src/index.js`:

```js
const PROJECTS = {
  babel:   { repo: 'yznts/babel',   tagPrefix: 'v' },
  example: { repo: 'yznts/example', tagPrefix: 'v' },
};
```

Grant the token read access to that repo, redeploy, and add the matching entry
to `data/releases-sources.json` so the pages pick it up.

## Why a worker and not a redirect

A redirect would put the GitHub url in the address bar and leak both the repo
and a signed asset link. Streaming keeps the download on `yznts.cc`, and works
for private repos, which a static link cannot do at all.

Cached responses are immutable: a published asset never changes, so the first
download of a version warms Cloudflare's cache and the rest are served from
it, not from GitHub.
