# R9 — Durability, recovery and executable operations

**Complete with findings: 0 P0, 13 P1, 7 P2, 1 optional P3.** Reviewed 2026-10-17–18; completed 2026-10-18 Africa/Cairo at immutable target `db9244fddfddc1905335fb8c7105328c15a0cc5e` (T), baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`, history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. Workspace HEAD started/ended at newer `a2545299b82fd0c22f92d316fb4790ce47c159c9`; source/reference reads used pinned git objects. Lead GPT-6.1 Sol/high; platform, ABO operations and runtime reviewers GPT-6.1 Sol/medium, explicitly configured. [Coverage](R9-coverage.md), [exact ranges/dispositions](R9-coverage.json), [checkpoint](R9-checkpoint.md).

All 457 manifest tuples are accounted for. **7,529 primary source lines were actually read; 252 embedded fixture/harness lines were excluded**, correcting the packet's 7,781 primary inventory. Of 13,800 supporting artifact lines, 1,166 non-lock lines were read for production effects; 12,634 generated lock lines were parsed for selected runtime/operational dependency resolution. Three missing-manifest executable programs were additionally read (135 lines). Detailed supporting expansions remain separately logged. Completion means source ownership and diagnosis are closed; it does not approve launch.

## Durable truth and recovery boundaries

| Effect and order at T | Failure/replay result and required boundary |
| --- | --- |
| ABO raw evidence R2 → notification/inquiry D1 → payment/work | Raw bodies can survive without an authoritative index; notification/inquiry facts are absent from export. FACT1 restores exact evidence membership; R3-C5 owns producer atomicity and lease/dedupe; R6-O2 owns erasure fencing. |
| ABO commercial row + fact_log → R2 `ledger/<fact_seq>.ndjson` → fact_export | Export is R2-first. A lost marker requires equal-object acknowledgment; replay currently trusts hashes/rows, renumbers facts and cannot resume. REC1 preserves original sequence, schema/version and immutable identity; missing/tampered/conflicting objects stop publication. Actual provider overwrite/lock semantics remain external. |
| Accepted grant/void/transfer → DO mutation/receipt/outbox → D1 ledger/event/mirror → separate grant/void R2 objects | DO remains coverage authority. R4-D1/D4, R6-DM2/DM3/O1 own atomic intent and wake-up. PAL1 owns losing an already queued alert; PDO1 prevents replacing newer authority with a stale shipped copy. Original command, grant claim, route/epoch, package and receipt must survive. |
| DO settlement → later Worker usage fact; snapshots include counters | Journal wall time cannot prove snapshot inclusion (PUS1). Request erasure destroys nullable identity (PRET1). Recovery needs stable accounting sequence/identity and original-term settlement receipts, composing with R5-A2/A3/J1. It must never recreate spent allowance. |
| R2 ledger → D1 ledger/void → surviving DO refresh → event/mirror | PD1 identifies the circular missing-event prerequisite. Registry/binding restoration is a separate explicit prerequisite: ledger summaries cannot reconstruct keys, binding authority or original signed envelope. REC1 validates imports; the inherited R4-D5 addendum requires original envelope/authorization capsules. |
| ABO ledger → projections → re-inquiry → resumed commands → reconciliation | REC2 restores pending work from immutable facts and prohibits creating new provider orders during recovery. REC3 applies the ordinary price/currency withholding predicate. Unknown original order/payment mapping stays blocked under R3-C2/C4 owner adjudication. Reconciliation findings never count as successful provisioning. |
| Feed event → backend/ABO projection; explicit reset → replay | Backend projection remains display only; cursor zero replay uses retained full snapshots. Ordinary advancement stays monotonic under R7-A1. Explicit recovery/reset must fence competing refresh generations; retain original event versions and historical suspend/resume aliases (R6-DM5), rather than rewriting facts. |

Receipts need both cryptographic validity and request/business linkage (canonical R4-A2/R6); equality reconciliation is only an independent-copy check. Nil-org/installation, seq-zero pre-grant tombstones are an intentional exception, but still require the original verified void receipt (AO1). Payouts require exact reversal identity rather than any earlier refund (AO2). Missing local projections/requests are discrepancies (AO3). All historical unknown actor/signer/predecessor/hash/lineage decisions remain named maintainer plus frontier adjudication stops; today's catalogue or registry is never substitute evidence.

## New findings and concrete remediation

All are high-confidence static source defects; severity reflects the demonstrated consequence, without a runtime reproduction. Each linked evidence report provides exact T paths/line numbers, causal trigger, ordered edit/transaction/migration/replay steps and source-visible completion checks. The concise recipes below are the implementation order; use the linked full recipe as authoritative detail.

| ID / severity | Trigger and consequence | Chosen fix and completion boundary |
| --- | --- | --- |
| **R9-REC1 / P1** — unchecked/nonresumable ledger import | Restore interruption leaves duplicate-key failure; skipped gaps renumber facts; platform INSERT OR IGNORE masks conflicting receipts/metadata. | 1. Add versioned schema/key/hash/receipt validators to both importers and preserve original fact_seq.<br>2. Commit row/log/checkpoint batches atomically; acknowledge existing equal records/exports and stop on conflicts.<br>3. Complete when interrupted replay resumes identically and gaps/tampering cannot activate recovery. [Full steps](R9-lead-review.md#r9-rec1--p1-ledger-import-does-not-validate-original-identity-and-abo-restore-cannot-resume). |
| **R9-REC2 / P1** — recovery loses due commands and creates replacement orders | Restored payment/reversal lacks work; known inquiries are discarded; replacement provider orders break original payment correlation. | 1. Remove createCheckout from recovery; block missing historical correlation pending R3-C2/C4 owner decision.<br>2. Derive unique due work from immutable facts; reuse exact stored signed bytes/version and normal key/receipt gates.<br>3. Complete when restored payments/reversals resume their original commands once without replacement provider orders. [Full steps](R9-lead-review.md#r9-rec2--p1-restored-facts-do-not-recreate-the-due-work-and-gap-recovery-creates-new-checkouts-instead-of-recovering-old-transactions). |
| **R9-REC3 / P1** — recovery bypasses withholding | Bound successful transaction with wrong amount/currency is unconditionally grant-eligible. | 1. Share the binding and exact amount/currency decision between normal and rebuild confirmation.<br>2. Atomically record mismatch evidence, withheld disposition and AL-05 without grant work.<br>3. Complete when mismatches remain withheld across replay and an exact match provisions once. [Full steps](R9-lead-review.md#r9-rec3--p1-rebuild-bypasses-the-normal-amountcurrency-withholding-rule). |
| **R9-FACT1 / P1** — locked recovery omits evidence facts | D1 loss removes notification/inquiry correlation and cancellation facts; fake inquiry IDs/empty hash hide missing evidence. | 1. Add production append helpers batching each immutable row, fact_log and dependent work, including cancellation.<br>2. Retain authenticated response references/hashes under the erasure fence; reuse the actual decisive inquiry identity.<br>3. Complete when restore retains callback/inquiry/cancellation links without invented bytes or resurrected erased bodies. [Full steps](R9-lead-review.md#r9-fact1--p1-immutable-callbackinquiry-and-cancellation-facts-are-absent-from-the-locked-recovery-ledger). |
| **R9-CRON1 / P1** — false job health | Work is stamped before execution; failed digest/reconciliation still produces health ping; missed daily work has no due checkpoint. | 1. Migrate to per-job start/success/error and persisted due-period leases; stamp success after completion.<br>2. Persist/log failures and retry pending periods from minute cron; emit digest-success heartbeat only after delivery acknowledgment.<br>3. Complete when failures retain due work and overlapping catch-up completes each period once. [Full steps](R9-lead-review.md#r9-cron1--p1-scheduled-failures-are-reported-as-successful-health-and-are-never-retried-as-missed-jobs). |
| **R9-PDO1 / P1** — destructive partial DO replacement | H rebuild wipes a nonempty DO/new unshipped grant before remote reads and exposes partial/stale state without restored alarm. | 1. Refuse nonempty targets and persist a fenced recovery generation for an empty target.<br>2. Validate the complete candidate before atomic installation; reconcile the alarm before unblocking.<br>3. Complete when external-read failures expose no partial coverage and witness/epoch mismatches stop activation. [Full steps](R9-platform-review.md#r9-pdo1--p1-rebuild-can-erase-newer-authoritative-coverage-and-leave-a-partial-replacement-live). |
| **R9-PUS1 / P1** — usage double charge after snapshot | Settlement is in snapshot, journal timestamp arrives later, then recovery adds it again. | 1. Commit DO accounting sequence/receipt atomically and include its watermark in snapshots.<br>2. Deploy compatible unique D1 accounting identity and replay only greater sequences on original terms.<br>3. Complete when delayed journal arrival cannot double-charge; block old unknown ordering for adjudication. [Full steps](R9-platform-review.md#r9-pus1--p1-wall-clock-replay-can-charge-usage-already-included-in-the-anchor-snapshot). |
| **R9-PRET1 / P1** — retention erases recoverable usage identity | 90-day erasure NULLs IDs; recovery Set collapses distinct retained charges and recreates allowance. | 1. Preserve origin/accounting identity independently of the erasable request FK before resuming purge.<br>2. Rebuild old NULL-request rows by stable event ID and retain usage until the term is proven ended.<br>3. Complete when distinct aged charges survive journal erasure and held/unknown terms cannot be age-purged. [Full steps](R9-platform-review.md#r9-pret1--p1-journal-expiry-destroys-retained-usage-identity-and-rebuild-collapses-multiple-charges). |
| **R9-PD1 / P1** — circular D1 snapshot bootstrap | Missing event/mirror tables prevent asking intact DO for the first replacement snapshot. | 1. Replace the missing-event prerequisite with verified restored binding→installation/org/epoch mapping.<br>2. Validate the surviving DO identity and ship its fresh snapshot through the normal outbox.<br>3. Complete when empty event/mirror tables bootstrap truthfully; missing/conflicting registry mappings remain blocked. [Full steps](R9-platform-review.md#r9-pd1--p1-d1-snapshot-recovery-requires-the-coverage-events-it-is-supposed-to-recreate). |
| **R9-PAL1 / P1** — security alert retry loses payload | DO deletes queued payload before durable delivery; dispatcher skips AL-11/12/19 and other unsent codes. | 1. Persist immutable operation/actor/version/body before acknowledging the DO alert outbox.<br>2. Dispatch every supported due code through a common leased retry path, preserving original AL-19 transitions/audit.<br>3. Complete when delivery failure retries the same evidence; body-less history stays blocked pending corroboration. [Full steps](R9-platform-review.md#r9-pal1--p1-queued-grant-override-and-control-alerts-have-no-failure-retry). |
| **R9-RT1 / P1** — launch command trusts unbound snapshots | Old/partial locally supplied booleans can return green after live configuration changes. | 1. Operations/frontier selects the actual read-only adapter/auth contract; stop dependent implementation until resolved.<br>2. Add target-bound fresh acquisition and strict validation; label supplied-file evaluation as offline.<br>3. Complete when live changes affect the result and stale/partial files cannot report authoritative launch success. [Full steps](R9-runtime-review.md#r9-rt1--p1-launch-check-never-checks-the-target-environment). |
| **R9-RT2 / P1** — external monitoring is only classifiers | Membership arrays have no timestamps/live acquisition/delivery; ABO minute ping masks absent daily digest on its same URL. | 1. Operations/frontier selects external receiver/audit/scheduler/delivery contracts and deadlines; stop before guessing them.<br>2. Add durable audit cursor/delivery acknowledgment, separate heartbeat streams and timestamp expiry with retry.<br>3. Complete when one missing stream is detected despite surviving streams and audit pagination loses no event; no static uptime certification. [Full steps](R9-runtime-review.md#r9-rt2--p1-external-failuresecurity-monitoring-consists-only-of-snapshot-classifiers). |
| **R9-RT3 / P1** — published production private signing default | Supplied production/staging config uses development private receipt key; repository holder can sign under that default if deployed. | 1. Remove nondevelopment private vars, provision separate secrets and reject the published key fingerprint before mutation.<br>2. Operations owner establishes prior deployment and coordinates pin-first rotation/historical trust handling.<br>3. Complete when nondevelopment cannot sign with the published key, even renamed; no remote grant bypass is claimed. [Full steps](R9-runtime-review.md#r9-rt3--p1-production-configuration-includes-the-development-private-receipt-signing-key). |

Moderate defects below have bounded impact and remain distinct from their producer roots. Their numbered recipes summarize the established [ABO operations evidence](R9-aboops-review.md#findings); the linked full recipe retains exact T lines and detailed acceptance boundaries.

### R9-AO1 — P2: planned tombstone accepted without completed receipt

`abo/src/reconciliation/run.ts:271–294` skips requested tombstone effects before verifying completion. [Full evidence and steps](R9-aboops-review.md#r9-ao1--p2-a-planned-tombstone-is-treated-as-completed-reversal-evidence).

1. In `checkReversalNotApplied`, exempt only `effect='none'`; require an applied/already-applied outcome for every other full reversal, including tombstones.
2. Reuse the R6 verified void consumer to bind the original receipt to the command. Preserve legitimate nil UUIDs, ledger_seq0 and empty terms for pre-grant tombstones; no coverage event is required.
3. Complete when missing, rejected or mismatched outcomes produce `reversal_not_applied`/AL-10, while a verified original tombstone passes. Compose with canonical R6-PT1/DM3.

### R9-AO2 — P2: earlier partial refund masks a distinct payout chargeback

`reconciliation/run.ts:400–428` accepts any reversal on a payment instead of matching the imported reversal. [Full evidence and steps](R9-aboops-review.md#r9-ao2--p2-a-partial-refund-can-hide-a-different-payout-chargeback).

1. Extend `ProviderPort.PayoutLine` and Paymob normalization with an opaque adapter-owned reversal identity and positive normalized amount; add immutable payout evidence/link records plus fact/rebuild mapping.
2. Change `checkUnrecordedReversal` to match exact normalized identity, payment, kind and amount after R6-BR1/BR3. An unrelated partial refund cannot satisfy a chargeback; CSV evidence never automatically creates a reversal or void.
3. Complete when a distinct chargeback remains `unrecorded_reversal` until matched authoritative/manual evidence exists, and repeated exact payout evidence links once. **Historical linkage is not implementation-ready:** maintainer/provider owner plus frontier must approve retained-evidence mappings; ambiguous legacy rows stay unmatched.

### R9-AO3 — P2: missing local projection/request copies escape reconciliation

`run.ts:565–575,614–619` skips absent coverage_view and inner-joins away orphan applied outcomes. [Full evidence and steps](R9-aboops-review.md#r9-ao3--p2-reconciliation-ignores-missing-local-copies).

1. In `checkFeedDivergence`, treat missing coverage_view for an org established by a recent valid event as divergence, retaining epoch/sequence evidence; do not conceal it by copying the live read.
2. LEFT JOIN applied outcomes to grant_request in the receipt check. Exclude only explicitly known transfers; a missing request is a receipt/lineage discrepancy.
3. Complete when either missing local copy creates a durable finding/AL-10, while legitimate transfer exclusions and full receipt/signature equality remain intact. Apply R7-A1 projection repair separately.

### R9-AO4 — P2: committed finding loses its AL-10 permanently

`run.ts:59–84` commits finding+fact before its alert; subsequent existence checks suppress alert repair. [Full evidence and steps](R9-aboops-review.md#r9-ao4--p2-a-committed-finding-can-permanently-lose-its-al-10).

1. Add a unique `finding_identity(kind,subject,finding_id)` registry. Backfill the deterministic earliest detected-at/finding-id representative while preserving every immutable duplicate fact/resolution.
2. Atomically claim identity and batch the winning finding, fact and prepared `AL-10:<finding_id>` alert insert. For an existing unresolved identity, repair a missing alert without resetting successful delivery time.
3. Batch resolution and deactivation under AO5; do not reopen resolved identities on replay. Complete when interruption leaves either no finding or finding+due alert, and overlapping detection claims one canonical identity.

### R9-AO5 — P2: recovered/resolved conditions keep repeating as active alerts

`alert/index.ts:155–163,182–197`, hourly watch and finding resolution leave recovered conditions active. [Full evidence and steps](R9-aboops-review.md#r9-ao5--p2-resolved-conditions-keep-repeating-as-active-alerts).

1. Expose a prepared clear helper; clear resolved export lag regardless of last_sent_at, preserving delivery audit metadata while setting active=0/unsent=0.
2. Clear AL-15 only after valid fresh feed health. Following complete successful registry reads, clear only AL-22 keys whose exact mismatch disappeared; unknown/refused/failed reads clear nothing.
3. Batch finding_resolution+fact with AL-10 deactivation in `handlePostResolveFinding`; R6-O1 retains accepted-command replay. Complete when recovery stops repeats and genuine recurrence sends again. Never blanket-clear once-only transition alerts such as AL-19.

### R9-AO6 — P2: invalid-HMAC retention ignores subsequent R2 pages

`housekeeping/run.ts:32–41` ignores list continuation, allowing an expired-sample backlog to grow. [Full evidence and steps](R9-aboops-review.md#r9-ao6--p2-invalid-hmac-retention-ignores-further-r2-pages).

1. Iterate list cursors while preserving the existing cutoff and `hmac-invalid/` prefix.
2. Bound deletion work per invocation with a persisted housekeeping cursor/budget; acknowledge a page only after its deletions finish and resume via the existing minute/daily schedule.
3. Complete when interrupted multi-page cleanup eventually removes expired samples, retains samples at/after cutoff and never touches verified evidence, ledger or payout objects. A cron start timestamp cannot mean cleanup completion.

### R9-AO7 — P2: malformed/partial/mixed-period payout files become accepted imports

`ops/index.ts:1719–1798` accepts the adapter's incomplete line array and derives an unreliable period. [Full evidence and steps](R9-aboops-review.md#r9-ao7--p2-malformed-payout-files-become-successful-emptypartial-imports).

1. Make `payoutLines` return typed success/error with line errors. Validate the fixed header, full six-field rows, kind, full-string safe integers and valid UTC settled_at; reject the entire file on any malformed row or empty/header-only result.
2. Require one UTC YYYY-MM across all rows; reject mixed months with a split-file error. Validate before R2/accepted-import mutation and return the existing versioned invalid_request on failure.
3. Use R6-O1's stable command/file-hash identity for accepted-import retry. Complete when bad/partial/mixed-period files create no accepted import, valid files commit all lines+facts atomically and exact retries return the original result.

### R9-AO8 — optional P3: payout-import list always returns empty

`ops/index.ts:1688–1695` returns literal `payout_imports: []` after imports have been stored. [Full evidence and steps](R9-aboops-review.md#r9-ao8--p3-payout-import-listing-always-returns-an-empty-array).

1. Pass env into `handleGetPayoutImports`; query stored metadata with deterministic period/import-id ordering and a bounded cursor/page.
2. Return import ID, provider, file hash, period and actor in the existing versioned response, retaining Access gating and excluding raw CSV contents.
3. Complete when accepted imports appear once, only an empty database returns [] and database errors cannot masquerade as empty successful history.

No P2 ceiling finding is recounted: the [recovered-envelope metadata addendum](R9-platform-review.md) extends canonical **R4-D5**.

## Cron, monitoring, audit and operational limits

ABO minute runs export/alerts/feed/inquiry/transfer; hourly runs key/self-check, reversal population and registry watch; six-hour and daily populate other reversals. Daily also runs lock/reconciliation/digest/housekeeping. Platform five-minute retries fallback/alerts and pings; daily purge/rollup retain their schedules. Source wiring exists, but CRON1/PAL1/RT2 prevent treating its health signals as completed work or delivered alarms. Missing chron execution requires persisted due-period catch-up; fallback retries must preserve original term and accounting receipt (R5), not replay value blindly.

Source lock check implements amended 076:2 exactly: a non-success management response is unknown and deliberately raises no missing-lock alarm. Runtime config disables workers.dev/previews, production omits TEST_CLOCK/DURATION_SCALE, and test-clock access is environment-binding gated; no request setter was established. Export/package and source guards were read, never executed. Local vendor-contracts resolves to its production root; testkit is separately exported but no production import was found. Operational Wrangler graph is parsed despite devDependency labels; the rebuild launcher tsx is unpinned/undeclared and belongs in REC1's execution repair.

Static review cannot certify live default ACL/owner/RLS execution identities, actual account separation/Access policy, bucket lock/overwrite semantics, deployed secret values/key ceremonies, provider expiry/inquiry/CSV contracts, monitor scheduling/uptime or native SendEmail binding compatibility. No account or provider research/operations were performed. RT1/RT2 actual adapter selection and historical/provider mapping/usage attribution are explicit owner decisions; safe containment is offline-only health labeling and blocked affected recovery/mutations, not guessed implementation.

## R10 handoff, without executing R10

1. R10 owns the combined D1/R2 failure→rebuild→resumed grant/void→feed narrative, using REC1–3/PDO1/PD1 and inherited R3/R4/R6 command conservation. Verify old signed bytes/version/receipt/epoch survive; never recreate value or cross binding generation.
2. R10 owns settlement/fallback→snapshot→retention/rebuild integration under PUS1/PRET1 and R5-A2/A3/J1, with unresolved old accounting evidence retained as a stop.
3. R10 owns accepted HP/H mutation→audit/AL-19/outbox→delivery under PAL1, R6-O1 and R8-AUDIT1/PUB1, including original actor/signer/predecessor/publication hash. Historical aliases and immutable original signatures remain preserved.
4. R10 owns explicit cursor reset versus concurrent ordinary refresh (R7-A1), and reconciliation/receipt/payout detection after recovery; AO1–7 are detectors, not automatic authority to mutate money/coverage.
5. Operations/maintainer plus frontier reviewer own RT1/RT2 adapter/deadline choices, R3-C2/C4 provider correlation, RT3 deployed-key history and all ambiguous historical repairs. Their absence does not leave R9 source unread, and must remain visible in consolidated readiness conclusions.

All 37 routed escalation dispositions are in [coverage](R9-coverage.md). Existing R1–R8 roots remain canonical and unfixed; only R9 artifacts/tracker changed. No tests/builds/lint/guards/services, excluded correctness review, live research, source changes, commits/pushes/branch switches or usage/account-limit checks occurred. Narrow incidental navigation over unrelated production worker ranges was not correctness-credited; no excluded bodies were used as evidence. R0–R8 preserved; R10 **not started**; overall review **in progress**.
