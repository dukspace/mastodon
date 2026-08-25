# Synology staging deployment

Every push to `production` runs a focused verification suite, then dispatches
the exact commit to a dedicated self-hosted runner on the Synology staging
server. The NAS builds the web and streaming images locally, migrates the
staging database, replaces the application containers, and checks their health.
A final GitHub-hosted job verifies the public web and streaming endpoints at
`https://pluviae.day`.

No container registry or inbound SSH access is required.

## Existing staging checkout

The deployment uses the existing checkout at:

```text
/volume1/docker/mastodon
```

It expects that directory to contain:

- a clean `production` checkout whose `origin` points to this repository;
- the existing staging-only `.env.production`;
- the existing `postgres14`, `redis`, and `public/system` data directories; and
- a working `docker compose` v2 installation.

The runner and deployment workflow must not copy, replace, or clean those
persistent directories. The deployment script rejects tracked local changes,
but leaves ignored and untracked staging data untouched.

## Install the self-hosted runner

Create a dedicated DSM user for GitHub Actions. Give it ownership or explicit
read/write access to `/volume1/docker/mastodon` and permission to run Docker
commands without interactive `sudo`. Do not grant the runner access to
production-only paths or secrets.

In GitHub, open **Settings → Actions → Runners → New self-hosted runner**. Select
Linux and the architecture reported by `uname -m` on the NAS, then run the
generated download and configuration commands as the dedicated user. Configure
the runner with these values:

```text
name: mastodon-staging
labels: staging
work folder: _work
```

Keep the default `self-hosted` and `linux` labels. Install the runner as a
persistent service when supported by DSM; otherwise create a DSM Task Scheduler
startup task that runs the runner's `run.sh` as the dedicated user. Confirm in
GitHub that the runner is online and has all three labels:

```text
self-hosted, linux, staging
```

The runner host needs `bash`, `git`, `curl`, Docker Engine, and Docker Compose
v2. Verify the dedicated user before enabling deployment:

```shell
git -C /volume1/docker/mastodon status --short
docker version
docker compose version
```

## Configure the GitHub environment

Create an Actions environment named `staging` with no required reviewers so
deployment remains automatic. Restrict its deployment branches to
`production`, then add these environment variables:

| Variable | Value |
| --- | --- |
| `STAGING_DEPLOY_PATH` | `/volume1/docker/mastodon` |
| `STAGING_BASE_URL` | `https://pluviae.day` |

This design does not require deployment secrets. The existing
`.env.production` remains only on the NAS.

## Deployment behavior

The workflow performs three ordered jobs:

1. `verify` runs the production feature RSpec suite, RuboCop, JavaScript tests,
   ESLint, TypeScript, theme Stylelint, and Compose validation on a
   GitHub-hosted runner.
2. `deploy` runs only after verification succeeds. The Synology runner updates
   the fixed checkout to the exact triggering SHA, builds SHA-tagged images,
   runs `rails db:prepare`, starts the stack, and checks web, streaming, and
   Sidekiq internally.
3. `smoke-test` checks `/health` and `/api/v1/streaming/health` through the
   public `https://pluviae.day` route.

If a newer `production` push supersedes a queued run, the older deployment is
skipped. Build failures leave the currently running containers untouched. A
failure after database migration or container replacement is reported with the
previous checkout SHA, container status, and recent logs; it is not rolled back
automatically because the migrated schema may not be backward-compatible.

After a successful deployment, the script keeps the three newest
`mastodon-staging` and `mastodon-staging-streaming` SHA tags. It does not prune
Docker build cache or unrelated images.

## Initial rollout and recovery

Install and verify the runner and GitHub environment before pushing the workflow
to `production`. The first push containing the workflow will deploy that exact
commit after verification succeeds.

If deployment fails after the new containers start, inspect the Actions log and
the NAS directly:

```shell
cd /volume1/docker/mastodon
export MASTODON_IMAGE_TAG=sha-<failed-or-recovery-sha>
export MASTODON_SOURCE_COMMIT=<failed-or-recovery-sha>
docker compose \
  -f docker-compose.yml \
  -f deploy/staging/compose.build.yml \
  ps
docker compose \
  -f docker-compose.yml \
  -f deploy/staging/compose.build.yml \
  logs --tail=100 web streaming sidekiq
```

Choose a recovery image only after checking migration compatibility. The
workflow intentionally leaves that decision to the operator.
