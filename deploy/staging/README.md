# Synology staging deployment

Every push to `staging` runs the focused verification suite, then builds and
publishes native `linux/amd64` and `linux/arm64` container images on
GitHub-hosted runners. The images are published to:

- `ghcr.io/dukspace/mastodon`
- `ghcr.io/dukspace/mastodon-streaming`

Each successful build receives both the moving `staging` tag and a
`sha-<full-commit-sha>` tag. Treat SHA tags as immutable release artifacts and
record their digests before promotion. Build metadata is `dukspace`, independent
of the target environment. After both multi-platform manifests are
available, the dedicated Synology runner pulls the immutable images, migrates
the staging database, replaces the application containers, and checks their
health. A final GitHub-hosted job verifies the public web and streaming
endpoints at `https://pluviae.day`.

No inbound SSH access is required, and the NAS does not compile application
images.

For branch roles and the one-time transition from the retained `production`
branch, see [Deployment flow](../README.md).

## GHCR access

The workflow supports private GHCR packages. Both build jobs publish with
`GITHUB_TOKEN`, and the Synology deploy job logs in with that token and
`packages: read` before pulling. Keep both packages linked to this repository
and grant the repository Actions access in each package's settings.
There is no need to make the packages public.

For manual pulls, authenticate as the same OS user that runs Docker, using an
account/token with package read access and `docker login --password-stdin`.
Do not put tokens in command-line arguments or repository files. The workflow's
login may be removed at job cleanup, so do not rely on it for later manual pulls.

## Existing staging checkout

The deployment uses the existing checkout at:

```text
/volume1/docker/mastodon
```

It expects that directory to contain:

- a clean `staging` checkout whose `origin` points to this repository;
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
docker pull ghcr.io/dukspace/mastodon:staging
docker pull ghcr.io/dukspace/mastodon-streaming:staging
```

## Configure the GitHub environment

Create an Actions environment named `staging` with no required reviewers and
restrict its deployment branches to `staging`. Add these environment
variables:

| Variable              | Value                      |
| --------------------- | -------------------------- |
| `STAGING_DEPLOY_PATH` | `/volume1/docker/mastodon` |
| `STAGING_BASE_URL`    | `https://pluviae.day`      |

The existing `.env.production` remains only on the NAS. It contains container
environment variables; it does not control Compose image interpolation.
The filename and `RAILS_ENV=production` / `NODE_ENV=production` describe
Mastodon runtime mode and remain unchanged on Staging.

## Deployment behavior

The workflow runs these stages in order:

1. `verify` runs the custom feature specs, RuboCop, JavaScript tests,
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
`staging` tag after a newer build. The deploy script also skips a commit
that has been superseded on `origin/staging`.

Image build or pull failures leave the currently running containers untouched.
A failure after database migration or container replacement reports the
previous checkout SHA, service status, and recent logs. It does not roll back
automatically because a migrated schema may not be backward-compatible.

After a successful deployment, the script retains the three newest locally
pulled `sha-*` tags for both application images. It does not prune unrelated
images.

## Manual deployment and recovery

Without `MASTODON_IMAGE_TAG`, Compose uses the current `staging` images:

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
export MASTODON_IMAGE_TAG=sha-<full-staging-commit-sha>
docker compose config --images
docker compose pull web streaming sidekiq
docker compose run --rm web bundle exec rails db:prepare
docker compose up -d --remove-orphans
docker compose ps
docker compose logs --tail=100 web streaming sidekiq
```

Choose a recovery image only after checking migration compatibility. Removing
local images does not delete GHCR tags. Keep promoted SHA tags and
their digests available in GHCR for recovery; do not retag or rebuild them.

Production promotion uses the exact verified SHA images and the separate
[Production runbook](../production/README.md). This workflow never deploys to
Production and no push or Git release tag triggers a Production deployment.

## Local script verification

Run `python3 deploy/staging/test_deploy.py` to check branch selection, stale
deployment skipping, local-change protection and fast-forward-only updates.
The tests use temporary local Git repositories and a fake Docker executable;
they never contact GitHub, a NAS, Docker Engine or Production.
