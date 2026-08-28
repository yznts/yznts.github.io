#!/usr/bin/env bash
#
# Turns GitHub releases into data/releases/<project>.json, which the
# download pages render. Sources are configured in data/releases-sources.json.
#
# Only metadata is taken from GitHub. The download urls point at this site,
# where a worker streams the bytes out of the private release assets, so a
# closed source project is distributed without sending anyone to a repo.
#
# Checksums come from the releases api itself (assets carry a digest), so
# nothing has to be downloaded to publish them.
#
# Usage: scripts/sync-releases.sh [project]

set -euo pipefail

cd "$(dirname "$0")/.."

sources="data/releases-sources.json"
only="${1:-}"

# Downloads are served from this site, not from GitHub.
base="${DOWNLOAD_BASE:-https://yznts.cc/dl}"

# Assets are classified by filename into a platform, an arch and a format.
# The format is what a person actually chooses between ("the .deb one"),
# so it is carried separately from the arch.
#
# Anything unrecognised is skipped rather than guessed at: a wrong platform
# label hands someone a binary that cannot run on their machine.
classify() {
  local name platform="" arch="" format=""
  name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

  # Package formats name their platform by themselves, so they are checked
  # first. .pkg.tar.zst is an arch linux package, .pkg a macos installer.
  case "$name" in
    *.pkg.tar.zst|*.pkg.tar.xz) platform="linux";   format="arch" ;;
    *.deb)                      platform="linux";   format="deb" ;;
    *.rpm)                      platform="linux";   format="rpm" ;;
    *.appimage)                 platform="linux";   format="appimage" ;;
    *.dmg)                      platform="macos";   format="dmg" ;;
    *.pkg)                      platform="macos";   format="pkg" ;;
    *.msi)                      platform="windows"; format="msi" ;;
    *.exe)                      platform="windows"; format="exe" ;;
  esac

  if [ -z "$platform" ]; then
    case "$name" in
      *darwin*|*macos*) platform="macos" ;;
      *windows*|*win32*|*win64*) platform="windows" ;;
      *linux*) platform="linux" ;;
      *) return 1 ;;
    esac
  fi

  if [ -z "$format" ]; then
    case "$name" in
      *.zip)              format="zip" ;;
      *.tar.gz|*.tgz)     format="tar.gz" ;;
      *.tar.xz)           format="tar.xz" ;;
      *)                  format="binary" ;;
    esac
  fi

  case "$name" in
    *universal*)            arch="universal" ;;
    *arm64*|*aarch64*)      arch="arm64" ;;
    *amd64*|*x86_64*|*x64*) arch="amd64" ;;
    *i386*|*386*)           arch="386" ;;
    # Package files often carry no arch at all (babel.deb). The builds
    # behind them are amd64 today, and a wrong arch label here is visible
    # rather than silent: the page prints what it says.
    *)                      arch="amd64" ;;
  esac

  printf '%s %s %s' "$platform" "$arch" "$format"
}

jq -c '.sources[]' "$sources" | while read -r source; do
  project=$(jq -r '.project' <<<"$source")
  repo=$(jq -r '.repo' <<<"$source")
  prefix=$(jq -r '.tag_prefix // ""' <<<"$source")
  keep=$(jq -r '.keep // 10' <<<"$source")

  if [ -n "$only" ] && [ "$only" != "$project" ]; then
    continue
  fi

  echo "syncing $project from $repo (tags: ${prefix}*)"

  # Drafts are not published yet, so they must not reach the site.
  # One page holds 100 releases, far more than a download page shows.
  # Paginating would hand jq one array per page and break the keep slice.
  releases=$(gh api "repos/${repo}/releases?per_page=100" \
    --jq "[.[] | select(.draft | not) | select(.tag_name | startswith(\"${prefix}\"))]")

  out="data/releases/${project}.json"
  mkdir -p "$(dirname "$out")"

  {
    printf '{\n  "project": "%s",\n  "repo": "%s",\n' "$project" "$repo"
    printf '  "updated": "%s",\n  "releases": [\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    first_release=1
    echo "$releases" | jq -c ".[:${keep}][]" | while read -r release; do
      tag=$(jq -r '.tag_name' <<<"$release")
      version="${tag#"$prefix"}"
      version="${version#v}"
      channel="stable"
      # A prerelease flag or a tag like 1.2.0-beta.1 both mean the same thing.
      if [ "$(jq -r '.prerelease' <<<"$release")" = "true" ] || [[ "$version" == *-* ]]; then
        channel="beta"
      fi

      [ $first_release -eq 0 ] && printf ',\n'
      first_release=0

      printf '    {\n      "version": "%s",\n      "tag": "%s",\n' "$version" "$tag"
      printf '      "channel": "%s",\n      "published": "%s",\n' "$channel" "$(jq -r '.published_at' <<<"$release")"
      printf '      "notes": "%s",\n      "assets": [\n' "$(jq -r '.html_url' <<<"$release")"

      first_asset=1
      while read -r asset; do
        name=$(jq -r '.name' <<<"$asset")
        # Checksum manifests and signatures are not downloads themselves.
        case "$name" in *checksums*|*.sha256|*.sig|*.asc) continue ;; esac
        classified=$(classify "$name") || continue
        platform=$(echo "$classified" | cut -d' ' -f1)
        arch=$(echo "$classified" | cut -d' ' -f2)
        format=$(echo "$classified" | cut -d' ' -f3)
        digest=$(jq -r '.digest // ""' <<<"$asset")

        [ $first_asset -eq 0 ] && printf ',\n'
        first_asset=0

        printf '        {\n          "platform": "%s",\n          "arch": "%s",\n          "format": "%s",\n' "$platform" "$arch" "$format"
        printf '          "file": "%s",\n          "url": "%s/%s/%s/%s",\n' \
          "$name" "$base" "$project" "$version" "$name"
        printf '          "size": %s,\n          "sha256": "%s"\n        }' \
          "$(jq -r '.size' <<<"$asset")" "${digest#sha256:}"
      done < <(jq -c '.assets[]' <<<"$release")

      printf '\n      ]\n    }'
    done

    printf '\n  ]\n}\n'
  } > "$out"

  python3 -m json.tool "$out" > "${out}.fmt" && mv "${out}.fmt" "$out"
  echo "  wrote $out ($(jq '.releases | length' "$out") releases)"
done
