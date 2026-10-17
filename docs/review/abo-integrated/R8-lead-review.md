# R8 lead — registry, policy and support seams

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; GPT-6.1 Sol explicitly high, `/root/abo_r8_review`. All 62 assigned tuples / 1,214 lines read; [exact coverage](R8-lead-coverage.json). Source at newer workspace HEAD was excluded. Static evidence only, no execution or fixes. Canonical report controls final numbering/counts.

## R8-KEY1 — P1: issuer retirement can restore a revoked key

High confidence; implementation-ready. `ai-platform/src/vendor/entrypoint.ts:2393–2428` reads status, permits active, awaits `finishHpAssertion`, then unconditionally updates `status='retiring'` by kid. Concurrent `revokeIssuerKey:2507–2512` can set revoked after the retirement's read but before that write. Retirement then overwrites revoked. `identity/index.ts:226–237,470–482` accepts retiring keys through their validity; the ordinary config TTL does not repair persistent resurrection. An emergency revocation overlapping routine rotation can therefore restore a compromised issuer's ability to mint tenant AI tokens until expiry. This is independent of R1-C3 malformed validity and R2's approval verification.

**Fix steps**
1. In `retireIssuerKey`, make the mutation `UPDATE issuer_key SET status='retiring' WHERE kid=? AND status='active'`. Never write retiring from a stale application read alone. Re-read the resulting row: revoked must return `kid_revoked`; already retiring remains idempotent success; absent remains `kid_not_found`.
2. Compose the guarded transition with R8-AUDIT1's local D1 transition audit; an audit must describe only the state change actually won. Retain revocation as a terminal state and same-key registration's existing no-status-reset behavior. Do not expand credential or service-key states.
3. Completion: for either interleaving of retire and revoke, once revoke completes the final status remains revoked; verifier cache refresh refuses that kid. Routine active→retiring and repeated retirement continue to work. Historical revoked-then-retiring cases require audit review and explicit re-revocation, not automatic key resurrection.

## R8-CEILING1 — P2: simultaneous policy changes collide after approval consumption

High confidence; implementation-ready. `entrypoint.ts:3071–3100` reads greatest policy version and computes next in application code. Different approved requests can read the same current value; both consume their distinct assertions before the primary-key insert. One then fails storage instead of appending its policy, and its original retry is refused as used (`1253–1258`). This is a separate version-allocation cause, with the shared consumed-approval recovery limit inherited from R4-PG3 rather than recounted.

**Fix steps**
1. In `setCeilingPolicy`, allocate and insert the next version inside one serialized D1 write using `INSERT ... SELECT COALESCE(MAX(version),0)+1, ... FROM ceiling_policy`, rather than carrying a previously read nextVersion.
2. Integrate that insert, assertion claim and transition audit with the accepted-command/atomic D1 mechanism prescribed by R4-PG3 and R8-AUDIT1. Forward-migrate ceiling_policy_command with challenge_sha256 primary key, unique policy_version, actor, operation_json, contract_version and result_json; leave historical policy rows and the empty seed challenge untouched. Allocate the new command/version, policy, claim and audit in one batch. Exact accepted retries compare canonical bytes/actor and return the originally allocated row; ambiguous historical replays remain read-only/refused pending evidence.
3. Completion: two independent authorized updates serialize into distinct consecutive versions, the greatest is effective, and failure does not strand an approval or create another version on an exact retry. Do not rewrite historical policy facts.

## R8-SUPPORT1 — P2: clinic lookup loads all history and payload objects in one request

High confidence; implementation-ready; bounded resource risk. `ai-platform/src/support/index.ts:114–124,314–343` has no row/time/page limit, joins every attempt, materializes the entire installation history and sequentially fetches a retained R2 envelope for each request. Org/subscription input is available on the public service-binding method (`entrypoint.ts:5077–5095`). A clinic with modest daily use accumulated across the retained journal horizon makes a single support request scale with every journal row and every recent payload, affecting the diagnostic operation precisely when it is needed. No live platform limit or measured timeout is asserted.

**Fix steps**
1. Extend org/subscription lookup with `limit` (default 50, integer 1–100) and a keyset cursor `(created_at,request_id)` descending; page request IDs before joining attempts so one request's attempts cannot split across pages. Return explicit `next_cursor` and `has_more`.
2. Return request/attempt metadata in the page; fetch payload envelopes only through the existing exact-reference lookup. Preserve the same Access and retention gates and deterministic order. Roll out the receiver's additive page metadata before any producer requests subsequent pages; no current org-list console consumer exists at T.
3. Completion: each list request reads at most the selected page's request/attempt rows and no R2 payloads; exact reference still returns only its eligible payload; paging neither skips nor duplicates rows with equal timestamps. Transfer/deletion diagnostic reachability retains existing semantics rather than claiming historical binding reconstruction.

## Established lifecycle and support limits

Operator registration inserts pending for 24 hours; only guarded pending→active updates in platform HP checks/list promote it. Revoked credentials stay revoked under those promoters. Existing credential ID/key replays do not reset status. The approved-by field intentionally records the Access actor, not another email; amended R2 contract does not require credential-owner-email equality. Bootstrap emptiness race remains canonical R2-P3. Platform validates each HP operation's exact field map; local URL binding/second ceiling assertion remain R2-P1/P2. Missing browser producer remains R2-P4; no rendered form is claimed.

Issuer register/retire/revoke and service register/revoke validate Access and HP, preserve same-key status/validity, and emit AL-13 after mutation. Issuer malformed validity remains R1-C3. Service verification rejects malformed/outside validity and revoked keys; unknown service kid is transient. ABO grants re-sign the original stored envelope bytes with the current key (`abo/src/work/grant.ts:746–765`), while its signing gate accepts only active valid listed keys (`239–289`); no key-rotation envelope rewrite was established. Registry audit/alert crash recovery must compose with prior accepted-command remedies and R9 alert delivery, without counting that same shared root again.

Plan publication compares immutable content and same-content replay does not republish retired policy; retirement changes only status. Existing terms retain their snapshot (R4). Ceiling row fields/greatest version map to grant consumers; R4-D5 remains the per-org history limitation and R2-P2 the second approval defect. `recordOperatorAction` implements the 081 action-ID/target contract; console input reuse is R8-CONSOLE3, with inherited R6-O1 delivery recovery.

Support payloads contain filtered context, prompt, attempt raw bodies and validated result (`journal/index.ts:79–84,187–194`). Live operator Access is deliberately allowed this visibility by amended AD-8, not an isolation bypass. The retention resolver gates R2 payloads by capability horizon (`retention/index.ts:62–93`); metadata remains journal-retained. Support service method drops the verified email and never audits the read (`entrypoint.ts:5072–5125`); this confirmed site is folded into canonical R8-AUDIT1. Inspect has the explicit 081:3 audit exception and is not counted as missing audit.

R9 owns export/rebuild/alert delivery, deployed environment configuration and historical fact adjudication. No operational attestation or runtime reproduction follows from these source traces.

## Targeted R6 retry handoff closure

### R8-RETRY1 — P2: parked reversals have no operator retry path

`abo/src/ops/index.ts:1971–1977` rejects every retry whose work kind is not grant. Reversal processing parks reverse rows after rejected/conflict or unverified receipts (`work/reversal.ts:771–795,824–853`); its lease accepts open only (`914–921`). Even after correcting a signing/receipt configuration problem, the operator sees parked reverse work but retry returns not_found. This closes the explicit R6 handoff; it is distinct from R4's successful-grant outcome conflict and R6's accepted-action durability.

**Fix steps**
1. In handlePostRetry allow existing parked grant or reverse work, preserving work_id, kind, subject_id and dedupe identity. Use a guarded parked→open update and batch its ABO action/accepted-command fact; concurrent/finished work must not be reopened from a stale SELECT. Preserve the existing Access H check and platform audit delivery through R6-O1.
2. For reverse dispatch persist the exact canonical accepted void request bytes/version before first send in a new reversal_request row keyed by reversal_id (grant_id,reason,evidence_sha256,partial,contract_version,canonical_body,body_sha256). Reuse those bytes on retry, re-signing only with the current key; accept no replacement value/target/evidence fields from the retry request. Inherit R6/R4 receipt identity validation. Legacy parked rows without recoverable original bytes require maintainer/frontier evidence or explicit refusal, never recomputation from changed values.
3. Complete when an authorized retry of a recoverable parked reversal resumes its original mutation or obtains its original receipt, changed-payload recovery is impossible, partial/conflicting evidence stays review-only, and finished/leased work cannot be silently reopened. No new reversal or grant identity is generated.


This supporting expansion closes the named R6 handoff only; adjacent R9 payout/finding source incidentally displayed by an initial navigation range was not analyzed or used as correctness evidence.
