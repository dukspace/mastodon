#!/usr/bin/env bash

set -euo pipefail

deploy_path="${1:?Usage: deploy.sh DEPLOY_PATH DEPLOY_SHA}"
deploy_sha="${2:?Usage: deploy.sh DEPLOY_PATH DEPLOY_SHA}"

case "$deploy_path" in
  /*) ;;
  *)
    echo "Deployment path must be absolute: $deploy_path" >&2
    exit 1
    ;;
esac

if [[ ! "$deploy_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Deployment SHA must be a full 40-character commit SHA: $deploy_sha" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo 'deployed=false' >> "$GITHUB_OUTPUT"
fi

cd "$deploy_path"

test -d .git
test -f .env.production
test -f docker-compose.yml

for command in git docker curl; do
  command -v "$command" >/dev/null
done

if test -n "$(git status --porcelain --untracked-files=no)"; then
  echo 'Tracked files have local changes; refusing to overwrite them.' >&2
  git status --short --untracked-files=no >&2
  exit 1
fi

git fetch --prune origin production

remote_sha="$(git rev-parse origin/production)"
if [[ "$remote_sha" != "$deploy_sha" ]]; then
  echo "Skipping superseded deployment $deploy_sha; origin/production is $remote_sha."
  exit 0
fi

previous_sha="$(git rev-parse HEAD)"
git switch production
git merge --ff-only "$deploy_sha"

if [[ "$(git rev-parse HEAD)" != "$deploy_sha" ]]; then
  echo 'Checked-out commit does not match requested deployment commit.' >&2
  exit 1
fi

test -f deploy/staging/compose.build.yml

export MASTODON_IMAGE_TAG="sha-$deploy_sha"
export MASTODON_SOURCE_COMMIT="$deploy_sha"

compose=(
  docker compose
  -f docker-compose.yml
  -f deploy/staging/compose.build.yml
)

show_diagnostics() {
  echo "Deployment failed. Previous checkout SHA: $previous_sha" >&2
  "${compose[@]}" ps >&2 || true
  "${compose[@]}" logs --tail=100 web streaming sidekiq >&2 || true
}
trap show_diagnostics ERR

"${compose[@]}" config --quiet
"${compose[@]}" build --pull web streaming
"${compose[@]}" run --rm web bundle exec rails db:prepare
"${compose[@]}" up -d --remove-orphans

healthy=false
for attempt in $(seq 1 60); do
  if "${compose[@]}" exec -T web \
    curl -fsS http://localhost:3000/health >/dev/null && \
    "${compose[@]}" exec -T streaming \
    curl -fsS http://localhost:4000/api/v1/streaming/health >/dev/null && \
    "${compose[@]}" exec -T sidekiq \
    test -f tmp/sidekiq_process_has_started_and_will_begin_processing_jobs; then
    healthy=true
    break
  fi

  echo "Waiting for staging services (${attempt}/60)..."
  sleep 5
done

if [[ "$healthy" != true ]]; then
  echo 'Staging health checks timed out.' >&2
  false
fi

container_source_commit="$(
  # Expand SOURCE_COMMIT inside the container, not in this script.
  # shellcheck disable=SC2016
  "${compose[@]}" exec -T web sh -c 'printf %s "$SOURCE_COMMIT"'
)"
if [[ "$container_source_commit" != "$deploy_sha" ]]; then
  echo "Web container source commit is $container_source_commit, expected $deploy_sha." >&2
  false
fi

stale_tags="$({
  docker image ls \
    --filter 'reference=mastodon-staging:sha-*' \
    --format '{{.Repository}}:{{.Tag}}' |
    while read -r image_ref; do
      created="$(docker image inspect --format '{{.Created}}' "$image_ref")"
      tag="${image_ref#mastodon-staging:}"
      printf '%s %s\n' "$created" "$tag"
    done
} | sort -r | awk 'NR > 3 { print $2 }')"

for stale_tag in $stale_tags; do
  docker image rm \
    "mastodon-staging:$stale_tag" \
    "mastodon-staging-streaming:$stale_tag" || true
done

trap - ERR

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo 'deployed=true'
    echo "deployed_sha=$deploy_sha"
  } >> "$GITHUB_OUTPUT"
fi

echo "Staging deployment is healthy: $MASTODON_IMAGE_TAG"
