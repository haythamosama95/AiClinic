# Stage 02 — Clinic keypair enrollment E2E report

**Declaration: GREEN (deferred)** — Worker E2E track has nothing in-scope; all IDs recorded as out-of-scope.

Stage 02 is entirely clinic-side Supabase (RPCs, keystore, availability flag, grants). There are zero automatable Worker HTTP journeys in this chapter. Per hard rule 7 of `docs/testing/ai-platform-e2e-implementation-prompt.md`, Supabase contract scenarios are a separate pgTAP / PostgREST track handled after Phase 15. This controller records S02-001 … S02-027 as out-of-scope and does not spawn writers.

Confirmation (chapter + Register 3.6): every action is `SELECT public.*` RPC, schema/RLS, GRANT, trigger, or `roles_permissions` — against `backend/supabase/migrations/`, not `ai-platform` Worker HTTP. No `stage-02-*.test.ts` files were created. No `it.skip` placeholders were added (these IDs are deferred-to-pgTAP, not Register 5 skips).

## 1. Chunk map

**None** (no writers). Entire ID range S02-001 … S02-027 is hard-rule-7 out-of-scope.

## 2. Writer outcomes

No writers spawned (hard rule 7). No Worker test files produced. No Register 5 `it.skip` rows added for these IDs.

## 3. Iteration count

**0** — no runner, no fixers, no vitest execution (`npx vitest run --config vitest.e2e.config.ts test/e2e/stage-02-*` was not run; there is no such suite).

## 4. Passing / skipped / failing

**N/A** (no Worker suite for this stage).

| | Count |
|---|---|
| Passing | N/A |
| Skipped (Register 5) | N/A — do not treat as Register 5 |
| Failing | N/A |
| Test files | 0 (none created) |
| Out-of-scope IDs | 27 (S02-001 … S02-027) |

## 5. Out-of-scope ID list (S02-001 … S02-027)

Each ID is a Supabase contract (pgTAP / PostgREST after Phase 15), not an `ai-platform` Worker HTTP journey.

| ID | Reason |
|---|---|
| S02-001 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `public.get_ai_availability()` seeded default jsonb |
| S02-002 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `anon` GRANT denial (42501) on availability + enroll |
| S02-003 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `rotate_installation_key` empty-keystore `INSTALLATION_NOT_ENROLLED` |
| S02-004 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — enroll as doctor `FORBIDDEN` |
| S02-005 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — rotate as doctor `FORBIDDEN` (role check before empty-keystore) |
| S02-006 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — revoke as doctor `FORBIDDEN` (role check before blank-kid) |
| S02-007 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — enroll as deactivated administrator `FORBIDDEN` |
| S02-008 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — enroll with no staff row `FORBIDDEN` |
| S02-009 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — first `enroll_installation_keypair` mints I0/K0 |
| S02-010 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `ai_internal.installation_keys` schema REVOKE + deny-all RLS |
| S02-011 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — enroll does not write `ai.availability` |
| S02-012 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — second enroll `ALREADY_ENROLLED` |
| S02-013 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `rotate_installation_key` happy path (K1 under I0) |
| S02-014 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `revoke_installation_key(K0)` happy path |
| S02-015 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — re-revoke already-revoked kid is idempotent |
| S02-016 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — blank/whitespace kid `INVALID_INPUT` |
| S02-017 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — unknown kid `KEY_NOT_FOUND` |
| S02-018 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — soft-deleted kid `KEY_NOT_FOUND` |
| S02-019 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — last active key `CANNOT_REVOKE_LAST_ACTIVE_KEY` |
| S02-020 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — rotate K2 then revoke K1 |
| S02-021 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `enforce_single_installation` trigger `SINGLE_INSTALLATION_VIOLATION` |
| S02-022 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — recovery re-enroll reuses I0 |
| S02-023 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — rotate succeeds when all keys revoked but rows exist |
| S02-024 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `set_ai_availability` / `get_ai_availability` flag flip |
| S02-025 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — COALESCE default when availability row missing/soft-deleted |
| S02-026 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `roles_permissions` `ai.visit_summary` grant matrix |
| S02-027 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — enroll payload reconstruction for Stage 3 handoff |

## 6. Conflicts / harness gaps

None (not executed). No Worker tests were written or run, so no catalog-vs-code conflicts and no harness gaps were observed on this track.

## 7. Remaining failures

None.

## 8. Phase 15 coverage-audit note

**Phase 15 coverage audit must treat S02-001 … S02-027 as deferred-to-pgTAP, not as Worker-suite gaps, and not as Register 5 skips.**

- Missing `test("S02-…")` names under `ai-platform/test/e2e/` are expected and correct.
- Missing `it.skip("S02-…")` rows are expected and correct (Register 5 is a DO-NOT-IMPLEMENT list for Worker seams; these IDs are a different track).
- Do not spawn gap-fixers to add Worker tests or Register 5 skips for this chapter.
- Coverage for these IDs belongs to the post–Phase 15 pgTAP / PostgREST suite against `backend/supabase/migrations/`.
