# Synology staging deployment

Every push to `production` runs the focused verification suite, then builds and
publishes native `linux/amd64` and `linux/arm64` container images on
GitHub-hosted runners. The images are published to:

- `ghcr.io/dukspace/mastodon`
- `ghcr.io/dukspace/mastodon-streaming`

Each successful build receives both the moving `production` tag and an
immutable `sha-<full-commit-sha>` tag. After both multi-platform manifests are
available, the dedicated Synology runner pulls the immutable images, migrates
the staging database, replaces the application containers, and checks their
health. A final GitHub-hosted job verifies the public web and streaming
endpoints at `https://pluviae.day`.

No inbound SSH access is required, and the NAS does not compile application
images.

## Initial GHCR setup

GitHub Container Registry creates new container packages as private packages.
After the first successful image build, open the package settings for both
`mastodon` and `mastodon-streaming` under the `dukspace` account and change
their visibility to **Public**. Public GHCR images can be pulled anonymously;
the visibility change cannot be reversed.

Keep the staging runner offline until both packages are public. Then rerun or
resume the deployment workflow and verify that the host can pull both images
without `docker login`.

## Existing staging checkout

The deployment uses the existing checkout at:

```text
/volume1/docker/mastodon
```

It expects that directory to contain:

- a clean `production` checkout whose `origin` points to this repository;
- the existing staging-only `.env.production`;
- the existing `postgres14`, `redis`, and `public/system` data directories; and
- a working Docker Engine and Docker Compose v2 installation.

The deployment must not copy, replace, or clean those persistent directories.
The script rejects tracked local changes but leaves ignored and untracked
staging data untouched.

## Install the self-hosted runner

Create a dedicated DSM user with ownership or explicit read/write access to
`/volume1/docker/mastodon` and permission to run Docker commands without
interactive `sudo`. Do not grant it access to production-only paths or secrets.

In GitHub, open **Settings → Actions → Runners → New self-hosted runner** and
configure the runner with:

```text
name: mastodon-staging
labels: staging
work folder: _work
```

Keep the default `self-hosted` and `linux` labels. Install it as a persistent
service or start it through DSM Task Scheduler. Confirm that it is online with
all three labels:

```text
self-hosted, linux, staging
```

The runner host needs `bash`, `git`, `curl`, Docker Engine, and Docker Compose
v2. Verify the dedicated user before enabling deployment:

```shell
git -C /volume1/docker/mastodon status --short
docker version
docker compose version
docker pull ghcr.io/dukspace/mastodon:production
docker pull ghcr.io/dukspace/mastodon-streaming:production
```

## Configure the GitHub environment

Create an Actions environment named `staging` with no required reviewers and
restrict its deployment branches to `production`. Add these environment
variables:

| Variable              | Value                      |
| --------------------- | -------------------------- |
| `STAGING_DEPLOY_PATH` | `/volume1/docker/mastodon` |
| `STAGING_BASE_URL`    | `https://pluviae.day`      |

The existing `.env.production` remains only on the NAS. It contains container
environment variables; it does not control Compose image interpolation.

## Deployment behavior

The workflow runs these stages in order:

1. `verify` runs the production feature specs, RuboCop, JavaScript tests,
   ESLint, TypeScript, theme Stylelint, and Compose validation.
2. `build-image` and `build-image-streaming` build both supported architectures
   in parallel and publish the multi-platform GHCR manifests.
3. `deploy` checks out the exact triggering commit, exports
   `MASTODON_IMAGE_TAG=sha-<full-commit-sha>`, pulls all application images,
   runs `rails db:prepare`, starts the stack, and checks web, streaming, and
   Sidekiq internally.
4. `smoke-test` checks `/health` and `/api/v1/streaming/health` through the
   public staging URL.

Workflow runs are serialized so an older build cannot overwrite the moving
`production` tag after a newer build. The deploy script also skips a commit
that has been superseded on `origin/production`.

Image build or pull failures leave the currently running containers untouched.
A failure after database migration or container replacement reports the
previous checkout SHA, service status, and recent logs. It does not roll back
automatically because a migrated schema may not be backward-compatible.

After a successful deployment, the script retains the three newest locally
pulled `sha-*` tags for both application images. It does not prune unrelated
images.

## Manual deployment and recovery

Without `MASTODON_IMAGE_TAG`, Compose uses the current `production` images:

```shell
cd /volume1/docker/mastodon
docker compose pull web streaming sidekiq
docker compose run --rm web bundle exec rails db:prepare
docker compose up -d --remove-orphans
```

For a reproducible deployment or recovery, set the Compose interpolation
variable in the invoking shell. Do not add it only to `.env.production`:

```shell
cd /volume1/docker/mastodon
export MASTODON_IMAGE_TAG=sha-<full-production-commit-sha>
docker compose config --images
docker compose pull web streaming sidekiq
docker compose run --rm web bundle exec rails db:prepare
docker compose up -d --remove-orphans
docker compose ps
docker compose logs --tail=100 web streaming sidekiq
```

Choose a recovery image only after checking migration compatibility. GHCR
retains the immutable SHA tags even after older local copies are removed.
