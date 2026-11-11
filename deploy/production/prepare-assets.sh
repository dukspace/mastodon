#!/usr/bin/env bash

# Creates a static release directory without starting any application process.
set -euo pipefail

image="${1:?Usage: prepare-assets.sh IMAGE FULL_SHA NEW_DIRECTORY}"
sha="${2:?Full commit SHA required}"
destination="${3:?New absolute directory required}"

[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Expected a full commit SHA.' >&2; exit 1; }
[[ "$destination" == /* && ! -e "$destination" && ! -L "$destination" ]] || { echo 'Destination must be a new absolute path.' >&2; exit 1; }

image_id="$(docker image inspect --format '{{.Id}}' "$image")"
source_commit="$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$image_id" | sed -n 's/^SOURCE_COMMIT=//p')"
[[ "$source_commit" == "$sha" ]] || { echo 'Image SOURCE_COMMIT does not match requested SHA.' >&2; exit 1; }

temporary="$(mktemp -d "${destination}.tmp.XXXXXX")"
container=''
cleanup() {
  if [[ -n "$container" ]]; then docker rm "$container" >/dev/null; fi
  if [[ -d "$temporary" ]]; then rm -rf -- "$temporary"; fi
}
trap cleanup EXIT

container="$(docker create --network none "$image_id")"
docker cp "$container:/opt/mastodon/public/." "$temporary/"
test -d "$temporary/assets"
test -d "$temporary/packs"
# Nginx needs traversal permission on the directory created by mktemp.
chmod -R a+rX "$temporary"
mv "$temporary" "$destination"
echo "Static release prepared: $destination"
