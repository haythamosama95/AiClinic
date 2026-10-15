# E2E reset state inventory

Static source review for P5 in `ci-fix-plan-run-38716221458.md`. No campaign or
test was run for this inventory. It records whether source currently proves a
targeted cleanup boundary can replace the campaign's per-file Supabase reset.

## Campaign expansion

| Campaign | Files selected by `run_campaigns.py` | Source evidence and cleanup | Group decision |
|---|---|---|---|
| `all-ci` | `p5-1.test.mjs`, `p5-2.test.mjs` | Both create/reuse organization and branch fixtures, create staff/auth users, and write test state through SQL/RPCs. P5.1 removes only its prefixed staff users before fixture creation; P5.2 does the same for its own prefix. Neither has campaign teardown for database state; their `after` hooks stop the local workers. P5.2 inserts coverage feed events and updates feed state. | Keep a reset between files. The per-file cleanup does not cover all rows/state created by the preceding file, and P5.2 can select an existing active organization. |
| `all-manual` | All 12 `test/*.test.mjs` files: P5.1, P5.2, P5.2b; P7.2 credential isolation, untrusted callers, vendor entrypoint; P7.3 01–05 and 07. | In addition to the P5 mutations, P5.2b seeds `ai_internal.clinic_ai_coverage`; P7.2/P7.3 tests include direct Postgres fixture SQL and queries against ABO/platform D1. File hooks generally stop workers, while P5.2b has no `after` hook. Wrangler persistence lives in shared `.wrangler/*` paths; `supabase db reset` does not clear those files. | Keep per-file resets. No source-proven cleanup contract covers the cross-file Postgres state, and reset boundaries do not establish isolation for D1 persistence or worker-owned state. |

## Reset-count discrepancy

The CI failure summary reports **33 resets** for `all-manual`, while the
historical and current `run_campaigns.py` expansion of `*.test.mjs` selects 12
files and runs one reset before each file step. The origin of the reported 33 is
unknown from the available source and artifacts. Reconcile that count against
the new per-step reset telemetry in a future campaign run; do not infer extra
steps or change reset behavior from the summary alone.

## Evidence by state owner

- **Postgres/Supabase:** P5.1 and P5.2 call bootstrap and staff-account RPCs and
  issue direct cleanup/fixture SQL. P5.2 additionally writes grant events and
  feed state. P5.2b creates clinic fixtures and seeds/updates AI coverage state.
  Those cleanups are fixture setup for their own prefixes or rows, not a complete
  after-file rollback.
- **Worker/D1:** `wrangler-persist.mjs` assigns stable platform, ABO, harness,
  and Paymob persistence directories under `e2e/fullstack/.wrangler`. P5 and P7
  source applies migrations and writes/query fixtures in D1. A Supabase reset
  cannot prove or provide cleanup for these files.
- **Processes/ports:** test hooks stop started worker stacks. This is process
  cleanup, not a reset of database or D1 records.

No compatibility group is approved by static source evidence alone. A future
reset reduction needs explicit per-file cleanup for all state it writes and
validation that the group leaves the next file's required initial state intact.
The runner now reports Supabase reset, readiness, and Node-step durations with
the campaign and file-step labels, while preserving the existing reset barrier.
