# Research: P8.1 staging profile and external monitors

## 1. R-4 hosted pg_cron and two-phase pg_net

**Decision:** `ai_coverage_feed_pull` stays `30 seconds` with two-phase `pg_net`. The named fallback is not applied. No new migration.

**Named fallback (05 §10, FR-006):** a longer pull interval that stays within the bound, used only if a hosted run fails overlapping runs, response size limits, or growth of `cron.job_run_details`.

**Outcome:** The hosted command was not executed. No `SUPABASE_DB_URL`, `DATABASE_URL`, or `SUPABASE_ACCESS_TOKEN` is set, and `backend/supabase/.temp/project-ref` is absent. This workflow does not deploy to Supabase and does not open a live account, so there is no hosted result that fails those three checks. The fallback is therefore not applied. The existing schedule in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` stays `30 seconds`. The E2E-P8.1-03 checklist records that the live hosted command is not executed here.

## 2. R-6 deploy credentials

**Decision:** Adopt the 01 §7 row R-6 policy as the mitigation. There is no separate fallback.

**Outcome:** The policy is the spike. No CI workflow and no production token are added. Staging stays a separate Cloudflare account and Supabase project, recorded on the staging checklist, with secret values kept out of git. The audit watcher in `ops/staging/audit-watcher.mjs` runs outside both Workers and outside Supabase, reads a token from the environment only when a live read is asked for, and that live read is not executed in this workflow.
