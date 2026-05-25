# AiClinic Backend

Auth/RBAC migrations live in `supabase/migrations/`. Apply them against the clinic-local stack (see `specs/002-auth-rbac/quickstart.md`):

```bash
cd backend
supabase db reset   # or: supabase migration up
```

## GoTrue custom claims hook

`supabase/config.toml` registers the `get_custom_claims` custom access token hook (`pg-functions://postgres/public/get_custom_claims`). After changing migrations or hook configuration:

1. Re-apply migrations if needed (`supabase db reset` or `supabase migration up`).
2. Restart the auth service so GoTrue reloads hooks:
   - **Supabase CLI local stack**: `supabase stop` then `supabase start`
   - **Docker Compose stack** (`backend/local`): `docker compose restart auth` from `backend/local`

Verification scripts: `backend/tests/auth_flow_smoke.sh`, `backend/tests/rls_isolation.sql`.

## Flutter boundary integration tests

After backend SQL tests pass, run the live Flutter repository suite (see `frontend/test/boundary/README.md`):

```bash
./backend/tests/run_all_backend_tests.sh
cd frontend && ./scripts/run_boundary_tests.sh
```

Requires `frontend/deployment-profile.json` (anon key from `backend/local/.env`) and GoTrue custom claims on Compose (`GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_*` in `backend/local/docker-compose.yml`).

Bootstrap administrator defaults: `backend/seed/bootstrap_admin.env.example`. First-run guide: `docs/setup/bootstrap-admin.md`.

## Configuration

There are **two** deployment paths. Choose ONE — do not mix them.

| Path               | Config files                                              | Used by                                                        |
| ------------------ | --------------------------------------------------------- | -------------------------------------------------------------- |
| Supabase CLI       | `backend/supabase/config.toml`                            | `supabase start`, `supabase db reset`, `supabase migration up` |
| Raw Docker Compose | `backend/local/docker-compose.yml` + `backend/local/.env` | `docker compose up` from `backend/local/`                      |

- **Supabase CLI** is recommended for migration development (runs a full Supabase stack including Auth, Storage, Realtime, Studio).
- **Docker Compose** is for self-hosted or CI deployments where the CLI is not available.

Both paths use the same migration files under `backend/supabase/migrations/`.

---

# Supabase CLI

[![Coverage Status](https://coveralls.io/repos/github/supabase/cli/badge.svg?branch=develop)](https://coveralls.io/github/supabase/cli?branch=develop) [![Bitbucket Pipelines](https://img.shields.io/bitbucket/pipelines/supabase-cli/setup-cli/master?style=flat-square&label=Bitbucket%20Canary)](https://bitbucket.org/supabase-cli/setup-cli/pipelines) [![Gitlab Pipeline Status](https://img.shields.io/gitlab/pipeline-status/sweatybridge%2Fsetup-cli?label=Gitlab%20Canary)
](https://gitlab.com/sweatybridge/setup-cli/-/pipelines)

[Supabase](https://supabase.io) is an open source Firebase alternative. We're building the features of Firebase using enterprise-grade open source tools.

This repository contains all the functionality for Supabase CLI.

- [x] Running Supabase locally
- [x] Managing database migrations
- [x] Creating and deploying Supabase Functions
- [x] Generating types directly from your database schema
- [x] Making authenticated HTTP requests to [Management API](https://supabase.com/docs/reference/api/introduction)

## Getting started

### Install the CLI

Available via [NPM](https://www.npmjs.com) as dev dependency. To install:

```bash
npm i supabase --save-dev
```

When installing with yarn 4, you need to disable experimental fetch with the following nodejs config.

```
NODE_OPTIONS=--no-experimental-fetch yarn add supabase
```

> **Note**
For Bun versions below v1.0.17, you must add `supabase` as a [trusted dependency](https://bun.sh/guides/install/trusted) before running `bun add -D supabase`.

<details>
  <summary><b>macOS</b></summary>

  Available via [Homebrew](https://brew.sh). To install:

  ```sh
  brew install supabase/tap/supabase
  ```

  To install the beta release channel:

  ```sh
  brew install supabase/tap/supabase-beta
  brew link --overwrite supabase-beta
  ```

  To upgrade:

  ```sh
  brew upgrade supabase
  ```
</details>

<details>
  <summary><b>Windows</b></summary>

  Available via [Scoop](https://scoop.sh). To install:

  ```powershell
  scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
  scoop install supabase
  ```

  To upgrade:

  ```powershell
  scoop update supabase
  ```
</details>

<details>
  <summary><b>Linux</b></summary>

  Available via [Homebrew](https://brew.sh) and Linux packages.

  #### via Homebrew

  To install:

  ```sh
  brew install supabase/tap/supabase
  ```

  To upgrade:

  ```sh
  brew upgrade supabase
  ```

  #### via Linux packages

  Linux packages are provided in [Releases](https://github.com/supabase/cli/releases). To install, download the `.apk`/`.deb`/`.rpm`/`.pkg.tar.zst` file depending on your package manager and run the respective commands.

  ```sh
  sudo apk add --allow-untrusted <...>.apk
  ```

  ```sh
  sudo dpkg -i <...>.deb
  ```

  ```sh
  sudo rpm -i <...>.rpm
  ```

  ```sh
  sudo pacman -U <...>.pkg.tar.zst
  ```
</details>

<details>
  <summary><b>Other Platforms</b></summary>

  You can also install the CLI via [go modules](https://go.dev/ref/mod#go-install) without the help of package managers.

  ```sh
  go install github.com/supabase/cli@latest
  ```

  Add a symlink to the binary in `$PATH` for easier access:

  ```sh
  ln -s "$(go env GOPATH)/bin/cli" /usr/bin/supabase
  ```

  This works on other non-standard Linux distros.
</details>

<details>
  <summary><b>Community Maintained Packages</b></summary>

  Available via [pkgx](https://pkgx.sh/). Package script [here](https://github.com/pkgxdev/pantry/blob/main/projects/supabase.com/cli/package.yml).
  To install in your working directory:

  ```bash
  pkgx install supabase
  ```

  Available via [Nixpkgs](https://nixos.org/). Package script [here](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/tools/supabase-cli/default.nix).
</details>

### Run the CLI

```bash
supabase bootstrap
```

Or using npx:

```bash
npx supabase bootstrap
```

The bootstrap command will guide you through the process of setting up a Supabase project using one of the [starter](https://github.com/supabase-community/supabase-samples/blob/main/samples.json) templates.

## Docs

Command & config reference can be found [here](https://supabase.com/docs/reference/cli/about).

## Breaking changes

We follow semantic versioning for changes that directly impact CLI commands, flags, and configurations.

However, due to dependencies on other service images, we cannot guarantee that schema migrations, seed.sql, and generated types will always work for the same CLI major version. If you need such guarantees, we encourage you to pin a specific version of CLI in package.json.

## Developing

To run from source:

```sh
# Go >= 1.22
go run . help
```
