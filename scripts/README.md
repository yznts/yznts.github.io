# Download pages

Binary releases are served from a **public** repo (`yznts/releases`), while the
source repos stay private. That keeps the download links plain GitHub urls: no
token in the browser, no proxy in front, no bandwidth bill. The pages
themselves are static, built from data files rather than fetched from the
GitHub api at runtime, so they carry no rate limit and work with javascript
off.

## How a release reaches the site

1. A project's release workflow uploads its archives to `yznts/releases`,
   under a tag namespaced by project: `zoetrope-v0.2.0`.
2. It then sends a `repository_dispatch` of type `release-published` to this
   repo (needs a token with `contents: write` here, stored as a secret in the
   project repo). Without it, the daily schedule picks the release up anyway.
3. `.github/workflows/sync-releases.yml` runs `scripts/sync-releases.sh`,
   which rewrites `data/releases/<project>.json`, commits it, and dispatches
   the Pages deploy.

## Adding a project

1. Add it to `data/releases-sources.json`:

   ```json
   { "project": "example", "repo": "yznts/releases", "tag_prefix": "example-", "keep": 10 }
   ```

2. Add `content/downloads/example.md` with `project: "example"` in the front
   matter, plus a `requirements` map for the per platform notes.
3. Run `./scripts/sync-releases.sh example` locally, or let the workflow do it.

## Asset naming

The sync classifies assets by filename, and skips anything it cannot place
rather than guessing:

```
<project>-<version>-<platform>-<arch>.<ext>
zoetrope-0.2.0-macos-universal.zip
zoetrope-0.2.0-linux-arm64.tar.gz
```

Recognised platforms: `macos`/`darwin`, `windows`, `linux`. Recognised
arches: `universal`, `arm64`/`aarch64`, `amd64`/`x86_64`/`x64`, `386`.
Checksum manifests and signatures are skipped.

## Beta channel

A release counts as beta when GitHub marks it as a prerelease, or when the
version carries a suffix (`0.3.0-beta.1`). Beta versions are hidden behind
the "Show pre-releases" toggle on the page.

Checksums come from the releases api, which reports a digest per asset, so
nothing has to be downloaded to publish them.
