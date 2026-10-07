# Feature Specification: Daily digest, platform watch, housekeeping and ABO rebuild

**Feature Branch**: `ai/086-abo-p4-11-daily-digest-platform-watch-housekeeping`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P4.11 — Daily digest, platform watch, housekeeping and ABO rebuild

## 1. Unit Contract

**Implements** — Read: 05 §3.4; 05 §1 (ABO hourly and daily rows); 05 §2 rows AL-14, AL-15, AL-22; 05 §5.1; 03 §8 (rows: completed work rows, invalid-HMAC samples); 04 §1.3 rows `listIssuerKeys`, `listOperatorCredentials`, `feedConsumerHealth`; 02 §4.2 row AD-9 ("Noticed by" column).

- Daily digest (24 h counts, every grant with operator/reason/length/allowance, open findings, parked work and alerts, last run of each job including the backend's last pull, R2 lock + export lag, keys expiring in 30 days, per-channel version counts for the channels the ABO observes).
- AL-14 (issuer keys via `listIssuerKeys` validity, ABO service keys).
- AL-15 (`feedConsumerHealth` > 5 min).
- AL-22 (hourly: issuer keys vs `ISSUER_KEYS`, credentials vs the AL-13-announced list).
- Housekeeping on the ABO daily 06:00 UTC `scheduled()` cron `0 6 * * *` (done work rows and sent alerts older than 90 days; invalid-HMAC samples older than 30 days; commercial facts not deleted).
- Daily heartbeat ping.
- ABO rebuild procedure (replay `ledger/` into an empty D1, recompute status, re-inquire the gap, compare with `listGrants`) as a script + runbook.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P4.10: None. The unit row states no Outputs / freezes line. P3.9: the HTTP feed contract; `/v1/coverage` response; `feedConsumerHealth`.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-07

- Q: Where do the rebuild procedure and its runbook live, and how does H-XW run them? → A: The procedure is `abo/src/rebuild.ts`. The H-XW test imports that module and calls it in-process; wiping D1 stays the test's setup. `abo/scripts/rebuild-abo.ts` is the operator wrapper and `abo/REBUILD.md` is the runbook. Both use the same module. `[implementation choice — no §citation]`
- Q: How does the digest test build a scripted day, and what body shape does the test require? → A: E2E-P4.11-01 inserts the scripted rows the digest lists, then runs the daily cron. The digest is one `send_email` body. The test asserts that the scripted counts, grants, findings, job last-runs, export lag, and version counts are present in that body. It does not require a separate machine-readable schema. `[implementation choice — no §citation]`
- Q: How does the rebuild script take the provider dashboard export for the gap window? → A: The script accepts the provider transaction references the operator copies from that export and re-inquires each one through the existing inquiry path. The runbook states that operator step. E2E-P4.11-06 passes one reference that is not in the replayed ledger. No new export schema is introduced. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Daily digest, key expiry, housekeeping, and heartbeat (Priority: P1)

The operator's daily 06:00 UTC run sends the digest, raises AL-14 when a key is inside 30 days of `not_after`, deletes operational rows past their retention, and pings the heartbeat URL. The digest proves the jobs are alive and lists every grant.

**Why this priority**: The digest, the key-expiry check, housekeeping, and the daily heartbeat are one `scheduled()` run. Platform watch and the rebuild procedure run on other entries.

**Independent Test**: E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-05, and E2E-P4.11-07 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** a scripted day, **When** the daily digest is sent, **Then** it lists the counts, every grant, open findings, job last-runs, export lag, and version counts. (E2E-P4.11-01, NFR-04, SR-23)
2. **Given** an issuer key whose `not_after` is within 29 days, **When** the daily key-expiry check runs, **Then** AL-14 is raised daily. (E2E-P4.11-02, A25, FM-17)
3. **Given** done work rows and sent alerts that are 91 days old, **When** housekeeping runs on the daily 06:00 UTC cron, **Then** those rows are deleted and facts are untouched. (E2E-P4.11-05)
4. **Given** the digest send fails, **When** the daily run sends the digest and the heartbeat ping, **Then** the digest send is retried and the daily heartbeat ping is sent. (E2E-P4.11-07)

### 2.2 User Story 2 - Hourly platform watch (Priority: P2)

The hourly run calls `feedConsumerHealth` and compares the platform's issuer keys and operator credentials with the ABO's pins and the AL-13-announced list. A feed pull older than 5 minutes raises AL-15. An issuer key or credential the ABO does not already pin or remember from AL-13 raises AL-22.

**Why this priority**: User Story 1 is the daily run. This story is the hourly watch named by AL-15, AL-22, and AD-9.

**Independent Test**: E2E-P4.11-03 and E2E-P4.11-04 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** `feed_consumer` stale for 6 minutes, **When** the hourly run reads `feedConsumerHealth`, **Then** AL-15 is raised hourly. (E2E-P4.11-03, FM-10)
2. **Given** an extra issuer `kid` on the platform that is not in the pins, **When** the hourly comparison runs, **Then** AL-22 is raised. **Given** an operator credential the ABO has not seen announced by AL-13, **When** the hourly comparison runs, **Then** AL-22 is raised. (E2E-P4.11-04, AD-9)

### 2.3 User Story 3 - ABO rebuild from the ledger (Priority: P3)

After ABO data loss, the operator follows the rebuild procedure. The script replays `ledger/` into an empty D1, recomputes status, re-inquires the gap, and compares with `listGrants`. A payment that has no grant receives one, and the platform answers `already_applied`. The procedure ends with a clean reconciliation run.

**Why this priority**: The daily and hourly runs are in place. This story is the FM-19 recovery procedure.

**Independent Test**: E2E-P4.11-06 in harness H-XW. Earlier suites stay green, and E2E-P4.11-01, E2E-P4.11-02, E2E-P4.11-03, E2E-P4.11-04, E2E-P4.11-05, and E2E-P4.11-07 still pass.

**Acceptance Scenarios**:

1. **Given** the ABO D1 is wiped, **When** the rebuild script replays `ledger/`, **Then** facts and status are restored, the gap is re-inquired, a payment with no grant gets one, the platform answers `already_applied`, and reconciliation is clean. (E2E-P4.11-06, FM-19, RC-04)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.11-01 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` on the ABO worker (`abo/src/worker.ts`); the digest is captured from `send_email` (rule V6) | Digest after a scripted day lists the counts, every grant, open findings, job last-runs, export lag and version counts [NFR-04, SR-23] | FR-001 | User Story 1 |
| E2E-P4.11-02 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` calls `VendorEntrypoint.listIssuerKeys` over the `PLATFORM` binding (`ai-platform/src/vendor/entrypoint.ts`); AL-14 is captured from `send_email` (rule V6) | A25/FM-17: issuer key `not_after` within 29 days → AL-14 daily | FR-002 | User Story 1 |
| E2E-P4.11-03 | H-XW | `runScheduled("0 * * * *")` → `scheduled()` calls `VendorEntrypoint.feedConsumerHealth` over the `PLATFORM` binding (`ai-platform/src/vendor/entrypoint.ts`); AL-15 is captured from `send_email` (rule V6) | FM-10: `feed_consumer` stale for 6 min → AL-15 hourly | FR-003 | User Story 2 |
| E2E-P4.11-04 | H-XW | `runScheduled("0 * * * *")` → `scheduled()` calls `VendorEntrypoint.listIssuerKeys` and `VendorEntrypoint.listOperatorCredentials` over the `PLATFORM` binding (`ai-platform/src/vendor/entrypoint.ts`); AL-22 is captured from `send_email` (rule V6) | AD-9: an extra issuer `kid` on the platform not in the pins → AL-22; an unannounced operator credential → AL-22 | FR-004 | User Story 2 |
| E2E-P4.11-05 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` on the ABO worker (`abo/src/worker.ts`) | The ABO daily 06:00 UTC `scheduled()` cron (`0 6 * * *`) deletes 91-day-old done work rows and sent alerts; facts untouched | FR-005 | User Story 1 |
| E2E-P4.11-06 | H-XW | The ABO rebuild script and runbook, run by the H-XW test: wipe the ABO D1, replay R2 `ledger/` , recompute status, re-inquire the gap, and call `VendorEntrypoint.listGrants` over the `PLATFORM` binding (`ai-platform/src/vendor/entrypoint.ts`) | FM-19: wipe the ABO D1 → replay `ledger/` → facts and status restored; gap re-inquired; a payment with no grant gets one → `already_applied`; reconciliation clean [RC-04] | FR-006 | User Story 3 |
| E2E-P4.11-07 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` on the ABO worker (`abo/src/worker.ts`); digest send is captured from `send_email`, and the daily heartbeat ping is captured as the outbound fetch to the configured heartbeat URL (rule V6) | Digest send failure retried; daily heartbeat ping sent | FR-007 | User Story 1 |

### 2.5 Edge Cases

- An issuer key with `not_after` within 29 days raises AL-14 daily. AL-14 is a key within 30 days of `not_after`, raised by the ABO, repeated daily. Detection of issuer-key expiry is AL-14. The operator step is rotate. (E2E-P4.11-02, 05 §2 row AL-14, FM-17, A25)
- `listIssuerKeys` returns `{kid, public_key, status, not_before, not_after}` for each `issuer_key` with `status` `active` or `retiring`. The hourly pin comparison uses the set of `{kid, public_key}` against pinned `ISSUER_KEYS`. `status` and the validity times are not a pin mismatch. Validity is the AL-14 key-expiry check. (04 §1.3 row `listIssuerKeys`, 05 §2 rows AL-14 and AL-22)
- An extra issuer `kid` on the platform that is not in the pins raises AL-22. An operator credential the ABO has not seen announced by AL-13 raises AL-22. AL-22 repeats hourly. (E2E-P4.11-04, 05 §2 row AL-22, 05 §1 ABO hourly row, 02 §4.2 row AD-9)
- `feed_consumer` stale for 6 minutes raises AL-15 hourly. AL-15 is the backend not having pulled the feed for 5 minutes (`feedConsumerHealth`), raised by the ABO, repeated hourly. `feedConsumerHealth` returns `last_pull_at` and `last_cursor`. (E2E-P4.11-03, 05 §2 row AL-15, 04 §1.3 row `feedConsumerHealth`, Implements)
- The daily 06:00 UTC run deletes 91-day-old done work rows and sent alerts. Facts stay. Completed work rows and sent alerts are kept 90 days. Invalid-HMAC samples are kept 30 days. (E2E-P4.11-05, 03 §8, 05 §1 ABO daily row)
- A failed digest send is retried. The same daily run sends the heartbeat ping. (E2E-P4.11-07, 05 §1 ABO daily row)
- Wiping the ABO D1, then replaying `ledger/`, restores facts and status. The gap is re-inquired. A payment with no grant gets a grant row and the platform answers `already_applied`. Reconciliation is clean. (E2E-P4.11-06, 05 §5.1, FM-19, RC-04)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The daily digest runs on the ABO daily 06:00 UTC `scheduled()` cron `0 6 * * *`. It proves the jobs are alive (NFR-04) and lists every grant (SR-23). It contains: 24-hour counts of checkouts, payments by classification, grants by source, reversals and alerts; every grant, and complimentary, adjustment and transfer grants with operator, reason, length and allowance; open findings, parked work and open alerts; the last run time of each scheduled job, including the backend's last feed pull; the R2 lock status and export lag, and keys expiring within 30 days; per channel, the contract versions received and the count of `contract_version_unsupported` answers, which show when an old version can be dropped (04 §7.3). Per-channel version counts are limited to the channels the ABO observes. The digest is captured from `send_email`. (05 §3.4, 05 §1 ABO daily row, Implements, 06 §6, E2E-P4.11-01, rule V6)
- **FR-002**: AL-14 is a key within 30 days of `not_after`, raised by the ABO, repeated daily, for A25. The daily key-expiry check reads issuer-key validity from `listIssuerKeys` and includes ABO service keys. An issuer key whose `not_after` is within 29 days raises AL-14 daily. FM-17 is detected by AL-14. The operator step is rotate (02 §6). Alerts go through `send_email`, are deduplicated by `alert_key`, and repeat at the stated interval while the condition holds. Every alert also appears in the digest. (05 §2 row AL-14 and the section introduction, 05 §1 ABO daily row, 04 §1.3 row `listIssuerKeys`, Implements, E2E-P4.11-02, FM-17, A25)
- **FR-003**: AL-15 is the backend having not pulled the feed for 5 minutes (`feedConsumerHealth`), raised by the ABO, repeated hourly, for FR-63 and 01 R-4. The hourly `scheduled()` cron `0 * * * *` calls `feedConsumerHealth`. The method returns `last_pull_at` and `last_cursor`. `feed_consumer` stale for 6 minutes raises AL-15 hourly. (05 §2 row AL-15, 04 §1.3 row `feedConsumerHealth`, Implements, E2E-P4.11-03, FM-10)
- **FR-004**: AL-22 is the platform's issuer keys differing from the ABO's pinned `ISSUER_KEYS`, or an operator credential that the ABO has not seen announced by AL-13, raised by the ABO, repeated hourly, for SR-11 and 02 AD-9. The hourly `scheduled()` run compares issuer keys and operator credentials with the ABO's pins and last-seen list. `listIssuerKeys` returns `{kid, public_key, status, not_before, not_after}` for each `issuer_key` with `status` `active` or `retiring`. `public_key` is the base64url raw 32-byte Ed25519 key. The pin comparison is the set of `{kid, public_key}` against pinned `ISSUER_KEYS`. `status` and the validity times are not a pin mismatch. `listOperatorCredentials` returns `{credential_id, public_key_cose, alg}` for each `operator_credential` with `status` `active`. An extra issuer `kid` on the platform that is not in the pins raises AL-22. An unannounced operator credential raises AL-22. AD-9 is noticed by this hourly comparison, together with ABO reconciliation and the external heartbeat if the platform goes silent. (05 §2 row AL-22, 05 §1 ABO hourly row, 04 §1.3 rows `listIssuerKeys` and `listOperatorCredentials`, 02 §4.2 row AD-9, Implements, E2E-P4.11-04)
- **FR-005**: Housekeeping runs inside the ABO daily 06:00 UTC `scheduled()` cron `0 6 * * *`, the same run as reconciliation, the digest, the R2 lock check, the key-expiry check, and the daily heartbeat. That run deletes completed work rows and sent alerts older than 90 days, and invalid-HMAC samples older than 30 days. Commercial facts are not deleted. Completed work rows and sent alerts are kept 90 days (operational). Invalid-HMAC samples are kept 30 days (diagnosis only). The cron deletes 91-day-old done work rows and sent alerts, and leaves facts untouched. (05 §1 ABO daily row, 03 §8, Implements, E2E-P4.11-05)
- **FR-006**: The ABO rebuild procedure satisfies RC-04 and ends with a clean reconciliation run. Within 30 days of the damage, restore D1 with Time Travel to a point before it. Otherwise, create an empty D1, replay the `ledger/` NDJSON facts in `fact_seq` order (inserts pass the append-only triggers), then recompute the status tables. Fill the gap after the last exported fact: re-inquire every checkout and payment reference known to the rebuilt set, and every transaction in the provider's dashboard export for the gap window. Compare with the platform's `listGrants`. A paid grant with no payment is re-derived from the provider inquiry. A payment with no grant gets a grant row. Its `grant_id` is deterministic, so the platform answers `already_applied`. The procedure is a script plus a runbook. Wiping the ABO D1, then replaying `ledger/`, restores facts and status, re-inquires the gap, gives a grant to a payment that has none, receives `already_applied`, and leaves reconciliation clean. FM-19 is ABO data loss or a bad restore. Its detection is AL-16 and reconciliation. Its operator step is §5.1. (05 §5, 05 §5.1, FM-19, Implements, E2E-P4.11-06, RC-04)
- **FR-007**: The daily 06:00 UTC run sends the heartbeat ping. A digest send failure is retried. The heartbeat ping is the outbound fetch to the configured heartbeat URL. (05 §1 ABO daily row, E2E-P4.11-07, rule V6)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An operator receives one daily digest for the clinic's billing jobs, grant list, open findings, and key expiry, and can rebuild the ABO records from the ledger copy after data loss. The unit adds no clinic-desktop flow and no second clinic product.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. The daily run and the hourly watch are `scheduled()` on the ABO worker (`abo/src/worker.ts`) for crons `0 6 * * *` and `0 * * * *`. `abo/wrangler.toml` already declares `0 6 * * *`. Platform reads go through `VendorEntrypoint.listIssuerKeys`, `VendorEntrypoint.listOperatorCredentials`, `VendorEntrypoint.feedConsumerHealth`, and `VendorEntrypoint.listGrants` over the `PLATFORM` binding. H-XW runs that platform worker from source. The rebuild procedure is a script plus a runbook in this codebase. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: Commercial facts stay in place, including through housekeeping. Housekeeping deletes completed work rows and sent alerts older than 90 days, and invalid-HMAC samples older than 30 days. Ledger replay inserts facts in `fact_seq` order through the append-only triggers. Issuer-key pin comparison uses `{kid, public_key}` from `listIssuerKeys` against `ISSUER_KEYS`. Operator credentials are compared with the list announced by AL-13. `feedConsumerHealth` is called as frozen by P3.9. (03 §8, 05 §1 ABO daily row, 05 §5.1, 04 §1.3, 05 §2 row AL-22)
- **Failure Handling**: A digest send failure is retried, and the daily heartbeat ping is still sent. (E2E-P4.11-07) An issuer key within 29 days of `not_after` raises AL-14 daily. (E2E-P4.11-02, FM-17) A feed pull stale for 6 minutes raises AL-15 hourly. (E2E-P4.11-03) An unpinned issuer `kid` or an unannounced operator credential raises AL-22 hourly. (E2E-P4.11-04, AD-9) ABO data loss is recovered by the §5.1 replay, and the run ends with a clean reconciliation. (E2E-P4.11-06, FM-19, RC-04)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P3.9 freezes the HTTP feed contract, the `/v1/coverage` response, and `feedConsumerHealth`. This unit calls `feedConsumerHealth`. P4.10 states no Outputs / freezes line. This unit calls `listIssuerKeys`, `listOperatorCredentials`, and `listGrants` as those methods already stand.
- No module that no test-plan row reaches (rule S8). The digest is reached by E2E-P4.11-01 and E2E-P4.11-07. AL-14 and the key-expiry check are reached by E2E-P4.11-02. AL-15 and `feedConsumerHealth` are reached by E2E-P4.11-03. AL-22, `listIssuerKeys`, and `listOperatorCredentials` are reached by E2E-P4.11-04. Housekeeping is reached by E2E-P4.11-05. The rebuild script, `ledger/` replay, and `listGrants` comparison are reached by E2E-P4.11-06. The daily heartbeat ping is reached by E2E-P4.11-07. The same housekeeping run deletes invalid-HMAC samples older than 30 days (03 §8, Implements). E2E-P4.11-05 states the 91-day work-row and sent-alert deletion and that facts stay. This spec adds no E2E id. AL-14 includes ABO service keys (Implements). E2E-P4.11-02 states the issuer-key case. This spec adds no E2E id.
- No S9 path owned by a later unit. The unit names none. Backend feed pull and status projection stay with P5.2. The cross-deploy version matrix stays with P7.3. Platform rebuild stays with P3.11 (§5.2 and §5.3). The external heartbeat monitor stays with P8.1. This unit sends the ABO daily ping.
- No second codebase. The Codebase cell is `abo`. H-XW binds the real platform worker. This unit does not add a platform wiring exception.
- Reconciliation checks stay with P4.10. The daily cron already runs them. The digest lists open findings. The rebuild procedure ends with a clean reconciliation run (05 §5, E2E-P4.11-06).
- The hourly signing-`kid` check and AL-23 stay on the existing hourly run. This unit adds the AL-22 comparison and the AL-15 `feedConsumerHealth` check to that same `0 * * * *` run (05 §1 ABO hourly row, Implements).
- The platform `0 3 * * *` and `0 4 * * *` retention crons stay platform usage purge (05 §1). ABO work rows, sent alerts, and invalid-HMAC samples are deleted by the ABO daily `0 6 * * *` run.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.11-01 through E2E-P4.11-07 pass in harness H-XW.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- The per-channel version counts in the digest (P4.11) are limited to channels the ABO observes. (06 §6)
- No S9 transitional path is named by this unit.
