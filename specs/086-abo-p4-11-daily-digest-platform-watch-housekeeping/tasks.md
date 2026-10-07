# Tasks: Daily digest, platform watch, housekeeping and ABO rebuild

**Input**: Design documents from `specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.10 (none; that unit row states no Outputs / freezes line; this unit calls `runReconciliation` and does not change it) and P3.9 (`feedConsumerHealth` on `VendorEntrypoint`, called over `PLATFORM` and not modified). Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is not a task: Spikes is none. `data-model.md` is not a task: spec §3.2 defines no entities. `contracts/` is not a task: Freezes is none. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id, written to fail before the behavior exists. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 27. Size M is 20–32 (rule S3). The count is the vitest include (1), one task per E2E id (7), one task per Files row other than that include and the seven-scenario test file (17), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §6.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/src/vendor/entrypoint.ts` — consumed through the `PLATFORM` binding (`listIssuerKeys`, `listOperatorCredentials`, `listServiceKeys`, `feedConsumerHealth`, `listGrants`) and not modified
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Spec Kit artifacts**: `specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/`
- Codebase is `abo`. One worker. No second codebase. `abo/src/reconciliation/run.ts` changes only its `fact_log` insert. The HTTP feed contract and the `/v1/coverage` response are not called and not modified

---

## 3. Setup

**Purpose**: Sequencing step 1, the include the failing tests need. The `abo/` Worker already exists. The test file is created in §4.

### 3.1 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — vitest include

**Independent Test**: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 in harness H-XW.

- [X] T001 [US1] Add the digest-watch-rebuild test include in `abo/vitest.cross-worker.config.ts` — produces the H-XW include for this unit, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, E2E-P4.11-06, E2E-P4.11-07. Depends on nothing. Add `test/system/digest-watch-rebuild.cross-worker.test.ts` to the H-XW `include` list. The unit command still names only that file. Leave `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` uncreated. Leave `abo/src/digest/run.ts`, `abo/src/watch/hourly.ts`, `abo/src/housekeeping/run.ts`, and `abo/src/rebuild.ts` uncreated.

**Checkpoint**: The include lists `test/system/digest-watch-rebuild.cross-worker.test.ts`. That file does not exist yet.

---

## 4. Tests

**Purpose**: Sequencing steps 1–7. One failing test per E2E id, all in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`. Titles are prefixed with the E2E id. Harness H-XW. Entry is `runScheduled` from `abo/test/system/harness.ts`, except E2E-P4.11-06, which imports `abo/src/rebuild.ts` and calls it in-process. The test wipes D1 for that scenario. `send_email` and the heartbeat fetch are the existing captures (rule V6). No local scenario sleeps more than 2 s (rule V4). Clock moves use the existing test clock. The file applies `abo/migrations/0009_digest_watch.sql` and the earlier ABO migrations it needs. Do not create that migration in this phase.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/digest-watch-rebuild.cross-worker.test.ts
```

### 4.1 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — tests

**Independent Test**: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 in harness H-XW.

- [X] T002 [US1] Add the failing test `E2E-P4.11-01` in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` — red test, FR-001, E2E-P4.11-01. Depends on T001. Create the file and the shared setup. Title `E2E-P4.11-01 Digest after a scripted day lists the counts, every grant, open findings, job last-runs, export lag and version counts`. Insert the scripted checkout, payment, grant, finding, parked work, open alert, job last-run, and `channel_version_seen` rows the digest lists. Run `runScheduled("0 6 * * *")`. One `send_email` message with subject `digest` contains those counts, every grant, the complimentary, adjustment, and transfer operator, reason, length, and allowance, the open finding, the job last-run times, the backend last pull, the export lag, and the version counts. The digest is one body. Do not require a separate machine-readable schema. The command fails because the daily cron does not send a digest.

- [X] T003 [US1] Add the failing test `E2E-P4.11-02` in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` — red test, FR-002, E2E-P4.11-02. Depends on T002 (same file). Title `E2E-P4.11-02 A25/FM-17: issuer key not_after within 29 days → AL-14 daily`. Platform issuer key `not_after` is 29 days after the test clock. `runScheduled("0 6 * * *")` captures an `AL-14` email. Advance the clock one day and run the cron again. A second `AL-14` email is sent. The command fails because AL-14 is not raised.

- [X] T004 [US1] Add the failing test `E2E-P4.11-05` in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` — red test, FR-005, E2E-P4.11-05. Depends on T003 (same file). Title `E2E-P4.11-05 The ABO daily 06:00 UTC scheduled() cron (0 6 * * *) deletes 91-day-old done work rows and sent alerts; facts untouched`. Insert a `work` row with `state` `done` and `opened_at` 91 days ago, a sent `alert` with `last_sent_at` 91 days ago, and a commercial fact (`payment` or `fact_log`). `runScheduled("0 6 * * *")` deletes those two operational rows and leaves the fact. The command fails because the daily cron does not delete the 91-day rows.

- [X] T005 [US1] Add the failing test `E2E-P4.11-07` in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` — red test, FR-007, E2E-P4.11-07. Depends on T004 (same file). Title `E2E-P4.11-07 Digest send failure retried; daily heartbeat ping sent`. The first digest `send_email` throws and the second succeeds. `runScheduled("0 6 * * *")` performs both sends. The captured heartbeat fetches include `HEARTBEAT_URL`. The command fails because a thrown digest send is not retried and the daily cron does not ping `HEARTBEAT_URL`.

**Checkpoint**: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 exist and fail.

### 4.2 User Story 2 - Hourly platform watch (Priority: P2) — tests

**Independent Test**: E2E-P4.11-03 and E2E-P4.11-04 in harness H-XW.

- [X] T006 [US2] Add the failing test `E2E-P4.11-03` in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` — red test, FR-003, E2E-P4.11-03. Depends on T005 (same file). Title `E2E-P4.11-03 FM-10: feed_consumer stale for 6 min → AL-15 hourly`. `feed_consumer.last_pull_at` is 6 minutes before the test clock. `runScheduled("0 * * * *")` captures an `AL-15` email. Advance one hour and run again. A second `AL-15` email is sent. The command fails because the hourly cron does not read `feedConsumerHealth`.

- [X] T007 [US2] Add the failing test `E2E-P4.11-04` in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` — red test, FR-004, E2E-P4.11-04. Depends on T006 (same file). Title `E2E-P4.11-04 AD-9: extra issuer kid and unannounced operator credential → AL-22`. An issuer `{kid, public_key}` from `listIssuerKeys` is absent from the pins. An active `{credential_id, public_key_cose, alg}` from `listOperatorCredentials` is absent from `seen_operator_credential`. `runScheduled("0 * * * *")` captures `AL-22` for the kid and for the credential. A triple already stored from an `ok` register `detail`, including one stored while `pending`, does not raise AL-22 when `listOperatorCredentials` later returns it as `active`. The command fails because the hourly comparison does not raise AL-22.

**Checkpoint**: E2E-P4.11-03 and E2E-P4.11-04 exist and fail. E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 still fail.

### 4.3 User Story 3 - ABO rebuild from the ledger (Priority: P3) — tests

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

- [X] T008 [US3] Add the failing test `E2E-P4.11-06` in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` — red test, FR-006, E2E-P4.11-06. Depends on T007 (same file). Title `E2E-P4.11-06 FM-19: wipe the ABO D1 → replay ledger/ → facts and status restored; gap re-inquired; a payment with no grant gets one → already_applied; reconciliation clean`. Export a scripted ledger, wipe D1 in the test, reapply the empty schema, and call `rebuildAbo` with one provider transaction reference that is not in the replayed ledger. Facts and `checkout_status` are restored. The gap inquiry records the payment. `grantIdPaid` is sent. The platform result is `already_applied`. `runReconciliation` leaves no open finding. `abo/REBUILD.md` states the operator step of copying those references from the provider dashboard export. The H-XW test imports `abo/src/rebuild.ts` and calls it in-process. Wiping D1 stays the test's setup. The command fails because `abo/src/rebuild.ts` is absent.

**Checkpoint**: E2E-P4.11-06 exists and fails. E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still fail.

---

## 5. Implementation

**Purpose**: Sequencing steps 8–21. Starts after T002–T008 exist and those E2E tests fail. Within a subphase the tasks run in id order.

### 5.1 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — schema, alerts, digest

**Independent Test**: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 in harness H-XW.

- [X] T009 [US1] Add migration `abo/migrations/0009_digest_watch.sql` — produces `scheduled_job_run`, `seen_operator_credential`, `channel_version_seen`, and `fact_log.row_json`, FR-001, FR-004, FR-006, E2E-P4.11-01, E2E-P4.11-04, E2E-P4.11-06. Depends on T008. Create `scheduled_job_run (job TEXT PRIMARY KEY, last_run_at TEXT NOT NULL)`, `seen_operator_credential (credential_id TEXT NOT NULL, public_key_cose TEXT NOT NULL, alg TEXT NOT NULL, PRIMARY KEY (credential_id, public_key_cose, alg))`, and `channel_version_seen (channel TEXT NOT NULL, contract_version INTEGER NOT NULL, received INTEGER NOT NULL, unsupported INTEGER NOT NULL, PRIMARY KEY (channel, contract_version))`. `ALTER TABLE fact_log ADD COLUMN row_json TEXT`. Leave the digest, watch, housekeeping, and rebuild modules uncreated.

**Checkpoint**: The three tables and `fact_log.row_json` exist. E2E-P4.11-01 through E2E-P4.11-07 still fail.

- [X] T010 [US1] Add `AL-14`, `AL-15`, and `AL-22` in `abo/src/alert/index.ts` — produces the three alert codes and their repeat intervals, FR-002, FR-003, FR-004, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04. Depends on T009. Add `AL-14`, `AL-15`, and `AL-22` to `AlertCode`. AL-14 repeats daily. AL-15 and AL-22 repeat hourly. Leave `abo/src/digest/run.ts` and `abo/src/watch/hourly.ts` uncreated.

**Checkpoint**: `AlertCode` includes `AL-14`, `AL-15`, and `AL-22`. E2E-P4.11-01 through E2E-P4.11-07 still fail.

- [X] T011 [US1] Record `channel_version_seen` in `abo/src/clinic-api/version.ts` — produces the version-gate writer, FR-001, E2E-P4.11-01. Depends on T010. On each `aboClinic` or `aboConsole` decision, increment `channel_version_seen`. A missing table is ignored. Per-channel version counts stay limited to the channels the ABO observes, `aboClinic` and `aboConsole`. Leave `abo/src/digest/run.ts` uncreated.

**Checkpoint**: `checkContractVersion` updates `channel_version_seen` for `aboClinic` and `aboConsole`. E2E-P4.11-01 through E2E-P4.11-07 still fail.

- [X] T012 [US1] Implement the daily digest and AL-14 in `abo/src/digest/run.ts` — produces the digest body, the `channel_version_seen` read, AL-14, and one digest-send retry, FR-001, FR-002, FR-007, E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-07. Depends on T011. The digest subject is `digest`. The body is plain text and is one `send_email` body. It contains the 24-hour counts of checkouts, payments by classification, grants by `source_kind`, reversals, and alerts; every grant; complimentary, adjustment, and transfer grants with operator, reason, length, and allowance taken from the stored grant envelope; open findings (`finding` with no `finding_resolution`); parked `work` and open `alert` rows; `scheduled_job_run.last_run_at` for each cron; `feedConsumerHealth.last_pull_at` as the backend's last pull; the existing R2 lock and export-lag status; keys with `not_after` after now and at most 30 days ahead; `channel_version_seen` received and `contract_version_unsupported` counts. Call `listIssuerKeys` and `listServiceKeys`. A key whose `not_after` is after now and within 30 days raises AL-14 (`alert_key` `AL-14:<kid>`). Digest send calls `SEND_EMAIL.send` once, and once more if that call throws. Leave `abo/src/worker.ts` without the digest call, the heartbeat fetch, and the housekeeping call in this task.

**Checkpoint**: `abo/src/digest/run.ts` builds the digest and raises AL-14. `scheduled()` does not call it yet. E2E-P4.11-01, E2E-P4.11-02, and E2E-P4.11-07 still fail.

- [X] T013 [US1] Require subject `AL-16` in `emailsWithAl16` in `abo/test/system/catalogue.system.test.ts` — produces the catalogue filter so a digest that quotes an open AL-16 does not change the E2E-P4.1-08 count, FR-001, E2E-P4.11-01. Depends on T012. The digest subject is `digest`. Match subject `AL-16`. Do not add an E2E id.

**Checkpoint**: `emailsWithAl16` matches subject `AL-16`. E2E-P4.11-01 through E2E-P4.11-07 still fail.

### 5.2 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — housekeeping

**Independent Test**: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 in harness H-XW.

- [X] T014 [US1] Implement retention deletes in `abo/src/housekeeping/run.ts` — produces the housekeeping module, FR-005, E2E-P4.11-05. Depends on T013. Delete `work` where `state` is `done` and `opened_at` is older than 90 days. Delete `alert` where `last_sent_at` is older than 90 days. Delete R2 objects under `hmac-invalid/` whose day prefix is older than 30 days. Do not delete commercial fact tables or `fact_log`. Leave `abo/src/worker.ts` without the housekeeping call in this task.

**Checkpoint**: `abo/src/housekeeping/run.ts` deletes those operational rows and leaves facts. `scheduled()` does not call it yet. E2E-P4.11-05 still fails.

### 5.3 User Story 2 - Hourly platform watch (Priority: P2) — hourly watch

**Independent Test**: E2E-P4.11-03 and E2E-P4.11-04 in harness H-XW.

- [X] T015 [US2] Export the issuer pin loader in `abo/src/clinic-api/auth.ts` — produces the `{kid, public_key}` set the hourly comparison uses, FR-004, E2E-P4.11-04. Depends on T014. Export the existing pin loader. The hourly comparison uses that same set, including the `harness_issuer_pin` rows billing auth already prefers when `TEST_CLOCK === "1"`. Leave `abo/src/watch/hourly.ts` uncreated.

**Checkpoint**: The pin loader is exported from `abo/src/clinic-api/auth.ts`. E2E-P4.11-03 and E2E-P4.11-04 still fail.

- [X] T016 [US2] Implement AL-15 and AL-22 in `abo/src/watch/hourly.ts` — produces the hourly checks and `rememberOperatorCredential`, FR-003, FR-004, E2E-P4.11-03, E2E-P4.11-04. Depends on T015. `last_pull_at` null or older than 5 minutes raises AL-15 (`alert_key` `AL-15:feed`). Send due alerts on that hourly run after the raise. Compare the `listIssuerKeys` set of `{kid, public_key}` with the exported pin loader. Any difference raises AL-22 (`alert_key` `AL-22:issuer:<kid>`). `status` and the validity times are not a pin mismatch. Compare `listOperatorCredentials` with `seen_operator_credential`. An active triple that is absent raises AL-22 (`alert_key` `AL-22:credential:<credential_id>`). `rememberOperatorCredential` inserts the triple `{credential_id, public_key_cose, alg}`. Leave `abo/src/ops/index.ts` and `abo/src/worker.ts` without the new calls in this task.

**Checkpoint**: `abo/src/watch/hourly.ts` raises AL-15 and AL-22 and exports `rememberOperatorCredential`. `scheduled()` does not call it yet. E2E-P4.11-03 and E2E-P4.11-04 still fail.

- [X] T017 [US2] Remember operator credentials in `abo/src/ops/index.ts` — produces the last-seen list from the ABO's own register result, FR-004, E2E-P4.11-04. Depends on T016. After an `ok` `registerOperatorCredential` result, including bootstrap, call `rememberOperatorCredential` with `{credential_id, public_key_cose, alg}` from `detail`. A `pending` row is stored then. A credential stored while `pending` is not a new appearance when it later becomes `active`. Do not switch `fact_log` inserts in this task. Leave the `0 * * * *` branch in `abo/src/worker.ts` without the hourly module call.

**Checkpoint**: An `ok` register `detail` is stored in `seen_operator_credential`. E2E-P4.11-04 still fails until `scheduled()` runs the comparison.

### 5.4 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — scheduled entry

**Independent Test**: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 in harness H-XW.

- [X] T018 [US1] Wire the daily and hourly modules from `scheduled()` in `abo/src/worker.ts` — produces the live cron entry, the `feedConsumerHealth` binding type, job stamps, and the daily heartbeat, FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, E2E-P4.11-07. Depends on T014, T016, and T017. Add `PLATFORM.feedConsumerHealth` on `Env`. Each cron stamps `scheduled_job_run` when the table exists. On `0 6 * * *`, after the existing lock check, reconciliation, and daily reversal population, call the digest function before `sendDueAlerts` so the AL-14 raise is already stored and `sendDueAlerts` sends that email in the same run. The digest function performs the digest `SEND_EMAIL` (once, and once more if that call throws). After those attempts, including when both throw, fetch `HEARTBEAT_URL`, then run housekeeping. On `0 * * * *`, call the hourly module after the existing signing-`kid` check and hourly reversal population. Isolate each new step so a failure does not skip the steps already on that cron. Leave `abo/src/rebuild.ts` uncreated.

**Checkpoint**: `runScheduled("0 6 * * *")` reaches the digest, the heartbeat, and housekeeping. `runScheduled("0 * * * *")` reaches the hourly watch. E2E-P4.11-06 still fails.

### 5.5 User Story 3 - ABO rebuild from the ledger (Priority: P3) — fact log row_json

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

- [X] T019 [US3] Add `insertFactLog` in `abo/src/records/append.ts` — produces the fact insert that stores `row_json`, FR-006, E2E-P4.11-06. Depends on T018. `insertFactLog` writes `row_json` as the canonical JSON whose SHA-256 is `row_sha256`. Leave the existing `INSERT INTO fact_log` call sites unchanged in this task. Leave `abo/src/records/export.ts` unchanged in this task.

**Checkpoint**: `insertFactLog` writes `row_json`. Existing call sites still use their current inserts. E2E-P4.11-06 still fails.

### 5.6 User Story 3 - ABO rebuild from the ledger (Priority: P3) — ledger export row

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

- [X] T020 [US3] Add `row` to the ledger line in `abo/src/records/export.ts` — produces the replayable ledger object, FR-006, E2E-P4.11-06. Depends on T018. The `ledger/<fact_seq>.ndjson` line keeps `fact_seq`, `table`, `key`, and `row_sha256`, and adds `row` from `row_json` when present. Still one JSON line. Still no payer `name`, `email`, or `phone`. Leave `abo/src/records/append.ts` unchanged in this task.

**Checkpoint**: Exported ledger lines include `row` when `row_json` is present. E2E-P4.11-06 still fails.

### 5.7 User Story 3 - ABO rebuild from the ledger (Priority: P3) — replay

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

- [ ] T021 [US3] Switch fact inserts to `insertFactLog` in `abo/src/clinic-api/checkouts.ts`, `abo/src/work/runner.ts`, `abo/src/work/grant.ts`, `abo/src/work/reversal.ts`, `abo/src/ops/index.ts`, and `abo/src/reconciliation/run.ts` — produces one fact-log writer, FR-006, E2E-P4.11-06. Depends on T017 and T019. Existing `INSERT INTO fact_log` statements in those files go through `insertFactLog`. `abo/src/reconciliation/run.ts` changes only that insert. Keep the `rememberOperatorCredential` call from T017. Do not export the paid-confirmation recording in this task. Leave `abo/src/rebuild.ts` uncreated.

**Checkpoint**: Those six files insert facts through `insertFactLog`. E2E-P4.11-06 still fails.

- [ ] T022 [US3] Export paid-confirmation recording in `abo/src/work/runner.ts` — produces the function rebuild uses for a payment inquiry finds, FR-006, E2E-P4.11-06. Depends on T021. Export the existing paid-confirmation recording so rebuild can record a payment that inquiry finds and that `payment` does not yet contain. Keep the `insertFactLog` switch from T021. Leave `abo/src/rebuild.ts` uncreated.

**Checkpoint**: The paid-confirmation recording is exported from `abo/src/work/runner.ts`. E2E-P4.11-06 still fails.

- [ ] T023 [US3] Implement `rebuildAbo` in `abo/src/rebuild.ts` — produces ledger replay, gap inquiry, `listGrants` comparison, and the closing reconciliation, FR-006, E2E-P4.11-06. Depends on T020 and T022. Read `ledger/<fact_seq>.ndjson` in `fact_seq` order, insert `row` into `table`, and insert `fact_log` with that `row_json`. Inserts are plain `INSERT`s. Then set `checkout_status` from the latest `checkout_event` (`opened` → `open`, `late_paid` → `paid_late`, otherwise the event kind) and call the existing `refreshCoverageView`. Record replayed sequences in `fact_export`. Re-inquire every rebuilt checkout with `provider.inquire({ checkout_id })` and every rebuilt payment with `provider.inquire({ payment_id })`. For each operator transaction reference, call `provider.inquire({ checkout_id, paymob_txn_id: reference })` on rebuilt checkouts that have a `paymob_intention` and no `payment`, and keep a bound result. A succeeded transaction with no `payment` row is recorded through the exported runner function and an open `grant` work row, then `runDueGrantWork`. `grant_id` is `grantIdPaid(payment_id)`. Call `listGrants` and treat a paid platform grant with no ABO payment as a further inquiry. End with `runReconciliation`. The provider stays behind `providerForId`. Leave `abo/scripts/rebuild-abo.ts` and `abo/REBUILD.md` uncreated.

**Checkpoint**: `rebuildAbo` replays `ledger/`, fills the gap, and ends on `runReconciliation`. The operator script and runbook do not exist yet.

### 5.8 User Story 3 - ABO rebuild from the ledger (Priority: P3) — operator script

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

- [ ] T024 [US3] Add the operator wrapper in `abo/scripts/rebuild-abo.ts` — produces the script that passes provider transaction references to `rebuildAbo`, FR-006, E2E-P4.11-06. Depends on T023. Import `rebuildAbo`. The script accepts the provider transaction references the operator copies from the dashboard export and passes those references to `rebuildAbo`. No new export schema. Leave `abo/REBUILD.md` uncreated in this task.

**Checkpoint**: `abo/scripts/rebuild-abo.ts` calls `rebuildAbo` with the operator's references. E2E-P4.11-06 still fails the runbook assertion until `abo/REBUILD.md` exists.

### 5.9 User Story 3 - ABO rebuild from the ledger (Priority: P3) — runbook

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

- [ ] T025 [US3] Add the runbook in `abo/REBUILD.md` — produces the operator steps for §5.1, FR-006, E2E-P4.11-06. Depends on T023. State §5.1 step 1 (Time Travel within 30 days) and, otherwise, the script: empty D1, replay, and the operator copying provider transaction references from the dashboard export into the script. Leave `abo/scripts/rebuild-abo.ts` unchanged in this task.

**Checkpoint**: `abo/REBUILD.md` states the operator step of copying provider transaction references from the dashboard export.

---

## 6. Verification

**Purpose**: Sequencing step 22. After T009 through T025, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command (rule S2).

### 6.1 Unit harness

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

- [ ] T026 [US3] Run `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/digest-watch-rebuild.cross-worker.test.ts` from `abo/` until E2E-P4.11-01 through E2E-P4.11-07 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, E2E-P4.11-06, E2E-P4.11-07. Depends on T025 (and therefore on T001–T024). Confirm the vitest path is that file only. This task may edit only `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`. It does not add an E2E id.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/digest-watch-rebuild.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.11-01 through E2E-P4.11-07 pass.

---

## 7. Documentation

**Purpose**: Sequencing step 23. After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task. `abo/REBUILD.md` is T025, not this phase.

### 7.1 Quickstart

- [ ] T027 [US3] Create `specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, E2E-P4.11-06, E2E-P4.11-07. Depends on T026. Sections: (1) what was implemented — daily digest, AL-14, AL-15, AL-22, housekeeping, the daily heartbeat ping, and the ABO rebuild module, operator script, and runbook; (2) files added or modified — the Files section of `plan.md`; (3) the harness command below; (4) the entry point → module chain per E2E id below. Manual steps: none. The harness can see every behaviour in the test plan.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/digest-watch-rebuild.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.11-01 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `SEND_EMAIL` |
| E2E-P4.11-02 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `PLATFORM.listIssuerKeys` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-03 | `runScheduled("0 * * * *")` → `scheduled()` → `abo/src/watch/hourly.ts` → `PLATFORM.feedConsumerHealth` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-04 | `runScheduled("0 * * * *")` → `scheduled()` → `abo/src/watch/hourly.ts` → `PLATFORM.listIssuerKeys` and `PLATFORM.listOperatorCredentials` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-05 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/housekeeping/run.ts` |
| E2E-P4.11-06 | H-XW test imports `abo/src/rebuild.ts` → R2 `ledger/` → D1 inserts → `providerForId` inquire → `PLATFORM.listGrants` → `abo/src/work/grant.ts` → `runReconciliation` |
| E2E-P4.11-07 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `SEND_EMAIL` (retry) → outbound fetch of `HEARTBEAT_URL` |

**Checkpoint**: `quickstart.md` names the files, the harness command, and the seven chains.

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (§3)**: No dependencies. The vitest include only. The test file stays uncreated.
- **Tests (§4)**: Depend on the vitest include. One failing test per E2E id, User Story 1 then User Story 2 then User Story 3: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, E2E-P4.11-07, then E2E-P4.11-03, E2E-P4.11-04, then E2E-P4.11-06. All of them fail before the digest, watch, housekeeping, and rebuild modules are implemented.
- **Implementation (§5)**: Depends on the seven failing tests. Order is the plan Sequencing: migration, alert codes, `channel_version_seen`, digest and AL-14, the `emailsWithAl16` subject filter, housekeeping, the pin loader, the hourly module, `rememberOperatorCredential`, the `scheduled()` branches, `insertFactLog` and the ledger `row`, the fact-insert switch, the paid-confirmation export, `rebuildAbo`, then the operator script and the runbook.
- **Verification (§6)**: Depends on T025. The unit harness command only.
- **Documentation (§7)**: Depends on the harness being green.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: Daily digest, key expiry, housekeeping, and heartbeat. E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07. One `scheduled()` run on `0 6 * * *`.
- **User Story 2 (P2)**: Hourly platform watch. E2E-P4.11-03 and E2E-P4.11-04. Starts after the User Story 1 tests exist in the same file. The hourly module is called from the existing `0 * * * *` branch after that branch's current steps.
- **User Story 3 (P3)**: ABO rebuild from the ledger. E2E-P4.11-06. Starts after the User Story 1 and User Story 2 tests exist in the same file. `rebuildAbo` ends with `runReconciliation`.

### 8.3 Within Each Phase

- T001 writes only `abo/vitest.cross-worker.config.ts` and leaves the test file uncreated.
- T002 creates `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` after T001. T003 through T008 all write that same file, in that id order.
- T009 writes only `abo/migrations/0009_digest_watch.sql` after T008.
- T010 writes only `abo/src/alert/index.ts` after T009.
- T011 writes only `abo/src/clinic-api/version.ts` after T010.
- T012 writes only `abo/src/digest/run.ts` after T011.
- T013 writes only `abo/test/system/catalogue.system.test.ts` after T012.
- T014 writes only `abo/src/housekeeping/run.ts` after T013.
- T015 writes only `abo/src/clinic-api/auth.ts` after T014.
- T016 writes only `abo/src/watch/hourly.ts` after T015.
- T017 writes only the `rememberOperatorCredential` call in `abo/src/ops/index.ts` after T016.
- T018 writes only `abo/src/worker.ts` after T014, T016, and T017.
- T019 writes only `abo/src/records/append.ts` after T018.
- T020 writes only `abo/src/records/export.ts` after T018. It does not edit `abo/src/records/append.ts`.
- T021 writes `abo/src/clinic-api/checkouts.ts`, `abo/src/work/runner.ts`, `abo/src/work/grant.ts`, `abo/src/work/reversal.ts`, `abo/src/ops/index.ts`, and `abo/src/reconciliation/run.ts` after T019. It keeps the T017 call.
- T022 writes only the paid-confirmation export in `abo/src/work/runner.ts` after T021.
- T023 writes only `abo/src/rebuild.ts` after T020 and T022.
- T024 writes only `abo/scripts/rebuild-abo.ts` after T023.
- T025 writes only `abo/REBUILD.md` after T023. It does not edit `abo/scripts/rebuild-abo.ts`.
- T026 runs after T025 and may edit only `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`.
- T027 writes only `specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/quickstart.md` after T026 is green.

---

## 9. Implementation Waves

### 9.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — vitest include` — paths: `abo/vitest.cross-worker.config.ts`

### 9.2 Wave 2

- T002–T005 [US1] — subphase: `### 4.1 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — tests` — paths: `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`

### 9.3 Wave 3

- T006–T007 [US2] — subphase: `### 4.2 User Story 2 - Hourly platform watch (Priority: P2) — tests` — paths: `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`

### 9.4 Wave 4

- T008 [US3] — subphase: `### 4.3 User Story 3 - ABO rebuild from the ledger (Priority: P3) — tests` — paths: `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`

### 9.5 Wave 5

- T009–T013 [US1] — subphase: `### 5.1 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — schema, alerts, digest` — paths: `abo/migrations/0009_digest_watch.sql`, `abo/src/alert/index.ts`, `abo/src/clinic-api/version.ts`, `abo/src/digest/run.ts`, `abo/test/system/catalogue.system.test.ts`

### 9.6 Wave 6

- T014 [US1] — subphase: `### 5.2 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — housekeeping` — paths: `abo/src/housekeeping/run.ts`

### 9.7 Wave 7

- T015–T017 [US2] — subphase: `### 5.3 User Story 2 - Hourly platform watch (Priority: P2) — hourly watch` — paths: `abo/src/clinic-api/auth.ts`, `abo/src/watch/hourly.ts`, `abo/src/ops/index.ts`

### 9.8 Wave 8

- T018 [US1] — subphase: `### 5.4 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1) — scheduled entry` — paths: `abo/src/worker.ts`

### 9.9 Wave 9

- T019 [US3] — subphase: `### 5.5 User Story 3 - ABO rebuild from the ledger (Priority: P3) — fact log row_json` — paths: `abo/src/records/append.ts`
- T020 [US3] — subphase: `### 5.6 User Story 3 - ABO rebuild from the ledger (Priority: P3) — ledger export row` — paths: `abo/src/records/export.ts`

### 9.10 Wave 10

- T021–T023 [US3] — subphase: `### 5.7 User Story 3 - ABO rebuild from the ledger (Priority: P3) — replay` — paths: `abo/src/clinic-api/checkouts.ts`, `abo/src/work/runner.ts`, `abo/src/work/grant.ts`, `abo/src/work/reversal.ts`, `abo/src/ops/index.ts`, `abo/src/reconciliation/run.ts`, `abo/src/rebuild.ts`

### 9.11 Wave 11

- T024 [US3] — subphase: `### 5.8 User Story 3 - ABO rebuild from the ledger (Priority: P3) — operator script` — paths: `abo/scripts/rebuild-abo.ts`
- T025 [US3] — subphase: `### 5.9 User Story 3 - ABO rebuild from the ledger (Priority: P3) — runbook` — paths: `abo/REBUILD.md`

### 9.12 Wave 12

- T026 [US3] — subphase: `### 6.1 Unit harness` — paths: `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`

### 9.13 Wave 13

- T027 [US3] — subphase: `### 7.1 Quickstart` — paths: `specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/quickstart.md`
