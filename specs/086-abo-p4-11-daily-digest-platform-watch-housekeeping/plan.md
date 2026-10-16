# Implementation Plan: Daily digest, platform watch, housekeeping and ABO rebuild

**Branch**: `ai/086-abo-p4-11-daily-digest-platform-watch-housekeeping` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

The ABO daily 06:00 UTC `scheduled()` cron `0 6 * * *` sends one digest email, raises AL-14 for keys inside 30 days of `not_after`, deletes operational rows past the 03 §8 retention, and pings the heartbeat URL. The hourly cron `0 * * * *` raises AL-15 from `feedConsumerHealth` and AL-22 from the issuer-key pins and the last-seen operator-credential list. After data loss, `abo/src/rebuild.ts` replays `ledger/` into an empty D1, recomputes status, re-inquires the gap, compares `listGrants`, and ends on a clean reconciliation. Phase P4, size M, **Depends** P4.10 and P3.9, in parallel with P5.x.

## Technical Context

**Language/Version**: TypeScript on the existing ABO worker (`abo/package.json`, `engines.node` `>=22`, `main = src/worker.ts`). Tests use Vitest `~3.2.4` and `@cloudflare/vitest-pool-workers` `0.8.71`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library. Platform reads use the existing `PLATFORM` service binding (`entrypoint = "VendorEntrypoint"`). Time uses `clockNowMs` / `clockNowIso` in `abo/src/clock.ts`. Pins use the existing `ISSUER_KEYS` set of `{kid, public_key}` (and, when `TEST_CLOCK === "1"`, the `harness_issuer_pin` rows billing auth already prefers). Alerts use the existing `raiseAlert` / `sendDueAlerts` path and `SEND_EMAIL`. The provider stays behind `providerForId` in `abo/src/provider/registry.ts`.

**Storage**: ABO D1 and R2. Commercial facts stay in the append-only tables and in `ledger/<fact_seq>.ndjson`. Housekeeping deletes only completed `work` rows, sent `alert` rows, and `hmac-invalid/` samples. New operational rows are `scheduled_job_run`, `seen_operator_credential`, and `channel_version_seen`. `fact_log.row_json` stores the canonical fact so export can replay it.

**Testing**: Harness H-XW. One new file `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` under `abo/vitest.cross-worker.config.ts`. Entry is `runScheduled` from `abo/test/system/harness.ts`, except E2E-P4.11-06, which imports `abo/src/rebuild.ts` and calls it in-process. The test wipes D1. `send_email` and the heartbeat fetch are the existing captures (rule V6). No local scenario sleeps more than 2 s (rule V4).

**Target Platform**: The existing ABO worker. Live entries are `scheduled()` on `abo/src/worker.ts` for `0 6 * * *` and `0 * * * *` (`abo/wrangler.toml` already lists both), and the in-process rebuild call. Platform methods are `VendorEntrypoint.listIssuerKeys`, `listOperatorCredentials`, `listServiceKeys`, `feedConsumerHealth`, and `listGrants` over `PLATFORM`. H-XW runs the platform worker from source.

**Project Type**: ABO Cloudflare Worker (D1, R2, crons). One codebase, `abo`. No wiring exception.

**Performance Goals**: One operator and a few orders a day (02 §7, principle I). One digest per daily run. Hourly watch is three class-M reads plus the comparisons. Housekeeping is a dated delete on the same daily run.

**Constraints**: Commercial facts are not deleted (03 §8, FR-005). Ledger replay inserts pass the append-only triggers (05 §5.1). `feedConsumerHealth` is called as frozen by P3.9. No new `VendorEntrypoint` method and no change to `listIssuerKeys`, `listOperatorCredentials`, `listGrants`, or `feedConsumerHealth`. The digest is one `send_email` body with no separate schema (clarification). The rebuild script takes provider transaction references and uses the existing `ProviderPort.inquire` input (clarification). Per-channel version counts are only the channels the ABO observes, `aboClinic` and `aboConsole` (06 §6, `abo/src/clinic-api/version.ts`).

**Scale/Scope**: Seven H-XW scenarios, three user stories, size M (20–32 tasks).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

Re-checked against 02 §7 and `.specify/memory/constitution.md`:

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One daily digest and one hourly watch on the existing ABO worker crons. No second product and no clinic-desktop flow (spec §4.1). |
| II. Replaceable layer boundaries | Codebase is `abo`. Platform reads go through the frozen `VendorEntrypoint` methods. The provider stays behind the existing port. No clinic database credential. |
| III. Backend authority and data integrity | This unit does not write clinic PostgreSQL. ABO commercial facts stay append-only. Replay inserts pass those triggers. `checkout_status` is recomputed from `checkout_event`. |
| IV. Secure and human-gated operations | Class-M reads use the existing service binding. The last-seen credential list is filled only from the ABO's own `ok` `registerOperatorCredential` `detail`, including bootstrap (05 §1, 05 §2 row AL-22). Commercial facts are not hard-deleted. 03 §8 operational retention (done work, sent alerts, invalid-HMAC samples) is the housekeeping this unit runs. |
| V. Operational continuity | FM-19 recovery is the §5.1 script plus runbook and ends with `runReconciliation`. A failed digest send is retried and the daily heartbeat ping is still sent. |
| Workflow automation | The new work is further branches of the existing crons, plus one operator script. No DAG engine. |
| Higher operational burden | The burden is the digest, the alerts, and the runbook already named in 05 §3.4, 05 §2, and 05 §5.1. |

## Project Structure

### Documentation (this feature)

```text
specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/
├── plan.md
├── spec.md
├── escalations.md
└── quickstart.md          # implement writes this after the H-XW file is green
```

No `research.md` (**Spikes** is `None`). No `data-model.md` (spec §3.2 defines no entities). No `contracts/` (**Freezes** is `None`). No `tasks.md` in this phase.

`quickstart.md` sections, written by implement after the harness is green:

1. What was implemented — daily digest, AL-14, AL-15, AL-22, housekeeping, the daily heartbeat ping, and the ABO rebuild module, operator script, and runbook.
2. Files added or modified — the Files section of this plan.
3. Harness command for this unit's tests only — the command in Test Layout.
4. Entry point → module chain per E2E id — the table below.

| E2E id | Chain |
| --- | --- |
| E2E-P4.11-01 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `SEND_EMAIL` |
| E2E-P4.11-02 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `PLATFORM.listIssuerKeys` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-03 | `runScheduled("0 * * * *")` → `scheduled()` → `abo/src/watch/hourly.ts` → `PLATFORM.feedConsumerHealth` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-04 | `runScheduled("0 * * * *")` → `scheduled()` → `abo/src/watch/hourly.ts` → `PLATFORM.listIssuerKeys` and `PLATFORM.listOperatorCredentials` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-05 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/housekeeping/run.ts` |
| E2E-P4.11-06 | H-XW test imports `abo/src/rebuild.ts` → R2 `ledger/` → D1 inserts → `providerForId` inquire → `PLATFORM.listGrants` → `abo/src/work/grant.ts` → `runReconciliation` |
| E2E-P4.11-07 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `SEND_EMAIL` (retry) → outbound fetch of `HEARTBEAT_URL` |

### Source Code (repository root)

```text
abo/
├── REBUILD.md
├── migrations/0009_digest_watch.sql
├── scripts/rebuild-abo.ts
├── src/
│   ├── digest/run.ts
│   ├── housekeeping/run.ts
│   ├── rebuild.ts
│   ├── watch/hourly.ts
│   ├── worker.ts
│   ├── alert/index.ts
│   ├── clinic-api/auth.ts
│   ├── clinic-api/version.ts
│   ├── ops/index.ts
│   ├── records/append.ts
│   ├── records/export.ts
│   └── work/runner.ts
└── test/system/digest-watch-rebuild.cross-worker.test.ts
```

**Structure Decision**: Source stays the ABO worker. The daily digest, AL-14, and the digest retry live in `abo/src/digest/run.ts`. The hourly AL-15 and AL-22 checks live in `abo/src/watch/hourly.ts`. Housekeeping lives in `abo/src/housekeeping/run.ts`. Rebuild lives in `abo/src/rebuild.ts`, with `abo/scripts/rebuild-abo.ts` and `abo/REBUILD.md` as the operator wrapper and runbook. `scheduled()` in `abo/src/worker.ts` is the live entry for both crons. No second codebase.

## Consumes Binding

| Consumes | Existing module | This unit |
| --- | --- | --- |
| P4.10 | None. The unit row freezes nothing. Reconciliation remains `runReconciliation` in `abo/src/reconciliation/run.ts`. | Calls that function. Does not change it. |
| P3.9 HTTP feed contract | `GET /v1/feed/coverage` on `ai-platform/src/worker.ts`, frozen in `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-coverage.md` | Not called. Not modified. |
| P3.9 `/v1/coverage` response | `ai-platform/src/coverage-read/index.ts`, frozen in `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/coverage-get.md` | Not called. Not modified. |
| P3.9 `feedConsumerHealth` | `VendorEntrypoint.feedConsumerHealth` in `ai-platform/src/vendor/entrypoint.ts`, frozen in `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-consumer-health.md`. Class M. Argument `{contract_version}` only. `detail` is JSON `{last_pull_at, last_cursor}`. | Called over `PLATFORM`. Not modified. |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `abo/migrations/0009_digest_watch.sql` | Create `scheduled_job_run (job TEXT PRIMARY KEY, last_run_at TEXT NOT NULL)`, `seen_operator_credential (credential_id TEXT NOT NULL, public_key_cose TEXT NOT NULL, alg TEXT NOT NULL, PRIMARY KEY (credential_id, public_key_cose, alg))`, and `channel_version_seen (channel TEXT NOT NULL, contract_version INTEGER NOT NULL, received INTEGER NOT NULL, unsupported INTEGER NOT NULL, PRIMARY KEY (channel, contract_version))`. `ALTER TABLE fact_log ADD COLUMN row_json TEXT`. | FR-001, FR-004, FR-006 |
| `abo/src/digest/run.ts` | Daily digest body, AL-14, digest send with one retry, and the `channel_version_seen` writer used by the version gate. | FR-001, FR-002, FR-007 |
| `abo/src/watch/hourly.ts` | AL-15, AL-22 pin comparison, AL-22 credential comparison, and `rememberOperatorCredential`. | FR-003, FR-004 |
| `abo/src/housekeeping/run.ts` | Retention deletes. | FR-005 |
| `abo/src/rebuild.ts` | `rebuildAbo`. | FR-006 |
| `abo/scripts/rebuild-abo.ts` | Operator wrapper. Imports `rebuildAbo`. | FR-006 |
| `abo/REBUILD.md` | Runbook. | FR-006 |
| `abo/src/worker.ts` | `PLATFORM.feedConsumerHealth` on `Env`. Daily and hourly branches call the new modules. Each cron stamps `scheduled_job_run` when the table exists. Daily branch pings `HEARTBEAT_URL`. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007 |
| `abo/src/alert/index.ts` | Add `AL-14`, `AL-15`, and `AL-22` to `AlertCode`. AL-14 repeats daily. AL-15 and AL-22 repeat hourly. | FR-002, FR-003, FR-004 |
| `abo/src/clinic-api/auth.ts` | Export the existing pin loader so the hourly comparison uses the same `{kid, public_key}` set. | FR-004 |
| `abo/src/clinic-api/version.ts` | On each `aboClinic` or `aboConsole` decision, increment `channel_version_seen`. A missing table is ignored. | FR-001 |
| `abo/src/ops/index.ts` | After an `ok` `registerOperatorCredential` result, including bootstrap, call `rememberOperatorCredential` with `{credential_id, public_key_cose, alg}` from `detail`. A `pending` row is stored then. | FR-004 |
| `abo/src/records/append.ts` | `insertFactLog` writes `row_json` as the canonical JSON whose SHA-256 is `row_sha256`. | FR-006 |
| `abo/src/records/export.ts` | The `ledger/<fact_seq>.ndjson` line keeps `fact_seq`, `table`, `key`, and `row_sha256`, and adds `row` from `row_json` when present. Still one JSON line. Still no payer `name`, `email`, or `phone`. | FR-006 |
| `abo/src/clinic-api/checkouts.ts`, `abo/src/work/runner.ts`, `abo/src/work/grant.ts`, `abo/src/work/reversal.ts`, `abo/src/ops/index.ts`, `abo/src/reconciliation/run.ts` | Existing `INSERT INTO fact_log` statements go through `insertFactLog`. `reconciliation/run.ts` changes only that insert. | FR-006 |
| `abo/src/work/runner.ts` | Export the existing paid-confirmation recording so rebuild can record a payment that inquiry finds and that `payment` does not yet contain. | FR-006 |
| `abo/vitest.cross-worker.config.ts` | Include `test/system/digest-watch-rebuild.cross-worker.test.ts`. | FR-001–FR-007 |
| `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` | The seven scenarios. | FR-001–FR-007 |
| `abo/test/system/catalogue.system.test.ts` | `emailsWithAl16` matches subject `AL-16`. The digest subject is `digest`, so an open AL-16 quoted in the digest does not change the E2E-P4.1-08 count. | FR-001 |

`abo/src/reconciliation/run.ts` is not otherwise modified. `ai-platform/` is not modified.

## Test Layout

Harness H-XW. File `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`. Config `abo/vitest.cross-worker.config.ts`. Titles start with the E2E id (rule V3). Each test calls the entry below and fails while the behavior it names is absent. The test applies `abo/migrations/0009_digest_watch.sql` and the earlier ABO migrations it needs. Clock moves use the existing test clock. No sleep over 2 s.

Unit command, this file only:

```bash
node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/digest-watch-rebuild.cross-worker.test.ts
```

Run from `abo/`.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P4.11-01 | H-XW | Title `E2E-P4.11-01 Digest after a scripted day lists the counts, every grant, open findings, job last-runs, export lag and version counts`. Insert the scripted checkout, payment, grant, finding, parked work, open alert, job last-run, and `channel_version_seen` rows the digest lists. Run `runScheduled("0 6 * * *")`. One `send_email` message with subject `digest` contains those counts, every grant, the complimentary, adjustment, and transfer operator, reason, length, and allowance, the open finding, the job last-run times, the backend last pull, the export lag, and the version counts. |
| E2E-P4.11-02 | H-XW | Title `E2E-P4.11-02 A25/FM-17: issuer key not_after within 29 days → AL-14 daily`. Platform issuer key `not_after` is 29 days after the test clock. `runScheduled("0 6 * * *")` captures an `AL-14` email. Advance the clock one day and run the cron again. A second `AL-14` email is sent. |
| E2E-P4.11-03 | H-XW | Title `E2E-P4.11-03 FM-10: feed_consumer stale for 6 min → AL-15 hourly`. `feed_consumer.last_pull_at` is 6 minutes before the test clock. `runScheduled("0 * * * *")` captures an `AL-15` email. Advance one hour and run again. A second `AL-15` email is sent. |
| E2E-P4.11-04 | H-XW | Title `E2E-P4.11-04 AD-9: extra issuer kid and unannounced operator credential → AL-22`. An issuer `{kid, public_key}` from `listIssuerKeys` is absent from the pins. An active `{credential_id, public_key_cose, alg}` from `listOperatorCredentials` is absent from `seen_operator_credential`. `runScheduled("0 * * * *")` captures `AL-22` for the kid and for the credential. A triple already stored from an `ok` register `detail`, including one stored while `pending`, does not raise AL-22 when `listOperatorCredentials` later returns it as `active`. |
| E2E-P4.11-05 | H-XW | Title `E2E-P4.11-05 The ABO daily 06:00 UTC scheduled() cron (0 6 * * *) deletes 91-day-old done work rows and sent alerts; facts untouched`. Insert a `work` row with `state` `done` and `opened_at` 91 days ago, a sent `alert` with `last_sent_at` 91 days ago, and a commercial fact (`payment` or `fact_log`). `runScheduled("0 6 * * *")` deletes those two operational rows and leaves the fact. |
| E2E-P4.11-06 | H-XW | Title `E2E-P4.11-06 FM-19: wipe the ABO D1 → replay ledger/ → facts and status restored; gap re-inquired; a payment with no grant gets one → already_applied; reconciliation clean`. Export a scripted ledger, wipe D1 in the test, reapply the empty schema, and call `rebuildAbo` with one provider transaction reference that is not in the replayed ledger. Facts and `checkout_status` are restored. The gap inquiry records the payment. `grantIdPaid` is sent. The platform result is `already_applied`. `runReconciliation` leaves no open finding. `abo/REBUILD.md` states the operator step of copying those references from the provider dashboard export. |
| E2E-P4.11-07 | H-XW | Title `E2E-P4.11-07 Digest send failure retried; daily heartbeat ping sent`. The first digest `send_email` throws and the second succeeds. `runScheduled("0 6 * * *")` performs both sends. The captured heartbeat fetches include `HEARTBEAT_URL`. |

## Sequencing

Tests before implementation. Each new test is observed failing before the code that makes it pass.

1. Add the test file to `abo/vitest.cross-worker.config.ts` and add E2E-P4.11-01. The run fails because the daily cron does not send a digest.
2. Add E2E-P4.11-02. The run fails because AL-14 is not raised.
3. Add E2E-P4.11-03. The run fails because the hourly cron does not read `feedConsumerHealth`.
4. Add E2E-P4.11-04. The run fails because the hourly comparison does not raise AL-22.
5. Add E2E-P4.11-05. The run fails because the daily cron does not delete the 91-day rows.
6. Add E2E-P4.11-06. The run fails because `abo/src/rebuild.ts` is absent.
7. Add E2E-P4.11-07. The run fails because a thrown digest send is not retried and the daily cron does not ping `HEARTBEAT_URL`.
8. Add `abo/migrations/0009_digest_watch.sql`.
9. Extend `AlertCode` and the repeat intervals for AL-14 (daily), AL-15 (hourly), and AL-22 (hourly).
10. Stamp `scheduled_job_run` from each existing cron branch when the table exists. Record `channel_version_seen` from `checkContractVersion` for `aboClinic` and `aboConsole`. A missing table is ignored.
11. Implement `abo/src/digest/run.ts`. The digest subject is `digest`. The body is plain text and contains the FR-001 items: 24-hour counts of checkouts, payments by classification, grants by `source_kind`, reversals, and alerts; every grant; complimentary, adjustment, and transfer grants with operator, reason, length, and allowance taken from the stored grant envelope; open findings (`finding` with no `finding_resolution`); parked `work` and open `alert` rows; `scheduled_job_run.last_run_at` for each cron; `feedConsumerHealth.last_pull_at` as the backend's last pull; the existing R2 lock and export-lag status; keys with `not_after` after now and at most 30 days ahead; `channel_version_seen` received and `contract_version_unsupported` counts. In `emailsWithAl16`, require subject `AL-16`.
12. In that same daily function, call `listIssuerKeys` and `listServiceKeys`. A key whose `not_after` is after now and within 30 days raises AL-14 (`alert_key` `AL-14:<kid>`). Run this check before `sendDueAlerts` on the `0 6 * * *` branch so the email goes out in that run.
13. Implement `abo/src/housekeeping/run.ts`. Delete `work` where `state` is `done` and `opened_at` is older than 90 days. Delete `alert` where `last_sent_at` is older than 90 days. Delete R2 objects under `hmac-invalid/` whose day prefix is older than 30 days. Do not delete commercial fact tables or `fact_log`.
14. On `0 6 * * *`, after the existing lock check, reconciliation, alert send, and daily reversal population, run the digest, then the heartbeat fetch of `HEARTBEAT_URL`, then housekeeping. Digest send: call `SEND_EMAIL.send` once, and once more if that call throws. The heartbeat fetch runs after those attempts, including when both throw. Isolate each new step so a failure does not skip the steps already on this cron.
15. Implement AL-15 in `abo/src/watch/hourly.ts`. `last_pull_at` null or older than 5 minutes raises AL-15 (`alert_key` `AL-15:feed`). Send due alerts on that hourly run after the raise.
16. In that module, compare the `listIssuerKeys` set of `{kid, public_key}` with the exported pin loader. Any difference raises AL-22. Compare `listOperatorCredentials` with `seen_operator_credential`. An active triple that is absent raises AL-22 (`alert_key` `AL-22:credential:<credential_id>` for the credential, `AL-22:issuer:<kid>` for the kid). `rememberOperatorCredential` inserts the triple from an `ok` register `detail`. Call it from `abo/src/ops/index.ts`.
17. Call the hourly module from the `0 * * * *` branch after the existing signing-`kid` check and hourly reversal population. A failure there does not skip those existing steps.
18. Add `insertFactLog` and switch the existing fact inserts over to it. `exportFacts` writes `row` onto the ledger line when `row_json` is present.
19. Implement replay in `rebuildAbo`: read `ledger/<fact_seq>.ndjson` in `fact_seq` order, insert `row` into `table`, and insert `fact_log` with that `row_json`. Inserts are plain `INSERT`s. Then set `checkout_status` from the latest `checkout_event` (`opened` → `open`, `late_paid` → `paid_late`, otherwise the event kind) and call the existing `refreshCoverageView`. Record replayed sequences in `fact_export`.
20. Fill the gap. Re-inquire every rebuilt checkout with `provider.inquire({ checkout_id })` and every rebuilt payment with `provider.inquire({ payment_id })`. For each operator transaction reference, call `provider.inquire({ checkout_id, paymob_txn_id: reference })` on rebuilt checkouts that have a `paymob_intention` and no `payment`, and keep a bound result. A succeeded transaction with no `payment` row is recorded through the exported runner function and an open `grant` work row, then `runDueGrantWork`. `grant_id` is `grantIdPaid(payment_id)`. Call `listGrants` and treat a paid platform grant with no ABO payment as a further inquiry. End with `runReconciliation`.
21. Add `abo/scripts/rebuild-abo.ts` and `abo/REBUILD.md`. The runbook states §5.1 step 1 (Time Travel within 30 days) and, otherwise, the script: empty D1, replay, and the operator copying provider transaction references from the dashboard export into the script. The script passes those references to `rebuildAbo`.
22. Run the unit command and confirm E2E-P4.11-01 through E2E-P4.11-07 pass. Confirm the vitest path is that file only.
23. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded for this unit in 02 §7. Nothing to justify.
