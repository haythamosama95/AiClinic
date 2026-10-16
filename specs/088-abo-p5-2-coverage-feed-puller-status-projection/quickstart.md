# Coverage feed puller, projection and status refresh

**Unit**: P5.2a · **Harness**: H-FS · **Verification**: T031 (seven E2E ids)

## 1. What was implemented

The Supabase backend pulls the platform coverage feed on a 30-second schedule, projects events into `ai_internal.clinic_ai_coverage`, and exposes minimal status RPCs. Platform and ABO source are consumed, not modified. Grace, lapse, notices, `days_left`, the `reason` read mapping, and `get_ai_billing_status` belong to P5.2b.

- **30-second pull** (`auth_internal.pull_coverage_feed`) — `pg_cron` job `ai_coverage_feed_pull` runs every 30 seconds. The function issues `net.http_get` to `GET /v1/feed/coverage` with a feed token and `Aip-Contract-Version`, stores a pending request id, validates the response (HTTP 200, matching contract version, ascending `feed_seq`), upserts events under the `(binding_epoch, clinic_seq)` ordering rule, and advances `feed_state.cursor`. Failed or unsupported-version pages increment `consecutive_failures` and leave the cursor and projection unchanged (FR-001, FR-002, FR-004, FR-012, FR-013, FR-014).
- **Projection** — `ai_internal.clinic_ai_coverage` holds the per-org coverage snapshot (no prices or provider data). `ai_internal.feed_state` is a singleton tracking cursor, pending request, `last_success_at`, and `consecutive_failures`. `reason` is stored on upsert when the snapshot state is not `active` or `grace` (FR-003).
- **`request_ai_status_refresh`** — Administrators call `public.request_ai_status_refresh(p_contract_version)` to upsert `ai_internal.status_refresh.requested_at` and trigger an immediate pull. A second call within 10 seconds returns `RATE_LIMITED` without changing the clock (FR-005, FR-016).
- **`get_ai_status`** — `public.get_ai_status(p_contract_version)` returns `available` and `active` when the stored projection state is `active`. `stale` is true when `feed_state.last_success_at` is more than 2 minutes old (FR-006, FR-007, FR-015, FR-016).
- **Dropped availability flag** — `get_ai_availability`, `set_ai_availability`, and the `ai.availability` settings row are removed. Catalog harnesses no longer require or read them (FR-011).
- **H-FS** (`e2e/fullstack/`) — Node runner starts local Supabase, platform (`startWorker` on port 8787), harness worker with the `PLATFORM` binding, ABO (`wrangler dev` on port 8788), and Paymob stub. Clinic calls use supabase-js; owner SQL uses `psql`. CI job `fullstack` runs the P5.1 package harness, then this unit's command (FR-001, FR-016).

## 2. Files this half adds or modifies

| File | FR |
| --- | --- |
| `specs/088-abo-p5-2-coverage-feed-puller-status-projection/quickstart.md` | FR-001–FR-016 |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-011, FR-012, FR-014, FR-015, FR-016 |
| `backend/tests/catalog/harness.sql` | FR-011 |
| `backend/tests/catalog/harness-smoke.sql` | FR-011 |
| `backend/tests/catalog/stage-02-availability-and-enroll.sql` | FR-011 |
| `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` | FR-011 |
| `backend/tests/catalog/stage-06-verify-and-handoff.sql` | FR-011 |
| `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql` | FR-011 |
| `backend/tests/catalog/stage-06-issuer-guards.sql` | FR-011 |
| `e2e/fullstack/test/p5-2.test.mjs` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-012, FR-014, FR-015, FR-016 |
| `.github/workflows/ci.yml` | FR-001, FR-016 |

## 3. Harness command for this unit's tests only

From `e2e/fullstack/`:

```bash
node --import tsx --test test/p5-2.test.mjs
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P5.2-01 | Platform `coverage_event` → `auth_internal.pull_coverage_feed` → `net.http_get` `GET /v1/feed/coverage` → `ai-platform/src/worker.ts` `handleFeedCoverageRequest` → upsert `ai_internal.clinic_ai_coverage` → PostgREST `public.get_ai_status` |
| E2E-P5.2-02 | PostgREST `public.request_ai_status_refresh` → `auth_internal.request_ai_status_refresh` → `ai_internal.status_refresh` → `auth_internal.pull_coverage_feed` |
| E2E-P5.2-05 | Platform `coverage_event` rows for epoch 2 / seq 1 and an older pair → `auth_internal.pull_coverage_feed` → `ai_internal.clinic_ai_coverage` |
| E2E-P5.2-06 | Owner SQL sets `platformFeed.current` to a version the platform rejects → `auth_internal.pull_coverage_feed` → `GET /v1/feed/coverage` → cursor and projection unchanged |
| E2E-P5.2-07 | `cron.job` deactivated → owner SQL sets `last_success_at` and platform `feed_consumer.last_pull_at` → PostgREST `public.get_ai_status` → harness `PLATFORM.feedConsumerHealth` → `ai-platform/src/vendor/entrypoint.ts` |
| E2E-P5.2-08 | Owner SQL sets `feed_state.cursor` to 0 → `auth_internal.pull_coverage_feed` → same projection |
| E2E-P5.2-10 | PostgREST `public.issue_billing_token` → ABO `POST /v1/checkouts` → Supabase stopped → ABO `POST /notify/paymob` → platform grant → Supabase started → `auth_internal.pull_coverage_feed` → PostgREST `public.get_ai_status` |
