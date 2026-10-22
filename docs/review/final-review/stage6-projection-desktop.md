# Stage 6 Final Review — Projection and Desktop State (RM36–RM38)

Second-round light-pass review of `ai/abo-remediation` against `master`. Branch tip `6cae8104`. That
commit is docs-only. No code changed after the RM38 record commit `9dd67db8`.

## 1. Summary

- RM status: 3 HANDLED (RM36, RM37, RM38), 0 PARTIAL, 0 NOT HANDLED, 0 REGRESSED.
- Requirements checked: 13. All 13 are HANDLED.
- Critical findings: 0. Major findings: 0.
- Verdict: **PASS**.

The RM36 record describes R7-A1 as "projected coverage snapshot at egress". That description is wrong.
The code at the tip does implement the actual R7-A1 recipe: the epoch/sequence predicate sits in the D1
upsert, and the page and cursor commit in one batch. The egress projection was added on top of that.
This is a documentation error only.

## 2. Phase verification

| RM | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| RM36 | R7-A1: the D1 upsert enforces `(binding_epoch, clinic_seq)` order; validated upserts and a cursor that only moves forward commit in one batch; a rejected event stops the cursor | HANDLED | `abo/src/coverage/view.ts:25-37` (predicate SQL and `MAX` cursor); `:133-167` (one `DB.batch`; cursor stops at the last accepted event) |
| RM36 | R7-A2: history names come from the payment's immutable `(offer_id, offer_version)`; no catalogue or terms R2 dependency; a missing version raises a diagnosis, not an invented name | HANDLED | `abo/src/clinic-api/billing-reads.ts:247-274` (`LEFT JOIN offer_version`); `:149-170` (`offer_malformed` alert, null name); `:314` |
| RM36 | R7-PS2: state `none` when no term was ever applied; `exhausted` and `transferred` reasons set; the special-case `active` on reads removed | HANDLED | `ai-platform/src/quota-do/coverage.ts` (commit `7b1673b3`: transferred reason ~684, `terms.length === 0` → none ~728, exhausted reason ~736, `snapshot.state = "active"` removed from `readCoverageRPC` ~2568) |
| RM36 | R7-PS3: one conditional `INSERT ... ON CONFLICT DO UPDATE WHERE requested_at <= now()-10s`; `RATE_LIMITED` with no pull when nothing is claimed; role, session and version behaviour kept | HANDLED | `backend/supabase/migrations/20261022130000_rm36_status_refresh_claim.sql:22-57` |
| RM36 | R7-PS4: `allowSuspended` only on the coverage read; administrator role still required | HANDLED | `ai-platform/src/coverage-read/index.ts:127-129` and `:144`; test `ai-platform/test/system/fallback-feed-coverage.system.test.ts:879` |
| RM36 | Egress projection (RM32 seam) on the feed, `getCoverage`, `readCoverageEvents` and the coverage read | HANDLED | `packages/vendor-contracts/src/coverage-snapshot.ts:131-153`; `ai-platform/src/worker.ts:2745`; `ai-platform/src/vendor/entrypoint.ts:6823,6903,7038`; `ai-platform/src/coverage-read/index.ts:184` |
| RM37 | R7-UI1: the live host is keyed by user, org, role and visit identity; inputs are captured before the first await | HANDLED | `frontend/lib/features/ai/presentation/pages/ai_page.dart:365-398` (identity); `:519-522` (`ValueKey`); `:797` |
| RM37 | R7-T1: one identity-scoped shell status with a refresh generation; transient failure keeps the data but marks it stale; update-required outcome; the open host applies live status and keeps a denial | HANDLED | `frontend/lib/app/providers/ai_shell_status_provider.dart:54-129`; `frontend/lib/features/ai/host/ai_feature_host_page.dart:159-204` (`_applyLiveStatus`); `:496` (denial kept); `:582` (no auto-invoke on a status remount); `ai_page.dart:821-825` |
| RM37 | R7-T2: decode `snapshot.term`; reference kept with no term; nullable figures; missing snapshot treated as malformed; administrator gate before commit | HANDLED | `frontend/lib/core/ai/usage_summary_client.dart:81-99`; `ai_feature_host_page.dart:319-323` and `:388-400`. Projected `TERM_KEYS` keep `used`, `allowance` and `plan_display_name` (`coverage-snapshot.ts:27-36`) |
| RM37 | R7-T3: stateful UTF-8 decoding across chunks; failure surfaces once | HANDLED | `frontend/lib/core/ai/https_submit_port.dart:132-189` (`utf8.decoder` plus `LineSplitter`; `_fail` guarded by `_closed`) |
| RM37 | R2-C3 step 2: Dart adapters check the echoed version; the mint port checks the `ver` claim (recorded deviation) | HANDLED | `frontend/lib/core/contract_version_guard.dart:30-59`, used by 8 adapters; `frontend/lib/core/ai/supabase_aat_mint_port.dart:28-64`. The `/v1/coverage` header is set by `withAipContractVersion` (`ai-platform/src/vendor/contract-version.ts:39-44`, route `worker.ts:2932`) |
| RM38 | R7-UI2: checkout callback; one billing generation; siblings guarded by generation; history resets; refresh control; at most 4 rereads 30 s apart from the pull request; checks for identity, epoch and step; no checkout mutation | HANDLED | `frontend/lib/features/ai/billing/administrator_billing_page.dart:29-30`, `:220-292` (chain), `:309-318` (pull, R2-C3 check), `:333-361`; `frontend/lib/features/ai/billing/payment_history.dart:44-113` (sequence and generation guards) |
| RM38 | R7-UI3: en/ar keys for 8 status and 5 commercial codes; `in_grace` days placeholder with `=0` read as less than a day; neutral text for unknown codes; no wire codes printed | HANDLED | `frontend/lib/features/ai/host/ai_feature_host_page.dart:728-751`; `frontend/lib/features/ai/billing/commercial_notices.dart:137-145`; `frontend/lib/l10n/app_en.arb:171-203`, `app_ar.arb:171-203` |

## 3. Critical findings

None.

## 4. Major findings

None. No Critical or Major defect was observed in the code read for this pass.

## 5. Could not verify

- **RM38 fullstack test not run by CI.** E2E-P6.4-01 to -05 in
  `frontend/test/integration/administrator_subscription_fullstack_test.dart` are globally `@Skip`ped, and no
  CI campaign runs them. The RM38 change to E2E-P6.4-02 is unverified, as RM38.md item 7 already records.
- **R7-PS3 concurrency.** Only sequential tests exist. The single-statement claim looks correct by reading,
  but no concurrent test proves it.
- **R7-UI2 resumed checkout.** A checkout that is already Active when the page opens (`initialCheckout`)
  does not request the projection pull (RM38 F5 second part, documented follow-up). The page's first reads
  still load fresh data, so this was not raised as Major.
- **Downstream handling of `none` and stricter projected snapshots.** I did not trace how the backend notice
  derivation and the Dart status reader treat the new `none` state, or how they treat a snapshot that no
  longer has extra keys. No `CHECK` constraint on state exists in backend migrations, and CI is green.
- **PS4 cached-suspension case.** I did not trace the isolate cache behaviour after resume, beyond the
  `allowSuspended` flag and the system test name at `fallback-feed-coverage.system.test.ts:879`.
