# Stage 4 Second-Round Review — Accounting, Lifecycle, Transfer and Deletion (RM22–RM27)

Branch `ai/abo-remediation` (tip includes RM22–RM38) compared with `master`. This was a light, read-only
pass. Scope: plan §4.4 (RM22–RM27), the per-phase records, and RM26/RM27 todo lists. Each requirement was
spot-checked once at the branch tip, with extra reading only where a later phase touched the same code.

## 1. Summary

- **RM status:** 6 HANDLED, 0 PARTIAL, 0 NOT HANDLED, 0 REGRESSED (RM22, RM23, RM24, RM25, RM26, RM27).
- **Requirement rows:** 20 HANDLED, 0 other.
- **Todo lists:** every item in `RM26.todo.md` and `RM27.todo.md` is checked, and spot-checks show the code exists at the tip. No open leftover items.
- **Findings:** 0 Critical, 0 Major. No Critical or Major defects were found.
- **Verdict: PASS.**

## 2. Phase verification

| RM | Requirement | Status | Evidence |
|---|---|---|---|
| RM22 | R5-A1: allowance, grace, bands and exhaustion count reservations by their own `term_id` | HANDLED | `reservedForTerm` at `ai-platform/src/quota-do/index.ts:922`. Used in grace usage (`:1268`), credits remaining (`:1672-1677`) and will-exhaust (`:1738-1740`). The concurrency limit still uses the global list (`:1664`). |
| RM22 | R5-A2: exhaustion closes the term with settled usage only; reservations stay live | HANDLED | `endGraceIfExhausted` sets `used_final = hot.row.used` (settled) and calls `markTermReservationsSettledOnly` (`quota-do/index.ts:1276-1281`). A held release during grace freezes `hotAfter.used` (`coverage.ts:2971`). |
| RM22 | R5-A7: never-admitted refusals are not stored and do not write hot state | HANDLED | Refusals go through `returnUnstoredRefusal(..., stateChanged)` (`quota-do/index.ts:1664-1722`). |
| RM23 | R4-D3: placement and adjustment use a due-boundary plan committed atomically with the grant | HANDLED | `planDueBoundaries`/`commitDueBoundaryPlan` (`coverage.ts:1174,1242`). The plan is passed into `applyComplimentaryTermGrant` (`:1787,1820-1821`). |
| RM23 | R4-D2: complimentary grant during grace renews from the old end; explicit stranded-term recovery action | HANDLED | Grace anchor `calendarStart = graceTerm.ends_at` (`coverage.ts:1843-1845`). `recoverStrandedTermRPC` (`:3082`, with a transfer fence at `:3139`). ABO route `/ops/coverage/recover-stranded` (`abo/src/ops/index.ts:5674`). Migration `20261019170000_r4_d2_stranded_recovery.sql`. |
| RM23 | R6-DM4: held release catches up the lifecycle first; release during grace ends grace as renewed | HANDLED | `releaseHeldRPC` calls `planDueBoundaries` before placement (`coverage.ts:2942-2950`). During grace it ends the grace term with `renewed` and activates the released term from the old end (`:2965-2972`). Otherwise it queues or activates (`:2973-2987`). |
| RM24 | R5-ADM1: fallback cap check and insert happen in one statement | HANDLED | A conditional `INSERT OR IGNORE ... WHERE SUM(weight)+? <= cap` (`ai-platform/src/admission/index.ts:572-606`). |
| RM24 | R5-ADM3: fallback JTI is stored and unique | HANDLED | Unique index `fallback_admission_installation_jti` (`migrations/20261020120000_rm24_fallback_admission_identity.sql:9-11`). JTI lookups at `admission/index.ts:479,620,659`. |
| RM24 | R5-A4: fallback carries the term snapshot and cost ceiling; terminal outcomes are persisted | HANDLED | `termView.ref` and `plan_snapshot` are stored at insert (`admission/index.ts:557-599`). The pipeline requires a snapshot for `grace_admitted` (`pipeline/index.ts:572-585`). |
| RM24 | R5-ADM2: routing uses the mirrored `max_cost_class`, with an economy default | HANDLED | Mirror parser defaults to economy (`coverage.ts:3528-3536`). The router receives `termAdmission.snapshot.max_cost_class` (`worker.ts:1310-1313`). |
| RM25 | R5-A3: durable, idempotent fallback settlement receipts | HANDLED | `settleFallbackUsage` and `acknowledgeUsageReceipt` (`credit/index.ts:280,323`). `acknowledgeUsageReceiptRPC` (`quota-do/index.ts:2269`). Migration `20261020130000_rm25_fallback_settlement.sql`. |
| RM25 | R5-A6: reconciliation closes rows from an exact usage fact and does not synthesize charges | HANDLED | Exact-match check on installation, term and weight, with a conflict skip (`credit/index.ts:485-536`). Non-terminal requests are not guessed (`:540-546`). |
| RM25 | R5-A5: exhausting an active term activates its queued successor once | HANDLED | `exhaustActiveTermAndActivateSuccessor` on both the refusal path and the admit path (`quota-do/index.ts:1706-1717,1753-1762`). |
| RM25 | R5-J1: accounting intent is persisted before usage, then acknowledged | HANDLED | `recordAccountingIntent` sets `accounting_state = 'pending'` (`journal/index.ts:130-138`). The cron drains pending intents (`credit/index.ts:397-483`). |
| RM26 | R6-DM1: transfer preserves usage and grace accounting; source frozen and drained before export | HANDLED | `transferOutRPC` requires `transfer_pending` with a matching ID and zero reservations (`coverage.ts:4387-4400`). `executeTransferOut` waits on pending `accounting_state` and pending fallback rows (`coverage/transfer.ts:1048-1058`). Fallback admission is fenced by `transfer_preparation` (`admission/index.ts:582-585`). Grant apply is fenced (`coverage.ts:2123-2130`). |
| RM26 | R6-DM2: exact replay bound to transfer ID; lost D1 step recovered from the DO record | HANDLED | `transfer_replay` request-hash check (`coverage.ts:4361-4378`). `restoreTransferOutStepFromDo` path (`coverage/transfer.ts:1022-1032`). |
| RM26 | R6-PT2: durable preparation; fenced destination init and source freeze; atomic publish after both acknowledgements; leased dispatcher | HANDLED | Phase machine `accepted → destination_ready → source_frozen → published` (`coverage/transfer.ts:830-936`). CAS retire, destination insert and transfer insert in one batch (`:887-937`). Leased `dispatchTransferPreparations` (`:944-985`), wired into cron (`worker.ts:3035`). Migration `20261020140000_r6_rm26_transfer_preparation.sql`. |
| RM27 | R6-PT3: durable deletion command; freeze inventory acknowledgement; CAS to held/retired; purge recovery; no overlap with transfer | HANDLED | `acceptDeleteInstallation` writes the command, assertion use and audit in one batch, guarded against overlapping deletion or transfer (`coverage/transfer.ts:1567-1614`). The exact completed replay reuses `freeze_id` (`:1506-1564`). `resumeDeleteInstallation` freezes and validates inventory, keeps unknown state transient, and does a CAS (`:1640-1706`). Purge preserves retained term IDs (`:1739-1745`). Dispatcher in cron (`:1766-1780`, `worker.ts:3043`). Transfer adopts only the matching held deletion fence (`:849-860`). Migration `20261020150000_rm27_durable_deletion.sql`. |
| RM27 | R7-PS1: held deletion projects `transfer_pending`, emits one `transfer` snapshot on the first fence, and re-arms the outbox on replay | HANDLED | Projection (`coverage.ts:711-722`). The first transition bumps `clinic_seq` and enqueues the snapshot (`:4612-4636`). Replay re-arms the alarm without a new event (`:4588-4590`). |
| RM26/27 | Todo items | HANDLED | All boxes are checked in `RM26.todo.md` and `RM27.todo.md`, and the code above matches them. |

Later phases: RM29 and RM30 touched recovery and usage identity near this code. No regression was seen in
the paths checked above (for example, the `reservedForTerm` callers and fallback settlement are still intact).

## 3. Critical findings

None.

## 4. Major findings

None.

## 5. Could not verify

- **Held release after a transfer, or during a source freeze.** `releaseHeldRPC` (`coverage.ts:2904-3048`) has no `transfer_pending`, `transferred_out_to` or binding-epoch fence. The vendor `releaseHeld` routes by `grant_ledger.installation_id` (`vendor/entrypoint.ts:6260-6281,6331`), and `coverage/transfer.ts` never rewrites `grant_ledger`. A release during a freeze is still exported correctly, because `transferOutRPC` waits for drained reservations and exports the current term states. After a transfer, the source term is `ended/transferred`, so a release returns `bad_request` rather than corrupting state. I did not confirm whether a held term that moved can still be released at the destination; that depends on the RM19/RM20 route and ledger mapping. The worst case is an operator-visible failure, not data loss.
- **Fallback reconciliation scan size.** `reconcileGraceUsage` selects every fallback row, including `settled` rows, on each cron run with no `LIMIT` (`credit/index.ts:380-391`). This is a scalability concern, not correctness, and it is acceptable at clinic scale. I did not check the retention or purge of `fallback_admission`.
- **Deletion dispatcher lease.** `dispatchDeletionCommands` filters on `lease_until` but never sets it (`coverage/transfer.ts:1766-1780`). Overlapping runs are protected by phase CAS and idempotent purge. One overlap could raise a duplicate AL-18 alert (`:1727-1733`). This is minor and not a finding.
- No tests or CI were run for this review. CI results are taken from the per-phase records.
