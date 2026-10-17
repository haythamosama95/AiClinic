# R9 ABO operations slice

**Complete with findings.** Target `db9244fddfddc1905335fb8c7105328c15a0cc5e` (T); GPT-6.1 Sol, explicitly **medium**; 2026-10-17 Africa/Cairo. All **104 exact assigned tuples / 1,927 lines** are read; no unread primary source. Source was loaded with `git show T:path`, never substituted with newer HEAD. [Exact coverage and escalation dispositions](R9-aboops-coverage.json). Only this report and its coverage file were written.

This is static source reasoning. No tests, fixtures, harnesses, testkit, campaigns or viewer implementation were reviewed; no tests/build/lint/guards/services/provider/account calls, source fixes, commits or branch operations ran. No runtime reproduction, deployment health or launch approval is claimed.

## Established traces and inherited roots

The daily and post-import reconciliation path reads ABO payment/reversal/outcome facts and platform `listGrants`; failures append finding+fact, then raise AL-10. Grant receipt comparison canonicalizes the complete receipt object, including signature, and flags a missing platform grant. It intentionally excludes transfer receipts (085:1). This equality is an independent-copy comparison, not cryptographic validation or business linkage; R4-A2 owns those producer checks. Machine `listGrants` has the amended ascending applied-at/grant-id order; feed calls request limit 200.

Payout import stores raw file bytes at their hash key, normalizes adapter lines, then batches import+lines+facts. Local operator action and platform audit occur afterward; R6-O1 remains canonical for acceptance/audit recovery, including these two ABO-verified H handlers. Finding resolution adds an immutable resolution+fact and an action, retaining original commercial evidence. The list endpoint and alert consumers have the gaps below.

Hourly watch compares exact issuer key maps and exact active credential triples with the ABO's successful-registration last-seen list. It does not populate that list from platform alerts or hourly responses. The registration relay stores a pending triple from its successful detail before later activation; this follows 086:2. `rememberOperatorCredential` and the comparison swallow database errors, so successful registration/monitor execution is not proof of durable baseline observation. R6-O1's accepted-command stages must retain and retry the exact registration result/triple; never bootstrap trust by copying the current platform list.

The lock checker follows 076:2: only a successful API body with no enabled indefinite `ledger/` or whole-bucket lock raises AL-16; API failures deliberately leave state unchanged. This is an explicit detection limit, not a newly invented source defect. Digest reads real DB/platform state, lists all grant requests/open findings/parked work, and retries email once. It cannot prove job completion: the lead owns cron's pre-work timestamps, swallowed stage failures and success heartbeat. ABO and platform email helpers both pass plain objects to native `send_email`; native message compatibility is assigned to the lead/runtime slice, without an external or live assumption here.

Inherited R1-C1/C2 and SQL authority, R2-C2/C3/P4, R3-C2/C4/C5/C7, R4-A1/A2/D1/D4/D5/PG1/PG3, R5 accounting/recovery, R6-PT1/DM2/DM3/O1/O2 and R7-A1 remain canonical. Reconciliation must consume their immutable original receipts, accepted commands, per-org history and atomic outcome view. Recovery must not infer missing actors, authorizations, lineage or receipts from current state. Existing ambiguous historical data requires maintainer/frontier adjudication and a safe stop for affected mutations; no guessed repair is authorized. AL-19 remains the platform's once-per-transition alert; these recipes do not change its semantics.

## Findings

All are high-confidence source defects. No new P0/P1 is established in this bounded slice; the inherited value/accepted-command defects retain their original severity.

### R9-AO1 — P2: a planned tombstone is treated as completed reversal evidence

`abo/src/reconciliation/run.ts:271–294` skips every full reversal whose **requested** effect is `tombstone`, before reading any outcome. That value is intent, not proof that the platform stored a tombstone. `abo/src/work/reversal.ts:707–718,735–795` can pause, fail, defer or park before a successful signed receipt/outcome. A reversal before grant therefore passes daily reconciliation even when its protective void never completed. This is a missing detector, distinct from R6-PT1's wrong routing/mutation root; no claim that reconciliation itself grants value.

**Fix steps (implementation-ready; compose with R6-PT1/DM3):**
1. In `checkReversalNotApplied`, exempt only genuine `effect='none'`; require an applied/already-applied outcome for every other full reversal, including tombstone.
2. Use the shared verified-void-result consumer introduced by the R6 remedy to require request-bound grant/reversal identity and original receipt. For a genuine pre-grant tombstone preserve the amended nil UUIDs, seq 0 and empty terms; never demand a coverage event or replace its signature.
3. Missing, rejected, malformed or unmatched outcome produces `reversal_not_applied`/AL-10; pending work remains owned by the existing reversal runner. Completion: signing gate pause, lost reply and rejected void cannot pass solely because effect=tombstone; a verified nil tombstone does pass.

### R9-AO2 — P2: a partial refund can hide a different payout chargeback

`reconciliation/run.ts:400–428` accepts **any** reversal with the payout payment ID. Example: payment has one small refund, then a payout reports a full chargeback not recorded by callbacks/inquiry. The old refund satisfies the query and suppresses `unrecorded_reversal`, defeating A18's payout backstop. The imported line retains kind/gross, but this check selects neither; the adapter also drops its CSV transaction identity (`provider/paymob/adapter.ts:855–875`, port `119–126`). This does not re-report R6-BR2's inquiry population defect.

**Fix steps (code recipe ready; historical linkage requires evidence):**
1. Extend `ProviderPort.PayoutLine` and the Paymob normalization with an opaque adapter-owned reversal identity and positive normalized reversal amount for refund/chargeback lines. Keep raw provider IDs inside the adapter; expose a stable normalized reference, with no provider-specific parsing in reconciliation.
2. Add a forward immutable payout-line evidence/link record and corresponding fact/rebuild mapping, retaining original raw file/hash. After R6-BR1/BR3, match the normalized transaction/reversal identity, payment, kind and amount against the exact recorded reversal. An unrelated partial refund must never satisfy a chargeback. Unknown identities remain unmatched; do not synthesize a reversal or automatically void from a CSV.
3. Update `checkUnrecordedReversal` to use that exact mapping and retain `unrecorded_reversal` until a matching authoritative/manual reversal exists. Operator resolution remains an explicit audit disposition, not financial evidence.
4. Completion: partial refund followed by distinct full chargeback is detected; exact repeated payout evidence links to the same reversal without extra value. Maintainer/provider owner plus frontier reviewer must approve legacy CSV-to-reversal mappings from retained evidence; stop automatic legacy linkage when ambiguous, preserving findings and facts.

### R9-AO3 — P2: reconciliation ignores missing local copies

For a clinic with recent events, `checkFeedDivergence` returns early when `coverage_view` is absent (`run.ts:565–575`), so a lost/rejected local projection is never reported. Separately receipt comparison uses an inner join to `grant_request` (`614–619`); an applied outcome surviving a partial restore without its request is never examined, despite 085:1's every-outcome rule. The schema has no FK making that state impossible (`abo/migrations/0004_grant.sql:1–19`). These are credible restore/divergence states, not ordinary valid no-coverage cases.

**Fix steps (implementation-ready):**
1. For an org actually established by a recent valid feed event, treat an absent view as `feed_divergence`, retaining its epoch/sequence evidence; do not populate the view from a potentially compromised live read merely to hide the discrepancy. Apply R7-A1's monotonic repair separately.
2. Change the receipt query to LEFT JOIN. Explicitly known `source_kind='transfer'` remains excluded; a missing request is a receipt/lineage discrepancy requiring a finding, never implicitly a transfer. Include all other applied/already-applied outcomes and compare exact receipt objects as today.
3. Completion: deleting either local copy from a restored snapshot yields a durable finding/AL-10; known transfer receipts remain outside grant comparison; missing platform ledger and signature-only differences still fail.

### R9-AO4 — P2: a committed finding can permanently lose its AL-10

`run.ts:59–84` commits finding+fact, then separately calls `raiseAlert`. Interruption or a failed alert insert leaves the finding durable. Every retry sees `findingExists` (`46–56,65–67`) and returns before repairing the alert. A reconciliation failure can therefore have no immediate/repeating AL-10 even after DB recovery; only the digest exposes it. Concurrent runs can also insert duplicate `(kind,subject)` findings because only finding_id is unique.

**Fix steps (implementation-ready):**
1. Add a forward `finding_identity(kind,subject,finding_id)` unique registry, preserving existing immutable findings. Backfill a deterministic earliest detected-at/finding-id representative; retain all duplicate facts/resolutions, never delete them. New concurrent detections atomically claim that identity.
2. Make `insertFinding` prepare the finding, its fact and `AL-10:<finding_id>` alert INSERT in one D1 batch, conditional on the winning identity. Reuse a prepared alert-upsert helper from `alert/index.ts`; no remote email inside the batch.
3. For an existing unresolved identity, ensure its alert row exists without resetting successful delivery time. Batch resolution and alert deactivation per AO5; replay of resolved identities must not reopen a disposed finding.
4. Completion: failure before/after any former boundary yields either no finding or both finding and due alert; overlapping daily/import reconciliation produces one canonical finding identity; a historical unresolved finding lacking an alert gets one.

### R9-AO5 — P2: resolved conditions keep repeating as active alerts

After the first export-lag email, `clearExportLagWhenResolved` deliberately refuses to clear if `last_sent_at` is nonnull (`alert/index.ts:155–163`), so a repaired backlog repeats daily forever. Feed freshness and issuer/credential watch only raise (`watch/hourly.ts:65–90,93–173`); successful healthy comparisons never clear prior AL-15/AL-22. Finding resolution (`ops/index.ts:1880–1892`) never deactivates its AL-10; the sender repeats all active rows (`alert/index.ts:182–197,262–280`). A routine recovered outage/resolved incident remains in open alerts and email indefinitely, making genuine recurrence indistinguishable.

**Fix steps (implementation-ready):**
1. In `alert/index.ts`, expose a prepared clear operation. Clear export lag whenever the authoritative oldest pending fact is absent or no longer over one hour, regardless of prior send. Preserve last-sent audit metadata; active=0 and unsent=0 stop repeats.
2. In hourly watch, clear AL-15 after a successful valid fresh health result. Following complete successful issuer and credential reads, clear only previously active AL-22 keys whose exact mismatch no longer exists. A thrown/refused/malformed read is unknown and must not clear anything.
3. Batch `finding_resolution`+fact and AL-10 deactivation in `handlePostResolveFinding`; an identical retry returns the original disposition via R6-O1. Reactivation after a later genuine condition transition sets unsent once; apply no blanket clearing to once-only transition alerts, particularly AL-19.
4. Completion: recovery/explicit resolution stops repeats and open-alert listing, a recurrence sends again, and transport failures retain active alerts. This corrects condition state, not an exactly-once email promise.

### R9-AO6 — P2: invalid-HMAC retention ignores further R2 pages

`housekeeping/run.ts:32–41` performs one prefix list and ignores continuation. With more expired objects than fit in one response, a daily run deletes only its first page, so the 30-day rule fails; a sustained invalid-callback stream can grow the backlog faster than one page/day. The date/key filter correctly avoids commercial evidence, and that boundary must remain.

**Fix steps (implementation-ready):**
1. Iterate R2 list cursors in `runHousekeeping`, preserving the same cutoff and `hmac-invalid/` prefix; handle truncated pages until completed.
2. Keep work bounded per invocation using a persisted housekeeping cursor and deletion budget, with the next existing minute/daily schedule resuming pending cleanup until drained. Persist cursor only after its page's deletions finish; repeated deletion is harmless. Never widen the prefix to `evidence/`, `ledger/` or payouts.
3. Completion: multiple expired pages are eventually removed after interruption/retry, samples at/after the cutoff remain, and no commercial fact/raw verified evidence is removed. Do not equate one cron timestamp with cleanup completion.

### R9-AO7 — P2: malformed payout files become successful empty/partial imports

`ops/index.ts:1719–1732,1745–1798` stores/accepts whatever line array the adapter returns and assigns the current month to an empty result. `provider/paymob/adapter.ts:809–852` converts a wrong header to [], silently skips malformed rows and uses permissive parseInt; settled_at is unchecked. A wrong export or damaged row is therefore acknowledged as an imported period, and reconciliation consumes incomplete evidence. A mixed-month file is assigned only its first row's month, distorting period completeness. Raw bytes remain recoverable, so bounded P2.

**Fix steps (implementation-ready for this fixed CSV format):**
1. Change `payoutLines` to return a typed success/error result with exact line errors. Validate the fixed header, complete six-field rows, allowed kind, full-string safe integers and valid UTC settled_at; reject the entire file on any invalid row. An empty/header-only file cannot establish an imported period.
2. Require all parsed rows have the same UTC YYYY-MM; otherwise reject with an explicit split-file error. Derive period only from that validated month. Validate before R2/import mutation; use the existing invalid_request response/version convention and retain no accepted import/fact on failure.
3. Route the accepted import through R6-O1's stable command/file-hash identity so retry resumes the same import/audit rather than creating another import. Completion: wrong-header, partly corrupt, unsafe money, invalid date and mixed-month files fail without accepted import; a valid file commits all lines+facts atomically and exact retry returns the original result.

### R9-AO8 — P3: payout-import listing always returns an empty array

`ops/index.ts:1688–1695` returns literal `payout_imports: []`, reached by GET `/ops/payout-imports` (`3338–3339`), even after a successful import writes those rows. The operator cannot inspect the promised import history through this route.

**Fix steps (implementation-ready):**
1. Pass env to `handleGetPayoutImports` and query actual `payout_import` metadata, with deterministic period/import-id ordering and an explicit bounded page/cursor.
2. Return stored import ID, provider, file hash, period and actor under the existing versioned payload; preserve Access gating and keep raw CSV contents out of the list.
3. Completion: accepted imports appear once, empty DB alone returns [], and database failure cannot masquerade as successful empty history. Preserve immutable prior import identities.

## Coverage and remaining ownership

The machine coverage records every completed exact tuple and supporting ranges. Assigned-source review is closed, including digest/lock code where no new defect is raised. All relevant escalation dispositions are explicit there; out-of-slice rebuild/config/monitor effects remain named coordinator/sibling ownership, not falsely completed by this slice. No R10 integrated narrative was attempted.

No unresolved *new code design* prevents these bounded recipes. Historical payout linkage in AO2 remains not implementation-ready without explicit evidence approval; stop at unmatched findings rather than infer a refund/chargeback. Actual provider CSV variants, native email binding compatibility, account policies/locks, key custody, live monitor uptime and runtime scheduling are explicit source-only limits. The lead owns full R9 synthesis, escalation aggregation and tracker updates.
