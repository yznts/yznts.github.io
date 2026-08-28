# Download pages

These projects are closed source, so there is no repository to send anyone
to. Binaries are served as plain static files from nue-4, and the pages are
built from `data/releases/*.json`.

Nothing in this chain needs a token, a worker or a third party service. The
site is static, the file server is nginx, and publishing runs from your
machine with the `gh` login and ssh key you already have.

```
release in a private repo
   │  scripts/publish.sh   (your machine: gh + rsync)
   ├─ binaries ──→ nue-4:~/Applications/Static/data/<project>/<version>/
   └─ metadata ──→ data/releases/<project>.json ──→ commit ──→ Pages
                                                              │
                        static.yznts.cc/<project>/<version>/<file>
```

## Publishing

```sh
scripts/publish.sh babel v2026.1-rc31        # pulls the release with gh
scripts/publish.sh babel 2026.1-rc31 --from ./bin   # or take local files
git add data/releases && git commit -m "chore: publish babel 2026.1-rc31" && git push
```

The script uploads the files, prunes versions beyond `keep`, and merges the
release into the data file with sizes and sha256 sums computed locally.

Override the destination with `STATIC_HOST`, `STATIC_ROOT`, `STATIC_BASE`.

## The file server

`deploy/static/` holds the compose file and nginx config deployed to
nue-4 at `~/Applications/Static`. It sits behind the same traefik as the
other apps, so Cloudflare terminates tls as usual.

```sh
scp deploy/static/* nue-4:~/Applications/Static/
ssh nue-4 'cd ~/Applications/Static && docker compose up -d'
```

Directory listing is off, so an unannounced build is not discoverable, and
paths carry the version, so files are served immutable and cache forever.

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
