# Tasks: Installation keystore and AAT issuer

**Input**: Design documents from `specs/021-installation-keystore-aat-issuer/`

**Prerequisites**: `plan.md` (required), `spec.md` (required). No prior AI-platform slice is a prerequisite — B1's `Needs` cell is empty. The external dependency (existing clinic RBAC tables) is already merged (delivery plan §7).

**Tests**: Mandatory for every named case in the spec's Test plan (delivery plan §3.10 — coverage is behavioural; cases are a floor, not a ceiling). Written to fail before the code exists.

**Organization**: One slice, one user story (delivery plan overrides: drop P1/P2/P3, drop Foundational, drop Polish). All tasks are `[US1]`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: `US1` for every task (single-story slice)
- Exact file paths in descriptions

## Path Conventions

- **Supabase backend**: `backend/supabase/migrations/`, `backend/tests/`
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — **not used by B1** (this slice touches `backend/` only)

---

## Phase 1: Tests (written first, fail before the code exists)

**Goal**: One task per named test in `spec.md` Test plan (T01–T07, T08–T12 = 12 named tests). Both suites follow the existing `BEGIN … CREATE TEMP TABLE <name>_results … DO $$ … $$ … RAISE EXCEPTION on failure … COMMIT … SELECT` pattern (`auth_security_extensions.sql`, `dev_reset_clinic_installation.sql`).

### `backend/tests/ai_keystore_rls.sql` (T01–T06)

- [X] T013 [P] [US1] Add `T01 keystore anon read denied` and `T02 keystore authenticated read denied` to `backend/tests/ai_keystore_rls.sql` — `SET LOCAL role anon|authenticated`; assert `SELECT` from `ai_internal.installation_keys` raises `insufficient_privilege`. Satisfies FR-001; pinned by itself.
- [X] T014 [US1] Add `T03 issuing function reads keystore successfully` to `backend/tests/ai_keystore_rls.sql` — a bootstrapped authenticated fixture calls the keypair/enroll function; asserts the `SECURITY DEFINER` path reaches the secret-key row. Satisfies FR-001; pinned by itself. (Depends on the keystore schema migration existing to fail-meaningfully — written against T015.)
- [X] T015 [US1] Add `T04 rotation adds key without removing previous`, `T05 previous-key AAT still verifies within validity window`, and `T06 revoked key rejected` to `backend/tests/ai_keystore_rls.sql` — enroll, rotate (assert two active rows, distinct `kid`), mint under the previous key and `auth_internal.verify_aat` (§4.2.1 `pgsodium.crypto_sign_verify_detached`) returns true; revoke a key and `verify_aat` returns false. Satisfies FR-002, FR-003; pinned by itself. (T05/T06 require the issuer/verifier migration T018 to fail-meaningfully.)

### `backend/tests/ai_token_issuer.sql` (T07, T08–T12)

- [X] T016 [P] [US1] Add `T07 all section 5.6 claims populated` to `backend/tests/ai_token_issuer.sql` — mint via `public.issue_ai_token` as a fixture staff member; base64url-decode the JWS payload (§4.2.1 `encode`/`translate`) and assert each of `iss`,`aud`,`sub`,`org`,`branch`,`role`,`scopes`,`jti`,`iat`,`exp`,`ver` is present and non-null. Satisfies FR-006, FR-008, FR-009, FR-011; pinned by itself.
- [X] T017 [US1] Add `T08 scopes derived from RBAC and unaffected by caller-supplied scopes`, `T09 expired or absent session rejected`, `T10 issuance row written`, `T11 issuer rate limit trips`, and `T12 exp within configured minutes` to `backend/tests/ai_token_issuer.sql` — fixture role has `ai.access` granted; call with `p_scopes := ARRAY['ai.forge']` and assert payload `scopes` excludes `ai.forge`; call with no `auth.uid()` → rejection; after a mint assert exactly one `ai_internal.ai_token_issuance` row for the `jti`; set the configured ceiling to a small fixture value, mint to the ceiling, assert the next mint is rejected; assert `0 < exp − iat ≤ configured_minutes`. Satisfies FR-004, FR-005, FR-007, FR-010, FR-012, FR-013; pinned by itself. (Requires the issuer migration T018 to fail-meaningfully.)

---

## Phase 2: Implementation (one task per implementation unit in `plan.md` Files)

- [X] T018 [US1] Create `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` — `CREATE EXTENSION pgsodium` + `GRANT pgsodium_keymaker` to the enrollment role (§4.2.1); `CREATE SCHEMA ai_internal` with `REVOKE ALL FROM PUBLIC, anon, authenticated`; `ai_internal.installation_keys` (installation_id uuid, kid text, public_key bytea, secret_key bytea, algorithm text default `'EdDSA'`, valid_from timestamptz, revoked_at timestamptz, audit/soft-delete columns) and `ai_internal.ai_token_issuance` (issuance_id, installation_id, jti, actor_staff_id, iat, audit columns) tables; `ALTER TABLE … ENABLE ROW LEVEL SECURITY` with `FOR ALL USING (false)` deny policies (only the `SECURITY DEFINER` functions read them, §4.2); config keys for AAT lifetime (minutes) and issuer rate-limit (window + ceiling). Satisfies FR-001, FR-002, FR-003, FR-012, FR-013. Proven by T01–T06, T10, T11, T12.
- [X] T019 [US1] Create `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` — `auth_internal.enroll_installation_keypair()` and `auth_internal.rotate_installation_key()` call `pgsodium.crypto_sign_new_keypair()` (§4.2.1), insert a new `kid` row without removing the previous (§8.1 rotation paragraph), gated by `auth_internal.assert_owner_or_administrator()`; `auth_internal.revoke_installation_key(p_kid)` sets `revoked_at`; `public` `SECURITY INVOKER` wrappers `public.enroll_installation_keypair` / `public.rotate_installation_key` / `public.revoke_installation_key`. Satisfies FR-001, FR-002, FR-003. Proven by T03, T04, T06.
- [X] T020 [US1] Create `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql` — `auth_internal.issue_ai_token()` `SECURITY DEFINER`: verify `auth.uid()` and reject absent/expired session (§4.2); resolve `iss`/`sub`/`org`/`branch`/`role` via `auth_internal.build_staff_claims`; derive `scopes` from `public.roles_permissions` `ai.*` granted to the caller's role (§5.6), ignoring any caller-supplied `p_scopes`; mint an `alg: EdDSA` JWS (§4.2.1 `pgsodium.crypto_sign_detached` over base64url `header.payload`) carrying every §5.6 claim and the deliberate omissions; set `aud` = AI platform audience, `jti` = `gen_random_uuid()`, `exp` = `iat` + configured minutes, `ver` = configured token-contract version; insert the `ai_token_issuance` row; count the caller's ledger rows in the configured window and reject over the ceiling. `auth_internal.verify_aat(token)` uses `pgsodium.crypto_sign_verify_detached` for the §4.2.1 clinic-side self-test. `public.issue_ai_token` `SECURITY INVOKER` wrapper. Satisfies FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013. Proven by T05, T07, T08, T09, T10, T11, T12.

---

## Phase 3: Verification (full B1 suite + every prior slice's suite, §3.10)

- [X] T021 [US1] Create `backend/tests/run_ai_platform_trust_tests.sh` (mirrors `run_auth_backend_tests.sh`: sources `backend/local/.env`, `psql -h 127.0.0.1 -p $SUPABASE_DB_PORT -U postgres -d postgres -v ON_ERROR_STOP=1 -f` each B1 SQL suite) and append `ai_keystore_rls.sql` / `ai_token_issuer.sql` to `backend/tests/run_auth_backend_tests.sh`'s `sql_tests` array so CI runs them with the existing auth suite. Run the whole B1 suite and the prior band-A suite (`ai-platform/` `npx vitest run`) green. **Slice-only note**: the quickstart cites only `ai_keystore_rls.sql` + `ai_token_issuer.sql`; this task is the full-suite gate, not a quickstart command.

---

## Phase 4: Documentation (always present)

- [X] T022 [P] [US1] Create `specs/021-installation-keystore-aat-issuer/quickstart.md` per `.specify/templates/ai-platform-quickstart-template.md` — sections: (1) Architecture context (cite delivery plan §3.3 row B1 and `01-ai-platform.md` §4.2 / §4.2.1 / §5.6 / §8.1); (2) What was implemented (the `ai_internal` keystore, the `auth_internal` keypair routines and issuer RPC, the `public` wrappers); (3) Files to review (the three migrations and two SQL suites — **slice-only**: no prior-slice files); (4) Prerequisites (local Supabase stack up, `pgsodium` enabled by the migration); (5) Run the automated suite (`bash backend/tests/run_ai_platform_trust_tests.sh` — slice-only, not full `npm test`/prior regression); (6) Inspect the changes (`\dn ai_internal`, `\df+ auth_internal.issue_ai_token`, a sample decoded AAT header); (7) Manual validation omitted (CI is the only verification path — no user-facing behaviour). State the slice-only scope rule explicitly.
- [X] T023 [P] [US1] Create `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md` — the frozen AAT JWS contract: header `{alg:"EdDSA", kid}` (§5.6 — `alg` non-negotiable), the §5.6 claim set with the deliberate omissions (no patient/quota/provider-model), the JWK public-key format `{"kty":"OKP","crv":"Ed25519","x":<base64url>}` with `kid` (§4.2.1), the signing/verifying mechanisms (`pgsodium.crypto_sign_detached` / `crypto_sign_verify_detached`), and the rotation rule (additive, §8.). Pinned by T07 (every claim populated) and T05/T06 (rotation/revocation). A later slice's **Consumes** (B3 verifier, B4 `jti`) binds to this artifact, not to prose.

---

## Dependencies & Execution Order

### Within the slice

1. **Tests first (Phase 1)** — written against the not-yet-existing schema/RPCs so they fail meaningfully. T013 (anon/auth deny) and T016 (claim population) are `[P]` — different files. T014 depends on T018 (keystore schema) to fail-meaningfully. T015 depends on T018 + T020 (issuer/verifier). T017 depends on T019 + T020.
2. **Implementation (Phase 2)** — strictly ordered by migration timestamp: T018 (schema) → T019 (keypair routines, needs the schema) → T020 (issuer + verifier, needs the schema and keypair rows).
3. **Verification (Phase 3)** — T021 after T018–T020 + T013–T017 are green.
4. **Documentation (Phase 4)** — T022 / T023 are `[P]` (different files); they may land after T018–T020 are written but should be finalized once the suite is green.

### Cross-slice

- B1 has no prior AI-platform slice dependency. B3 and B4 will consume the AAT contract frozen here (T023); they do not block B1.
- The external dependency — existing clinic RBAC + `ai.access` seed — is already merged (verified in `20260516100400_auth_rbac_seed.sql` / `20260613140000_role_permissions_full_matrix.sql`); no task is needed for it.

### Parallel Opportunities

- T013 (`ai_keystore_rls.sql`) ‖ T016 (`ai_token_issuer.sql`) — different files, both `[P]`.
- T022 (`quickstart.md`) ‖ T023 (`contracts/aat-token.md`) — different files, both `[P]`.
- No other parallelism: the three migrations (T018→T019→T020) are timestamp-ordered and share the schema; the test tasks T014/T015/T017 are gated by the migrations they assert against.

---

## Notes

- 23 tasks total (12 test-grouped tasks + 3 migrations + 1 verification + 2 documentation = 18 named rows above; counting T013–T023 = 11 task rows). Under the 25-task cap.
- Every task traces to an `FR-###` and is proven by a named test from `spec.md`'s Test plan (T01–T07, T08–T12). No task adds work the spec or plan does not name (R-20).
- The T07a–T07k per-claim cases are grouped into one `T07` named test (and one task) at the behavioural-coverage level — one mint, one decoded payload, eleven assertions (§3.10 coverage is behavioural; §3.11.2's "one case per §5.6 claim populated" is satisfied by iterating the claim set in a single case). The spec's Test plan was amended to reflect this grouping so tasks stay traceable to it.
- Preserve layer boundaries: B1 is `backend/` only; no `ai-platform/` or `frontend/` files.
- Commit after each task or logical group; stop at the verification checkpoint (T021) to confirm the full B1 + prior band-A suite is green.

---

## Review resolution note (2026-08-03)

Completed tasks above remain checked. Post-review hardening landed as an overlay migration
`backend/supabase/migrations/20260803140000_b1_review_resolution.sql` plus expanded suites
(`ai_keystore_rls.sql` T01–T10 including T05b–d; `ai_token_issuer.sql` T07–T16). Behavioural
deltas encoded in `spec.md` / `plan.md` / `contracts/aat-token.md` / `quickstart.md`:
`public_jwk` on enroll/rotate, per-actor advisory rate lock, installation-scoped signing
selection + singleton trigger, `verify_aat` `iss` bind and malformed→false (no `exp`), dual
error conventions documented in contract §9, and grant hygiene (`ai_internal` USAGE to
`postgres` only at B1).