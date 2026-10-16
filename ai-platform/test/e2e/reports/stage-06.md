# Stage 06 — Minting an AAT E2E report

**Declaration: GREEN (deferred)** — Worker E2E track has nothing in-scope; all IDs recorded as out-of-scope.

Stage 06 is entirely clinic-side Supabase (`public.issue_ai_token`, `auth_internal.verify_aat`, PostgREST GRANT/session contract). There are zero automatable Worker HTTP journeys in this chapter. Per hard rule 7 of `docs/testing/ai-platform-e2e-implementation-prompt.md`, Stage 6 as a whole is a separate pgTAP / PostgREST track handled after Phase 15. This controller records S06-001 … S06-047 as out-of-scope and does not spawn writers.

Confirmation (chapter): every S06-001 … S06-040 action is `SELECT public.issue_ai_token()`, `SELECT auth_internal.verify_aat(...)`, GRANT/REVOKE, JWT claim injection, or `ai_internal` ledger/keystore/settings reads — against `backend/supabase/migrations/`, not `ai-platform` Worker HTTP. S06-041 … S06-047 are minted-then-rejected journeys whose clinic-side mint is this chapter's source of truth; their platform-half identity probes are still deferred with Stage 6 (not Worker-suite work in this phase). No `stage-06-*.test.ts` files were created. No `it.skip` placeholders were added (these IDs are deferred-to-pgTAP, not Register 5 skips).

## 1. Chunk map

**None** (no writers). Entire ID range S06-001 … S06-047 is hard-rule-7 out-of-scope.

## 2. Writer outcomes

No writers spawned (hard rule 7). No Worker test files produced. No Register 5 `it.skip` rows added for these IDs.

## 3. Iteration count

**0** — no runner, no fixers, no vitest execution (`npx vitest run --config vitest.e2e.config.ts test/e2e/stage-06-*` was not run; there is no such suite).

## 4. Passing / skipped / failing

**N/A** (no Worker suite for this stage).

| | Count |
|---|---|
| Passing | N/A |
| Skipped (Register 5) | N/A — do not treat as Register 5 |
| Failing | N/A |
| Test files | 0 (none created) |
| Out-of-scope IDs | 47 (S06-001 … S06-047) |

## 5. Out-of-scope ID list (S06-001 … S06-047)

Each ID is a Supabase issuer / `verify_aat` / PostgREST contract (pgTAP / PostgREST after Phase 15), or a minted-then-rejected journey deferred with the rest of Stage 6 — not an `ai-platform` Worker HTTP journey in this phase.

| ID | Reason |
|---|---|
| S06-001 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `anon` GRANT denial (42501) on `public.issue_ai_token` |
| S06-002 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — authenticated without JWT claims `UNAUTHENTICATED` |
| S06-003 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — expired clinic session JWT `SESSION_EXPIRED` |
| S06-004 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — auth user with no staff row `STAFF_NOT_FOUND` |
| S06-005 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — deactivated staff `STAFF_NOT_FOUND` |
| S06-006 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — soft-deleted staff `STAFF_NOT_FOUND` |
| S06-007 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — bootstrap admin before clinic setup `BRANCH_NOT_FOUND` |
| S06-008 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — staff with no branch assignment `BRANCH_NOT_FOUND` |
| S06-009 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — only branch inactive `BRANCH_NOT_FOUND` |
| S06-010 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — mint before enroll `INSTALLATION_NOT_ENROLLED` |
| S06-011 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — only key revoked `INSTALLATION_NOT_ENROLLED` |
| S06-012 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — only key soft-deleted `INSTALLATION_NOT_ENROLLED` |
| S06-013 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — per-actor ceiling boundary `RATE_LIMITED` |
| S06-014 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — rate ceiling per actor, not per installation |
| S06-015 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — ledger rows older than window excluded from count |
| S06-016 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — rate check fires before scope check |
| S06-017 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — role with no `ai.*` grant `AI_ACCESS_DENIED` |
| S06-018 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — revoked `ai.*` grant `AI_ACCESS_DENIED` |
| S06-019 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — doctor happy-path `issue_ai_token` compact JWS + ledger |
| S06-020 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — administrator scopes sorted from `roles_permissions` |
| S06-021 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — caller `p_scopes` subset ignored |
| S06-022 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — caller-supplied missing/bogus scopes ignored |
| S06-023 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — caller empty `p_scopes` ignored (does not trip `AI_ACCESS_DENIED`) |
| S06-024 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — branch claim is primary active (`ORDER BY is_primary DESC, name`) |
| S06-025 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — successive mints unique `jti`, stable identity claims |
| S06-026 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — missing `app_settings` rows fall back to built-in defaults |
| S06-027 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — post-rotation mint on K1; `verify_aat` still accepts K0 token |
| S06-028 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — post-revoke mint on K1; `verify_aat` rejects K0 token |
| S06-029 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — recovery re-enroll reuses I0 then mint succeeds |
| S06-030 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `ver` claim from `ai.aat.ver` |
| S06-031 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `aud` claim from `ai.aat.audience` |
| S06-032 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `exp − iat` exactly 600 s from `lifetime_minutes` |
| S06-033 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — non-numeric rate ceiling uncoded `22P02` cast error |
| S06-034 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — clinic `verify_aat` accepts freshly minted token |
| S06-035 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `verify_aat` rejects tampered payload |
| S06-036 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `verify_aat` rejects malformed tokens without throwing |
| S06-037 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `verify_aat` rejects `alg ≠ EdDSA` or missing `kid` |
| S06-038 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `verify_aat` rejects unknown and revoked kids |
| S06-039 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `verify_aat` rejects `iss` not matching key installation |
| S06-040 | Out-of-scope Supabase contract (pgTAP / PostgREST after Phase 15) — `verify_aat` does not evaluate `exp` |
| S06-041 | Deferred with Stage 6 (hard rule 7) — minted-then-rejected wrong audience; clinic mint is chapter SoT; platform-half identity probe not Worker-suite work this phase |
| S06-042 | Deferred with Stage 6 (hard rule 7) — minted-then-rejected expired AAT; clinic mint is chapter SoT; platform-half identity probe not Worker-suite work this phase |
| S06-043 | Deferred with Stage 6 (hard rule 7) — default lifetime within platform cap; clinic mint is chapter SoT; platform-half identity probe not Worker-suite work this phase |
| S06-044 | Deferred with Stage 6 (hard rule 7) — minted-then-rejected kid unknown to platform; clinic mint is chapter SoT; platform-half identity probe not Worker-suite work this phase |
| S06-045 | Deferred with Stage 6 (hard rule 7) — minted-then-rejected kid revoked platform-side; clinic mint is chapter SoT; platform-half identity probe not Worker-suite work this phase |
| S06-046 | Deferred with Stage 6 (hard rule 7) — minted-then-rejected `ver` unknown/retired platform-side; clinic mint is chapter SoT; platform-half identity probe not Worker-suite work this phase |
| S06-047 | Deferred with Stage 6 (hard rule 7) — minted-then-rejected installation unknown to platform; clinic mint is chapter SoT; platform-half identity probe not Worker-suite work this phase |

S06-041 … S06-047 platform-half identity probes remain deferred with Stage 6. They are not Worker-suite work in this phase: do not implement them as Stage 8/9 Worker tests here, and do not add Register 5 skips for them.

## 6. Conflicts / harness gaps

None (not executed). No Worker tests were written or run, so no catalog-vs-code conflicts and no harness gaps were observed on this track.

## 7. Remaining failures

None.

## 8. Phase 15 coverage-audit note

**Phase 15 coverage audit must treat S06-001 … S06-047 as deferred-to-pgTAP, not as Worker-suite gaps, and not as Register 5 skips.**

- Missing `test("S06-…")` names under `ai-platform/test/e2e/` are expected and correct.
- Missing `it.skip("S06-…")` rows are expected and correct (Register 5 is a DO-NOT-IMPLEMENT list for Worker seams; these IDs are a different track).
- Do not spawn gap-fixers to add Worker tests or Register 5 skips for this chapter — including S06-041 … S06-047 platform-half identity probes.
- Coverage for these IDs belongs to the post–Phase 15 pgTAP / PostgREST suite against `backend/supabase/migrations/`.
