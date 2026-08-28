# Download pages

These projects are closed source, so there is no repository to send anyone
to: the downloads live on this domain. Releases stay in their own private
repos, and `worker/` streams the assets out of them at `yznts.cc/dl/...`, so
nothing about the origin reaches the browser.

Only metadata is copied here. The pages are static, built from
`data/releases/*.json` rather than the GitHub api at runtime, so they carry no
rate limit and work with javascript off.

## How a release reaches the site

1. A project is released as usual, in its own private repo.
2. Its workflow may send a `repository_dispatch` of type `release-published`
   to this repo, for an immediate update. Without it the daily schedule picks
   the release up anyway.
3. `.github/workflows/sync-releases.yml` runs `scripts/sync-releases.sh`,
   which rewrites `data/releases/<project>.json`, commits it, and dispatches
   the Pages deploy.
4. The urls it writes point at `yznts.cc/dl/<project>/<version>/<file>`, which
   the worker serves. Deploy the worker before announcing a project, or the
   links resolve to nothing.

Both the sync workflow (`RELEASES_TOKEN` secret) and the worker use one
fine-grained token with **Contents: read-only** on the private repos.

## Adding a project

1. Add it to `data/releases-sources.json`:

   ```json
   { "project": "example", "repo": "yznts/example", "tag_prefix": "v", "keep": 10 }
   ```

2. Add it to `PROJECTS` in `worker/src/index.js` and redeploy the worker.
3. Add `content/downloads/example.md` with `project: "example"` in the front
   matter, plus a `requirements` map for the per platform notes.
4. Run `GH_TOKEN=... ./scripts/sync-releases.sh example` locally, or let the
   workflow do it.

## Asset naming

The sync classifies assets by filename into a platform, an arch and a format,
and skips anything it cannot place rather than guessing:

```
babel-2026.1-rc31-darwin-universal.dmg   macos   universal  dmg
babel-2026.1-rc31-linux-amd64            linux   amd64      binary
babel.deb                                linux   amd64      deb
babel.pkg.tar.zst                        linux   amd64      arch
```

Package extensions name their own platform (`.deb`, `.rpm`, `.pkg.tar.zst`,
`.dmg`, `.msi`), so those need no platform in the filename; everything else is
matched on `darwin`/`macos`, `windows`, `linux` and on `universal`, `arm64`,
`amd64`, `386`. A package carrying no arch is assumed to be `amd64`, which the
page prints, so a wrong guess is visible rather than silent. Checksum
manifests and signatures are skipped.

The format decides the button label — "Debian / Ubuntu (.deb)" rather than a
second "Intel / AMD (64-bit)" — and which build the big button hands over:
an installer beats a package, a package beats a bare binary.

## Beta channel

A release counts as beta when GitHub marks it as a prerelease, or when the
version carries a suffix (`0.3.0-beta.1`). Beta versions are hidden behind
the "Show pre-releases" toggle on the page.

Checksums come from the releases api, which reports a digest per asset, so
nothing has to be downloaded to publish them.
