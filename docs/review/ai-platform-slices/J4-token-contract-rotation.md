# Slice Review: J4 — Token contract rotation with overlapping acceptance

**Reviewed against:** `docs/architecture/ai-platform/01-ai-platform.md` §5.6, §5.7 (plus §4.5 row and §7.3 `token_contract` entry as cited by the spec — source of truth); `specs/051-token-contract-rotation/` (spec, plan, tasks, data-model, contracts).
**Implementation reviewed:** `ai-platform/migrations/20260803120000_token_contract.sql`, `ai-platform/schema.snap.sql`, `ai-platform/src/identity/index.ts`, `ai-platform/src/config-cache/index.ts`, `ai-platform/src/control/token-contract.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/worker.ts`, plus the three J4 test suites (`ai-platform/test/token-contract-rotation.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `backend/tests/ai_token_contract_rotation.sql`) and their harness registrations.
**Method:** Static review only; no build, no test execution.

## 1. Executive Summary

J4 is a faithful, tightly scoped implementation of the §5.6/§5.7 token-contract rotation model. The core requirements are correctly implemented and tested: the D1 `token_contract` table has exactly the §7.3 shape (`ver`, `added_at`, `retired_at`, `changed_by`; no `retire_after`, no TTL) seeded with one accepted `ver = '1'`; the identity stage checks `payload.ver` against the accepted set through the existing config cache after all B3 checks, refusing misses and retired rows as the existing `unauthenticated` with no new taxonomy code; begin-rotation and retire are the only writers, both operator-authenticated POST-only control-plane mutations that write `control_audit`; the B1 issuer is untouched and still mints a single `ver` from `ai.aat.ver`. The no-rework rule holds for B1 (keystore, issuer, claim set, RBAC `scopes` — all unchanged) and B3 (signature, `alg: EdDSA` pinning, audience, expiry, skew — all intact; the accepted-`ver` check is appended after them, so the rotation mechanism introduces no algorithm-downgrade path). Unknown/future `ver` handling is correct: `ver` is a required string claim, and any value outside the set fails closed as `unauthenticated`.

No critical or high issues were found. All four delivery-plan required test cases and all ten spec-named tests are present. The notable findings are coverage gaps rather than behavior bugs: the FR-002 writer-enforcement branches (refusing a third accepted `ver`, and every retire error branch) are implemented but **never tested**, and the production `createD1ConfigReader` `"token_contracts"` SQL branch is **never exercised against real D1** — unit tests stub the reader and workers tests call the control handlers directly, so a defect in the cold-isolate reconstruction path (FR-009) would not be caught. The remaining findings are a check-then-insert race in begin-rotation, a weakly-asserted non-writer test, and a plan-vs-code file-listing mismatch.

## 2. Critical Issues

None found.

## 3. Bugs

- **[Low] Begin-rotation's at-most-two enforcement is a non-atomic check-then-insert** — `ai-platform/src/control/token-contract.ts:37-60` reads `COUNT(*) ... WHERE retired_at IS NULL`, rejects at `>= 2`, then `INSERT`s in separate statements. Two concurrent operator begin-rotation requests can both observe a count of 1 and both insert, producing a three-member accepted set and violating FR-002 ("at most two during a rotation"). The retire guard (`token-contract.ts:100-107`) has the same read-then-write shape. D1 offers no multi-row CHECK constraint to close this declaratively; the window is narrow (operator-rare, control-plane only, never the request path) and the blast radius is one extra accepted `ver`, but the FR-002 MUST is enforced only probabilistically.
- **[Low] Retired-`ver` refusal lags the retire write by up to one config-cache TTL** — the verifier reads the contract row through `loadConfig` (`identity/index.ts:322-333`), and a row cached while accepted (`retired_at` null) keeps verifying until the entry expires, even after the operator retires that `ver`. §7.3 explicitly sanctions this ("a rotation takes effect within one cache TTL without a deploy"), so it is not a deviation — but the slice's Done-when wording ("tokens of the retired version are refused after it") reads as immediate, and neither the quickstart nor the contract records the TTL lag for operators sequencing a retire. After the TTL, refusal is airtight (retired row cached → refuse; row absent → miss → refuse; both permanent states).

## 4. Architectural Deviations

- **[Low] Plan Files table omits the new `src/control/token-contract.ts` module** — `specs/051-token-contract-rotation/plan.md` (Files table, Project Structure) attributes the begin-rotation / retire handlers to a modification of `src/control/index.ts`; the handlers actually live in a new file `ai-platform/src/control/token-contract.ts` that no plan row lists (`control/index.ts:18-19, 55-56, 66-67, 135-142` only re-exports and routes). The code structure is good — it matches the `capability-lifecycle.ts` / `routing-policy.ts` sibling-file pattern — but the Speckit record misstates the file surface, a documentation issue under the source-of-truth rule.
- **Verified non-deviations (no-rework rule holds):** B1's issuer still mints `ver` from `ai_internal.app_settings` key `ai.aat.ver` with `EdDSA` and the full §5.6 claim set, unmodified (`backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:114, 260`); B3's verifier pipeline is intact — `alg !== "EdDSA"` rejected before any config load (`identity/index.ts:227`), audience/expiry/skew before I/O (`identity/index.ts:251-259`), `iss`+`kid` ownership bound before signature verification (`identity/index.ts:294-318`) — with the accepted-`ver` consult appended *after* signature verification, so `payload.ver` is only trusted post-authentication and rotation adds no algorithm-negotiation path; `ver` is a required string claim (`identity/index.ts:107`), so a missing `ver` fails closed; the principal is extended with `ver` without changing its frozen shape otherwise (`identity/index.ts:139-152`); the config cache is extended forward-only with kind `"token_contracts"` (`config-cache/index.ts:13, 138-143`), A5's contract untouched; `errors.ts` is unchanged and no new taxonomy code exists (refusal reuses `rejectUnauthenticated`); control-plane operator mistakes stay on the B2 HTTP error surface (`token-contract.ts:33, 42, 51, 83, 95, 99, 106`) as contract §3 permits; the request path never writes `token_contract` — the only `INSERT`/`UPDATE` statements in `src/` are in `control/token-contract.ts:55, 111`, reachable only via POST `/control/token-contract/...` (`worker.ts:111`); the migration carries no `retire_after`/TTL (`migrations/20260803120000_token_contract.sql:2-7`) and the snapshot matches (`schema.snap.sql:114-119`).

## 5. Missing or Weak Tests

**Required-case status (delivery plan §3.11.8 J4 floor): all present.**

- Both `ver` values verify during the rotation window — **present**: T-J4-01 (`token-contract-rotation.test.ts:260-290`), including assertions that both `token_contracts:1` and `token_contracts:2` were consulted.
- A retired `ver` is refused afterwards — **present**: T-J4-02 (`token-contract-rotation.test.ts:292-313`), including the no-new-code assertion `Object.keys(result)` equals `["ok", "code"]`.
- A token minted under the new contract carries every claim — **present**: T-J4-08 (`backend/tests/ai_token_contract_rotation.sql:150-219`), asserting all eleven §5.6 claims non-empty, `alg: EdDSA` header, `ver = '2'`, and absence of patient/quota/provider/model keys.
- Rotation requires no re-enrollment — **present**: T-J4-10 in three halves (unit `token-contract-rotation.test.ts:362-398`; workers `token-contract-control.test.ts:213-239`; clinic `ai_token_contract_rotation.sql:257-304` asserting key count unchanged and same `iss`).

All ten spec-named tests (T-J4-01..T-J4-10) exist with matching names and are registered in both Vitest harnesses and the clinic trust script. The gaps are branch coverage the §3.10 every-branch rule implies beyond the named floor:

- **[Medium] The FR-002 writer-enforcement branch is untested** — nothing refuses a third accepted `ver`: no test drives begin-rotation while two rows are accepted and asserts the 409 `rotation_already_open` (`token-contract.ts:41-43`). T-J4-04 (`token-contract-control.test.ts:116-134`) observes counts 1 and 2 through the happy path only, so "at most two" is verified as an outcome of correct inputs, not as an enforced rule. A regression deleting the count guard would leave every existing test green.
- **[Medium] No retire error branch is tested** — `ver_not_found` (404, `token-contract.ts:94-96`), `ver_already_retired` (409, `:98-100`), and `no_rotation_open` (409, `:105-107`) have no cases; nor does the cancel-rotation path (retiring the *newly added* `ver` mid-window to return to one). The `no_rotation_open` guard is also the only thing preventing the accepted set from being emptied to zero — a state `data-model.md` §3 marks Forbidden — and it is unverified.
- **[Medium] The production D1 reader path for `token_contracts` is never exercised against real D1** — `createD1ConfigReader`'s `case "token_contracts"` (`config-cache/index.ts:138-143`) runs `SELECT * FROM token_contract WHERE ver = ?`, but the workers-pool suite only calls the control handlers and the unit suite stubs `D1Reader`; no test runs `EnrolledKeyVerifier.verify` backed by `createD1ConfigReader(env.DB)`. FR-009's cold-isolate reconstruction from D1 is therefore unproven end-to-end: a SQL typo, wrong table, or wrong bind in that branch would fail no test.
- **[Low] `request_path_never_writes_token_contract` asserts interface shape, not behavior** — T-J4-07 (`token-contract-rotation.test.ts:337-360`) proves its point with `expect("write" in reader).toBe(false)` and `expect("run" in reader).toBe(false)` on a test-built spy — properties of the `D1Reader` type, not of production code — plus a state-equality check on a map the production code never sees. It would not fail if request-path code gained a D1 write. The real guarantee currently rests on the grep-level fact that only `control/token-contract.ts` contains `token_contract` writes.
- **[Low] Operator-auth and payload-validation branches on the new routes are untested** — no case covers `requireOperator` rejection or the 400 `invalid_ver` empty/missing-body guard (`token-contract.ts:21-24, 30-33, 71-74, 80-83`) for either handler. The fake `OperatorAuth` in the workers suite always resolves.
- **[Low] The workers-pool half of T-J4-10 does not verify tokens** — `token-contract-control.test.ts:213-239` asserts accepted-set contents after begin-rotation but never runs the verifier, so the "still verify under both accepted `ver` values" claim on the D1 side is carried entirely by the Node-pool stub-reader half. Combined with the reader-path gap above, no test ties real D1 state to a verification decision.
- **[Low] Clinic SQL cases are order-coupled to a hardcoded `ver = '2'`** — T-J4-09 and clinic T-J4-10 assert `v_payload ->> 'ver' = '2'` (`ai_token_contract_rotation.sql:241, 293`), depending on T-J4-08's earlier `UPDATE ai_internal.app_settings` within the same transaction. Fine within one file, but the literal duplicates the setting value instead of re-reading it (T-J4-09 does read `v_setting_ver` and *also* compares to `'2'`, making the read half-decorative).

## 6. Recommended Improvements

1. **[Medium] Add writer-enforcement tests**: begin-rotation with two accepted rows → 409 `rotation_already_open` with the accepted set unchanged; retire of an unknown `ver` → 404; double-retire → 409; retire with a one-member set → 409 `no_rotation_open` (proving the set cannot be emptied); and a cancel-rotation case retiring the newly added `ver` (§3.10 every-branch rule; FR-002, FR-007).
2. **[Medium] Add one workers-pool identity test** that seeds `token_contract` in Miniflare D1 and runs `EnrolledKeyVerifier.verify` through `createD1ConfigReader(env.DB)` for an accepted, a retired, and an unknown `ver` — closing the FR-009 cold-isolate reconstruction gap and making the D1 half of T-J4-10 actually verify.
3. **[Low] Close or document the begin-rotation race** — e.g. perform the count check and insert inside a single serialized statement (`INSERT ... SELECT ... WHERE (SELECT COUNT(...) ) < 2` with affected-row detection), or record in the contract that concurrent operator mutations are operationally excluded.
4. **[Low] Strengthen T-J4-07** so the non-writer invariant would fail on regression — e.g. a static assertion that no file under `src/` outside `control/` references `INSERT`/`UPDATE`/`DELETE` on `token_contract` (mirroring the grep this review relied on), or a worker-level fetch test with a spy D1 binding.
5. **[Low] Record the cache-TTL retirement lag for operators** in `contracts/token-contract-rotation.md` or the quickstart: a retire takes full effect within one config-cache TTL, so the safe sequencing is advance-all-clinics → wait token lifetime **and** cache TTL → retire (§7.3).
6. **[Low] Reconcile the plan Files table** with the actual `src/control/token-contract.ts` module, and de-duplicate the clinic SQL's hardcoded `'2'` in favor of the re-read setting value.

---

## 1. Review Resolution

### 1.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **J4-R1 — Writer-enforcement + retire errors** | Missing/Weak Tests #1, #2; Recommended Improvements #1 | `ai-platform/test/token-contract-control.test.ts` — third-`ver` 409, `ver_not_found`, `ver_already_retired`, `no_rotation_open`, cancel-rotation |
| **J4-R2 — D1 reader + workers verify** | Missing/Weak Tests #3, #6; Recommended Improvements #2 | `token-contract-control.test.ts` — `createD1ConfigReader(env.DB)` + `EnrolledKeyVerifier` for accepted/retired/unknown; T-J4-10 workers half now verifies both `ver`s |
| **J4-R3 — Atomic begin/retire race** | Bugs #1; Recommended Improvements #3 | `ai-platform/src/control/token-contract.ts` — `INSERT … SELECT … WHERE COUNT < 2`; conditional retire `UPDATE`; contract §3 documents atomic FR-002 |
| **J4-R4 — Strengthen T-J4-07** | Missing/Weak Tests #4; Recommended Improvements #4 | `token-contract-rotation.test.ts` — static scan: no `src/` file outside `control/` writes `token_contract` |
| **J4-R5 — Operator-auth + invalid_ver** | Missing/Weak Tests #5 | `token-contract-control.test.ts` — 401 unauthorized (no D1 writes); 400 `invalid_ver` on both handlers |
| **J4-R6 — TTL lag documentation** | Bugs #2; Recommended Improvements #5 | `contracts/token-contract-rotation.md` §2.3; `quickstart.md` §2 — retire lag / safe sequencing |
| **J4-R7 — Plan Files + clinic SQL** | Architectural Deviations #1; Missing/Weak Tests #7; Recommended Improvements #6 | `plan.md` Files + Project Structure; `tasks.md` T014; clinic SQL T-J4-09/T-J4-10 compare to re-read `ai.aat.ver` |

Every numbered review item is in exactly one stage. No architecture-doc change. No escalation.

### 1.2 Test cases created first

- **J4-R1:** `writer_enforcement_refuses_third_accepted_ver`; `retire_error_branches` (`ver_not_found`, `ver_already_retired`, `no_rotation_open`, cancel-rotation) — assert 409/404 codes and accepted-set invariants before relying on the atomic handlers.
- **J4-R2:** `d1_config_reader_token_contracts_identity_path` — accepted/retired/unknown through production `createD1ConfigReader`; T-J4-10 workers half extended to call `EnrolledKeyVerifier.verify` for both accepted `ver`s.
- **J4-R3:** Covered by R1 writer-enforcement cases against the atomic `INSERT … SELECT` / conditional `UPDATE` (affected-row detection classifies `rotation_already_open` / `ver_already_exists` / retire errors).
- **J4-R4:** T-J4-07 second case — static source scan of `src/` outside `control/` for `INSERT`/`UPDATE`/`DELETE` near `token_contract`.
- **J4-R5:** `token_contract_operator_auth_and_payload_validation` — 401 + 400 `invalid_ver` before treating auth/payload branches as covered.
- **J4-R6 / J4-R7:** Docs / clinic SQL only (no new production behaviour).

### 1.3 Fix implemented

- **J4-R1 / R5:** Workers-pool control suite expanded with writer-enforcement, retire error, cancel-rotation, operator-auth, and `invalid_ver` cases. No production-code change beyond what R3 requires.
- **J4-R2:** Real Miniflare D1 path seeds installation + key, runs `EnrolledKeyVerifier` via `createD1ConfigReader(env.DB)` (FR-009 cold-isolate reconstruction); T-J4-10 workers half verifies tokens under both accepted `ver`s.
- **J4-R3:** Begin-rotation uses a single `INSERT … SELECT … WHERE (COUNT accepted) < 2 AND NOT EXISTS (ver)`; retire uses conditional `UPDATE … WHERE retired_at IS NULL AND accepted COUNT >= 2` with nested subquery; zero-change paths reclassify errors.
- **J4-R4:** T-J4-07 keeps the verify non-mutation check and adds the static non-writer scan.
- **J4-R6:** Contract §2.3 and quickstart record cache-TTL retire lag and safe operator sequencing.
- **J4-R7:** Plan / tasks / quickstart list `src/control/token-contract.ts`; clinic T-J4-09 drops literal `'2'`; clinic T-J4-10 compares mint `ver` to re-read `ai.aat.ver`.

### 1.4 Verification

Full `ai-platform` suite: **60** files, **948** tests, all passing (`npm test` — Node pool 41/640 + workers pool 19/308).

J4 files touched in tests: `test/token-contract-rotation.test.ts` (6 tests), `test/token-contract-control.test.ts` (12 tests). Production: `src/control/token-contract.ts`. Spec Kit: `contracts/token-contract-rotation.md`, `plan.md`, `tasks.md`, `quickstart.md`. Clinic: `backend/tests/ai_token_contract_rotation.sql`.
