#!/usr/bin/env bash
#
# Publishes a release to the download pages.
#
# Binaries are served as plain files from nue-4 (~/Applications/Static),
# so a download depends on nothing but that box: no tokens in the browser,
# no worker, no third party. This script runs on your machine, with the
# gh login and the ssh key you already have — nothing is stored in CI.
#
# Usage:
#   scripts/publish.sh babel v2026.1-rc31          # from a GitHub release
#   scripts/publish.sh babel 2026.1-rc31 --from ./bin
#
# Then commit the changed data file and push; Pages rebuilds from it.

set -euo pipefail
cd "$(dirname "$0")/.."

project="${1:?usage: publish.sh <project> <tag> [--from <dir>]}"
tag="${2:?usage: publish.sh <project> <tag> [--from <dir>]}"
shift 2

from=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) from="${2:?--from needs a directory}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

host="${STATIC_HOST:-nue-4}"
root="${STATIC_ROOT:-Applications/Static/data}"
base="${STATIC_BASE:-https://static.yznts.cc}"
sources="data/releases-sources.json"

repo=$(jq -r --arg p "$project" '.sources[] | select(.project==$p) | .repo' "$sources")
prefix=$(jq -r --arg p "$project" '.sources[] | select(.project==$p) | .tag_prefix // ""' "$sources")
keep=$(jq -r --arg p "$project" '.sources[] | select(.project==$p) | .keep // 8' "$sources")
[ -n "$repo" ] || { echo "$project is not in $sources" >&2; exit 1; }

version="${tag#"$prefix"}"
version="${version#v}"

# A release is beta when GitHub says so, or when the version says so.
channel="stable"
case "$version" in *-*) channel="beta" ;; esac
published=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ -z "$from" ] && command -v gh >/dev/null; then
  meta=$(gh release view "$tag" --repo "$repo" --json isPrerelease,publishedAt 2>/dev/null || true)
  if [ -n "$meta" ]; then
    [ "$(jq -r '.isPrerelease' <<<"$meta")" = "true" ] && channel="beta"
    published=$(jq -r '.publishedAt' <<<"$meta")
  fi
fi

# Collect the files.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
if [ -n "$from" ]; then
  cp "$from"/* "$staging/"
else
  echo "downloading $tag from $repo"
  gh release download "$tag" --repo "$repo" --dir "$staging"
fi

# Assets are classified by filename into a platform, an arch and a format.
# Anything unrecognised is skipped rather than guessed at: a wrong platform
# label hands someone a binary that cannot run on their machine.
classify() {
  local name platform="" arch="" format=""
  name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
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
      *.zip) format="zip" ;;
      *.tar.gz|*.tgz) format="tar.gz" ;;
      *.tar.xz) format="tar.xz" ;;
      *) format="binary" ;;
    esac
  fi
  case "$name" in
    *universal*)            arch="universal" ;;
    *arm64*|*aarch64*)      arch="arm64" ;;
    *amd64*|*x86_64*|*x64*) arch="amd64" ;;
    *i386*|*386*)           arch="386" ;;
    *)                      arch="amd64" ;;
  esac
  printf '%s %s %s' "$platform" "$arch" "$format"
}

# Build the asset list, dropping what the pages cannot label.
assets="[]"
for file in "$staging"/*; do
  [ -f "$file" ] || continue
  name=$(basename "$file")
  case "$name" in *checksums*|*.sha256|*.sig|*.asc) rm -f "$file"; continue ;; esac
  if ! classified=$(classify "$name"); then
    echo "  skipping $name: no platform in the name"
    rm -f "$file"
    continue
  fi
  assets=$(jq -c \
    --arg platform "$(cut -d' ' -f1 <<<"$classified")" \
    --arg arch     "$(cut -d' ' -f2 <<<"$classified")" \
    --arg format   "$(cut -d' ' -f3 <<<"$classified")" \
    --arg file     "$name" \
    --arg url      "$base/$project/$version/$name" \
    --argjson size "$(wc -c <"$file" | tr -d ' ')" \
    --arg sha      "$(shasum -a 256 "$file" | cut -d' ' -f1)" \
    '. + [{platform:$platform,arch:$arch,format:$format,file:$file,url:$url,size:$size,sha256:$sha}]' \
    <<<"$assets")
done
[ "$(jq 'length' <<<"$assets")" -gt 0 ] || { echo "nothing publishable in $tag" >&2; exit 1; }

# Upload, then drop versions beyond the keep window.
echo "uploading to $host:$root/$project/$version"
# The rsync macOS ships (openrsync) creates no intermediate directories
# and has no --chmod, so the target is prepared and fixed up over ssh.
ssh "$host" "mkdir -p '$root/$project/$version'"
rsync -a "$staging/" "$host:$root/$project/$version/"
ssh "$host" "chmod 755 '$root/$project/$version' && chmod 644 '$root/$project/$version'/*"
ssh "$host" "cd '$root/$project' && ls -1dt */ 2>/dev/null | tail -n +$((keep + 1)) | xargs -r rm -rf"

# Merge into the data file the pages read.
out="data/releases/$project.json"
mkdir -p "$(dirname "$out")"
[ -f "$out" ] || printf '{"project":"%s","releases":[]}\n' "$project" > "$out"
jq --arg version "$version" --arg tag "$tag" --arg channel "$channel" \
   --arg published "$published" --argjson assets "$assets" --argjson keep "$keep" \
   '.project = .project
    | .releases = ([{version:$version,tag:$tag,channel:$channel,published:$published,assets:$assets}]
        + (.releases | map(select(.version != $version))))
    | .releases = (.releases | sort_by(.published) | reverse | .[:$keep])' \
   "$out" > "$out.tmp" && mv "$out.tmp" "$out"

echo
echo "published $project $version ($channel), $(jq 'length' <<<"$assets") files"
echo "commit $out and push to update the pages"
