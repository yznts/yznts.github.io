# Download pages

These projects are closed source, so there is no repository to send anyone
to. Binaries live in object storage under `releases/`, and the pages are
built from `data/releases/*.json`.

Nothing in this chain runs or needs a token: the site is static, the files
are objects, and publishing happens from your machine with the `gh` login
and ssh key you already have. Storage credentials stay on nue-4.

```
release in a private repo
   │  scripts/publish.sh   (your machine: gh + ssh)
   ├─ binaries ──→ nue-4 ──rclone──→ s3://yznts/releases/<project>/<version>/
   └─ metadata ──→ data/releases/<project>.json ──→ commit ──→ Pages
                                                              │
       https://yznts.nbg1.your-objectstorage.com/releases/<project>/<version>/<file>
```

Public read is scoped to the `releases/` prefix by a bucket policy; see
`deploy/storage/`.

## Publishing

```sh
scripts/publish.sh babel v2026.1-rc31        # pulls the release with gh
scripts/publish.sh babel 2026.1-rc31 --from ./bin   # or take local files
git add data/releases && git commit -m "chore: publish babel 2026.1-rc31" && git push
```

The script uploads the files, prunes versions beyond `keep`, and merges the
release into the data file with sizes and sha256 sums computed locally.

Override the destination with `STATIC_HOST`, `STATIC_REMOTE`, `STATIC_BASE`.

## The storage

`deploy/storage/` holds the bucket policy and how to apply it. Listing is
denied, so an unannounced build is not discoverable by browsing; only the
exact key resolves.

The publish script prunes versions the data file no longer lists, so storage
follows the pages rather than growing forever.

## Adding a project

1. Add it to `data/releases-sources.json` (repo and tag prefix are only used
   by the publish script, to find the release):

   ```json
   { "project": "example", "repo": "yznts/example", "tag_prefix": "v", "keep": 8 }
   ```

2. Add `content/downloads/example.md` with `project: "example"` in the front
   matter, plus a `requirements` map for the per platform notes.
3. Publish. The project entry on the home page grows a download button by
   itself once its data file carries a release.

## Asset naming

Assets are classified by filename into a platform, an arch and a format, and
anything unplaceable is skipped rather than guessed at:

```
babel-2026.1-rc31-darwin-universal.dmg   macos   universal  dmg
babel-2026.1-rc31-linux-amd64            linux   amd64      binary
babel.deb                                linux   amd64      deb
babel.pkg.tar.zst                        linux   amd64      arch
```

Package extensions name their own platform (`.deb`, `.rpm`, `.pkg.tar.zst`,
`.dmg`, `.msi`); everything else is matched on `darwin`/`macos`, `windows`,
`linux` and on `universal`, `arm64`, `amd64`, `386`. A package carrying no
arch is assumed to be `amd64`, which the page prints, so a wrong guess is
visible rather than silent.

The format decides the button label — "Debian / Ubuntu (.deb)" rather than a
second "Intel / AMD (64-bit)" — and which build the big button hands over:
an installer beats a package, a package beats a bare binary.

## Beta

A release is beta when GitHub marks it a prerelease, or when the version
carries a suffix (`2026.1-rc31`). Beta versions sit behind the "Show
pre-releases" toggle, and the page opens on the newest stable one. A project
that has only ever shipped release candidates shows them with the toggle
held on rather than an empty page.
