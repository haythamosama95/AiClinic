# AI Platform Gateway

This directory is the Cloudflare Workers deployable for the AiClinic AI gateway — a separate
serverless component from the Flutter app (`frontend/`) and Supabase backend (`backend/`).
Requires **Node.js 22+** (see the repo `.nvmrc`; run `nvm use` from the repository root).
Slice
A1 provisions three isolated wrangler environments (`development`, `staging`, `production`) in
[`wrangler.toml`](./wrangler.toml), each with its own D1, R2, and Durable Object bindings. The
Worker entry point is [`src/worker.ts`](./src/worker.ts); it validates required bindings at
startup and exposes a [`/health`](./src/worker.ts) endpoint that returns build identity
(`BUILD_SHA`) and environment identity (`ENVIRONMENT`). Run `npm test` for the contract suite, or
see [`specs/015-ai-worker-skeleton/quickstart.md`](../specs/015-ai-worker-skeleton/quickstart.md)
for deploy and manual verification steps.
