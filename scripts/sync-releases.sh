#!/usr/bin/env bash
#
# Turns GitHub releases into data/releases/<project>.json, which the
# download pages render. Sources are configured in data/releases-sources.json.
#
# Binaries live in a public repo so the pages can link them directly, with
# no token in the browser and no proxy in front. Source repos stay private.
#
# Checksums come from the releases api itself (assets carry a digest), so
# nothing has to be downloaded to publish them.
#
# Usage: scripts/sync-releases.sh [project]

set -euo pipefail

cd "$(dirname "$0")/.."

sources="data/releases-sources.json"
only="${1:-}"

# Asset filenames follow <project>-<version>-<platform>-<arch>.<ext>.
# Anything unrecognised is skipped rather than guessed at: a wrong
# platform label sends someone a binary that cannot run.
classify() {
  # Asset names vary in case (macOS, Darwin, Linux), so match on one form.
  local name platform="" arch=""
  name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$name" in
    *darwin*|*macos*|*.dmg|*.pkg) platform="macos" ;;
    *windows*|*.exe|*.msi)        platform="windows" ;;
    *linux*)                      platform="linux" ;;
    *)                            return 1 ;;
  esac
  case "$name" in
    *universal*)          arch="universal" ;;
    *arm64*|*aarch64*)    arch="arm64" ;;
    *amd64*|*x86_64*|*x64*) arch="amd64" ;;
    *386*|*i386*)         arch="386" ;;
    *)                    arch="amd64" ;;
  esac
  printf '%s %s' "$platform" "$arch"
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
        platform=${classified% *}
        arch=${classified#* }
        digest=$(jq -r '.digest // ""' <<<"$asset")

        [ $first_asset -eq 0 ] && printf ',\n'
        first_asset=0

        printf '        {\n          "platform": "%s",\n          "arch": "%s",\n' "$platform" "$arch"
        printf '          "file": "%s",\n          "url": "%s",\n' "$name" "$(jq -r '.browser_download_url' <<<"$asset")"
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
