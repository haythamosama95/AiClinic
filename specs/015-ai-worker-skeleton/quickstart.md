# Quickstart: Worker skeleton and environments (A1)

Slice **A1** provisions the Cloudflare AI Gateway Worker skeleton in `ai-platform/` with three
isolated environments — `development`, `staging`, and `production` — each with its own D1, R2,
and Durable Object bindings, plus a `/health` endpoint that reports build and environment
identity.

## 1. Prerequisites

From the repository root, activate the pinned Node version:

```bash
nvm install   # reads .nvmrc (Node 22)
nvm use
node -v       # expect v22.x
```

- Node.js **22+** and npm (enforced by `ai-platform/package.json` `engines` and repo `.nvmrc`; Wrangler 4.x requires Node 22)
- A Cloudflare account with the **Workers Paid** subscription enabled
- **R2 enabled** on that account ([Cloudflare Dashboard → R2](https://dash.cloudflare.com/) → enable R2; deploy fails with error `10042` until this is done)
- D1 databases, R2 buckets, and Durable Object namespaces referenced in `wrangler.toml` provisioned in Cloudflare (update `database_id` values with real IDs from `wrangler d1 create`; create R2 buckets with `wrangler r2 bucket create <name>`)
- `wrangler` authenticated to that account (from `ai-platform/`):

```bash
cd ai-platform
npx wrangler login
```

## 2. Install dependencies

From the repository root:

```bash
cd ai-platform
npm install
```

## 3. Run the automated suite (reproduce the green run)

```bash
npm test
```

This runs `vitest run` and exercises all four named A1 tests (T1–T4) via
`@cloudflare/vitest-pool-workers`. Expect four passing tests across `test/env-deploys.test.ts`
and `test/health.test.ts`.

## 4. Deploy each environment

Before the first deploy, provision Cloudflare resources for each environment if they do not exist
yet:

```bash
# Example for development — repeat for staging and production names in wrangler.toml
npx wrangler d1 create ai-platform-development
npx wrangler r2 bucket create ai-platform-development
```

Copy each `database_id` from the `d1 create` output into the matching `[[env.*.d1_databases]]`
block in `wrangler.toml`.

Set the build identity to the current git commit SHA before deploying. From `ai-platform/`:

```bash
export BUILD_SHA="$(git -C .. rev-parse HEAD)"

npx wrangler deploy --env development --var BUILD_SHA:"$BUILD_SHA"
npx wrangler deploy --env staging     --var BUILD_SHA:"$BUILD_SHA"
npx wrangler deploy --env production  --var BUILD_SHA:"$BUILD_SHA"
```

Each command deploys to its own Worker name and binding set defined in `wrangler.toml`:

| Environment   | Worker name                       |
| ------------- | --------------------------------- |
| `development` | `ai-platform-gateway-development` |
| `staging`     | `ai-platform-gateway-staging`     |
| `production`  | `ai-platform-gateway-production`  |

`wrangler deploy` prints the deployed URL when the command succeeds. Use that URL for the health
check in the next step.

## 5. Call the health endpoint

The health endpoint path is `/health`. It returns JSON with two fields only:

- `build` — the git commit SHA injected as `BUILD_SHA` at deploy time
- `environment` — the wrangler environment name (`development`, `staging`, or `production`)

Replace `<worker-url>` with the URL from the deploy output (or
`https://<worker-name>.<account-subdomain>.workers.dev`):

```bash
curl -s "https://<worker-url>/health" | jq .
```

Expected shape:

```json
{
  "build": "<git-commit-sha>",
  "environment": "development"
}
```

Repeat for each deployed environment and confirm `environment` matches the wrangler `--env` value
and `build` matches the SHA you passed at deploy time.

## 6. Local smoke check (optional)

To exercise a single environment locally without deploying:

```bash
npm run dev
```

In another terminal:

```bash
curl -s "http://127.0.0.1:8787/health" | jq .
```

Local dev uses the placeholder `BUILD_SHA = "local"` from `wrangler.toml` and returns
`environment: "development"`.
