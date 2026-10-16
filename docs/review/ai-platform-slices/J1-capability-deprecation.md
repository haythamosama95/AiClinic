# Slice Review: J1 — Capability deprecation and the overlap window

**Reviewed against:** `docs/architecture/ai-platform/01-ai-platform.md` §5.1, §5.7, §7.3, §12.4, amendment A12, OD-9 (source of truth); `specs/048-capability-deprecation/` (spec, plan, tasks, `contracts/capability-deprecation.md`).
**Implementation reviewed:** `ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql`, `ai-platform/schema.snap.sql`, `ai-platform/src/capability/index.ts`, `ai-platform/src/control/capability-lifecycle.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/worker.ts`, `ai-platform/test/capability-deprecation.test.ts`, plus both vitest configs.
**Method:** Static review only; no build, no test execution.

## 1. Executive Summary

J1 is a faithful, well-scoped implementation of the A12 overlap-window contract. The core requirements are correctly implemented and tested: deprecate/retire persist onto the `global`-scope `capability_grant` lifecycle overlay (never touching a published manifest or its hash); discovery announces `deprecated` with the successor and derives the etag from the effective Identity so the announcement invalidates client caches; a deprecated pin keeps serving; after the operator retire mutation the same pin returns `capability_retired`; and both mutations write `control_audit` with the operator identity. The delivery-plan band-J constraint is met exactly: no new entity, and precisely one forward-only additive migration (`ALTER TABLE capability_grant ADD` four nullable columns), with `schema.snap.sql` updated to match. The no-rework rule holds for C1 (evaluation order `lookup → retired → allowance/grant → kill-switch` preserved verbatim, three taxonomy codes untouched) and B2 (`OperatorAuth`, the `/control` boundary, and the `control_audit` row shape reused; only the action vocabulary extended, which B2 explicitly allows).

No critical issues were found. The notable findings are: `handleDeprecate` performs **no state guard at all** — it can resurrect a retired version and silently restart the overlap window on a duplicate deprecate; deprecate/retire never check that the target capability version exists in the registry, so operator typos create orphan overlay rows; and the test suite, while covering all five named cases from the spec's Test plan, omits every control-plane rejection branch (unauthenticated operator, retire-before-window, retire-without-deprecation, missing successor), the discovery-excludes-retired branch, and the etag-invalidation claim the frozen contract makes.

## 2. Critical Issues

None found.

## 3. Bugs

- **[High] `handleDeprecate` has no lifecycle-state guard — deprecate-after-retire resurrects a retired version, and duplicate deprecate silently resets the window** — `ai-platform/src/control/capability-lifecycle.ts:49-107`. The handler never reads the current overlay; it unconditionally appends a new `global`-scope row with `lifecycle_state = 'deprecated'`. Because both the request-path reader (test reader, `capability-deprecation.test.ts:291-295`) and `loadGlobalOverlay` (`capability-lifecycle.ts:41-42`) resolve the overlay as `ORDER BY changed_at DESC LIMIT 1`, a deprecate issued after a retire makes the effective state `deprecated` again — `resolve()` starts serving the pin (`capability/index.ts:430-432` only rejects `retired`) and discovery re-advertises it. §5.7 / §12.4 model the lifecycle as one-directional (`active → deprecated → retired`; retirement is the terminal step of the recipe), and the frozen contract §2.2 defines deprecate only as the transition *into* deprecation. The same gap means a second deprecate (operator retry, double-click, script rerun) overwrites `deprecated_at` and pushes `retire_after` out by another 90 days without any audit-visible distinction. `handleRetire` correctly guards its preconditions (`capability-lifecycle.ts:126-139`); deprecate needs the symmetric guard (reject when the latest overlay is `retired`; define and enforce idempotency or rejection for repeated deprecate).
- **[Medium] Deprecate (and retire) never verify the capability version exists in the registry** — `capability-lifecycle.ts:80-105`. An operator typo in `{capability_id}` or `{version}` produces a `global` overlay row plus a `control_audit` entry for a capability that does not exist; the overlay is inert only because `resolve()`/`discover()` key off the registry first (`capability/index.ts:423-425`). The `successor_id` is likewise accepted as an arbitrary string with no shape or registry check (`capability-lifecycle.ts:68-70`), so discovery can announce a successor that resolves to `capability_unknown` — clients prompting for an update to a nonexistent version is exactly the opaque failure §12.4 forbids. The handlers run in the control isolate where the registry is available; a lookup before the write is cheap.
- **[Low] Overlay rows are written with `granted_at = <mutation instant>` and `revoked_at = NULL`** — `capability-lifecycle.ts:83-96, 146-162`. A lifecycle-overlay row is not a grant, yet it is stamped as a live, unrevoked grant. Today's readers key global-scope rows separately from installation/plan grant keys, so this is harmless, but it pollutes the append-only history the §7.3 audit story depends on ("who deprecated what, when" is answerable) — a `granted_at` on a retire row is meaningless, and any future reader that filters grants by `revoked_at IS NULL` without scoping will pick up overlay rows.
- **[Low] Window comparison is a raw string compare** — `capability-lifecycle.ts:138` (`nowIso() < retireAfter`). Lexicographic comparison is only valid for canonical UTC `Z` timestamps of identical precision; both sides are currently produced by `new Date().toISOString()` so it holds, but the overlay column is operator-writable TEXT and a non-canonical value (offset, missing millis) would silently misorder the FR-005/FR-007 window gate. Parse to epoch milliseconds before comparing.

## 4. Architectural Deviations

- **[Medium] Production read path for the overlay exists only in tests** — FR-010 / contract §2.4 require discovery and resolve to read the overlay through the config cache via `loadConfig("grants", "global/{id}/{version}")`. The code path is correct (`capability/index.ts:75-104`), but the platform's only production `D1Reader`, `createD1ConfigReader` (`ai-platform/src/config-cache/index.ts:112-149`), returns `"miss"` for every kind except `installations`/`keys`/`token_contracts`; the `grants` reader that understands `global/{id}/{version}` is defined inside this slice's test file (`capability-deprecation.test.ts:281-299`) and its siblings. `resolve`/`discover` are also not yet wired into `worker.ts` (no import of `../capability` outside `control/capability-lifecycle.ts`). This is an inherited C1/A5 wiring gap deferred to whichever slice binds the request pipeline, not something J1 introduced — but as shipped, a production request path using the current production reader would observe *no* overlay (miss → published manifest lifecycle stands) and retirement would never be enforced. The handoff must be explicit before the slice that wires the pipeline ships.
- **[Low] Deprecate is not journaled with before/after context, and neither mutation records the successor in the audit target** — `control_audit` rows for both mutations carry `before_pointer`/`after_pointer = NULL` (`capability-lifecycle.ts:99-102, 163-166`). This matches B2's own enroll precedent (`control/lifecycle.ts:195-198`), so the consumed contract is respected — but §7.3's audit story ("who deprecated what, when") loses the *successor*, which lives only on the overlay row. Given rows are append-only this is recoverable by correlation; noted as a debt item, not a deviation.
- **Verified non-deviations (no-rework rule holds):** exactly one forward-only additive migration and no new table/entity (`migrations/20260802100000_capability_grant_lifecycle.sql:1-5`; `schema.snap.sql:51`); manifest bytes and content hash are never touched — discovery/resolve return a *derived* frozen copy via `manifestWithEffectiveIdentity` (`capability/index.ts:107-127`) per contract §2.3; C1's evaluation order and all three taxonomy codes are intact (`capability/index.ts:422-451`); C1's `deprecated`-is-not-a-rejection semantics are preserved and the request path does not auto-retire on a clock (`resolve` rejects only effective `retired`, `capability/index.ts:430-432`); B2's `/control` boundary, `OperatorAuth`, five installation-lifecycle actions, and `control_audit` shape are extended, not rewritten (`control/index.ts:64-66, 99-108`; `worker.ts:111-113`); the OD-9 default is a named constant, not a configuration surface (`capability/index.ts:34-35`); the discovery etag hashes the effective Identity set, so a deprecation announcement changes the etag and `must-revalidate` clients pick it up (`capability/index.ts:453-460, 636-657`) per contract §5; guard-rejection at resolve produces no `ai_request` row (resolve has no journal dependency — C1/C3 invariant intact).

## 5. Missing or Weak Tests

**Required floor (delivery plan §3.11.8) — all present:** T-J1-01 discovery marks deprecated with successor (`capability-deprecation.test.ts:369-398`); T-J1-02 deprecated serves inside the window (`400-435`); T-J1-03 retired pin returns `capability_retired` (`437-485`); T-J1-04 retirement journaled with operator identity (`487-527`). The spec's fifth named case T-J1-05 (cold-isolate reconstruction, manifest hash unchanged, `529-578`) is also present.

Missing against the every-branch coverage rule:

- **[Medium] No operator-authorization test on the new mutations** — `requireOperator` is exercised on the deprecate/retire path only in the affirmative; no case drives a null/rejected `OperatorAuth` (the test's own fake supports it, `capability-deprecation.test.ts:43-51`) to assert the 401. B2's freeze — control plane authenticated by operator identity, not clinic identity — is a stated invariant this slice applies to two new routes, and the security-sensitive surface is otherwise untested.
- **[Medium] No tests for the retire gates** — `not_deprecated` (retire without prior announced deprecation/successor) and `overlap_window_active` (retire before `retire_after`) are stated rule branches (contract §4.3; FR-002, FR-005, FR-007) and are the entire enforcement of "announcement before enforcement" on the write side; neither rejection is ever asserted (`capability-lifecycle.ts:126-139`).
- **[Medium] No test that discovery excludes a retired version** — contract §2.3 requires `discover()` to drop effective-`retired` versions (`capability/index.ts:557-559`); T-J1-03 asserts only the resolve path. A regression that rejects resolve but keeps advertising the retired version in discovery would go undetected.
- **[Low] No test for `missing_successor_id`** — the deprecate request-body validation branch (`capability-lifecycle.ts:68-70`) is unexercised.
- **[Low] No test for the deprecate audit row** — FR-008 covers *both* mutations, but only action `retire` is asserted in `control_audit` (T-J1-04); a deprecate that skipped or mis-targeted its audit insert would pass the suite.
- **[Low] No etag-invalidation test** — contract §5 promises deprecation invalidates client caches via the etag; no test compares discovery etags before/after a deprecate (or after a retire).
- **[Low] No test that a deprecated version still serves *after* `retire_after` has passed but before the operator retires it** — this is the explicit "request path does not auto-retire on a clock" branch (contract §3; plan Constraints) and the other half of the window semantics; T-J1-02 only covers `now < retire_after`.
- **[Low] No test for deprecate-after-retire or duplicate deprecate** — the missing state guard (§3, first finding) is also uncovered behavior; once the guard exists, both rejection cases belong in the suite.
- **[Low] Overlay-absent fallback of `effectiveLifecycle` is untested in this slice** — a manifest published with `lifecycleState: "deprecated"`/`"retired"` and no overlay row never exercises the `publishedState` branch (`capability/index.ts:56-67`); partially covered by C1 suites, but J1 owns the merged rule.

## 6. Recommended Improvements

1. **[High] Add the deprecate state guard**: load the current global overlay in `handleDeprecate` (reuse `loadGlobalOverlay`); reject when the latest state is `retired` (terminal per §5.7/§12.4), and either reject or treat as idempotent a deprecate that is already `deprecated` with the same successor — never silently restart `deprecated_at`/`retire_after`. Add both rejection tests.
2. **[Medium] Validate the target against the registry in both handlers** (unknown id/version → 400/404 before any D1 write), and validate `successor_id` minimally as a known capability identity so discovery never announces a successor that resolves to `capability_unknown`.
3. **[Medium] Backfill the missing branch tests**: 401 on unauthenticated deprecate/retire, `not_deprecated`, `overlap_window_active`, `missing_successor_id`, discovery-excludes-retired, and the deprecate audit row — each is one seeded fixture away given the existing substrate.
4. **[Low] Compare window timestamps as epoch milliseconds** (`Date.parse`) instead of ISO strings, and validate `retire_after` parses before relying on it (`capability-lifecycle.ts:135-139`).
5. **[Low] Write overlay rows without grant semantics** — e.g. `granted_at = NULL` (or reuse `changed_at` only) so the append-only history does not read as a live grant.
6. **[Low] Record the successor in the deprecate audit trail** (e.g. in `target` as `{id}@{version}->{successor}`, or via `after_pointer`) so `control_audit` alone answers "deprecated in favour of what".
7. **[Low] Document the production-reader dependency**: note in `contracts/capability-deprecation.md` or the quickstart that FR-010's config-cache read path requires a production `D1Reader` handling `grants` (including the `global/` key form) before the request pipeline is wired, so the enforcing slice cannot silently ship the miss-everything reader.

---

## 7. Review Resolution

### 7.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **J1-R1 — Deprecate state guard** | Bugs #1; Missing/Weak Tests #8; Recommended Improvements #1 | `ai-platform/src/control/capability-lifecycle.ts`; `ai-platform/test/capability-deprecation.test.ts` (T-J1-06..08) |
| **J1-R2 — Registry + successor validation** | Bugs #2; Missing/Weak Tests #4; Recommended Improvements #2 | `capability-lifecycle.ts`; `ai-platform/src/capability/index.ts` (`isCapabilityVersionRegistered`, `isSuccessorRegistered`); tests T-J1-09..11 |
| **J1-R3 — Overlay hygiene + epoch window compare** | Bugs #3, #4; Recommended Improvements #4, #5 | `capability-lifecycle.ts` (`revoked_at = changed_at`; `Date.parse` window gate); tests T-J1-12..13 |
| **J1-R4 — Audit successor in after_pointer** | Architectural Deviations #2; Recommended Improvements #6 | `capability-lifecycle.ts` deprecate/retire audit `after_pointer`; test T-J1-14; contract §4.4 extension |
| **J1-R5 — Branch / coverage backfill** | Missing/Weak Tests #1–3, #5–7, #9; Recommended Improvements #3 | `capability-deprecation.test.ts` T-J1-15..20 (401, retire gates, discovery-excludes-retired, etag, post-window serve, published-without-overlay) |
| **J1-R6 — Production-reader handoff docs** | Architectural Deviations #1; Recommended Improvements #7 | `specs/048-capability-deprecation/contracts/capability-deprecation.md` §2.4; `quickstart.md`; `plan.md` Constraints |

Every numbered review item appears in exactly one stage. No escalations — all fixes stayed within J1 scope and allowed contract extensions (rejection vocabulary, `after_pointer` successor, documentation handoff). Architecture docs untouched.

### 7.2 Test cases created first

- **J1-R1:** T-J1-06 `deprecate_rejects_after_retire` (409 `already_retired`, no resurrect); T-J1-07 `duplicate_deprecate_same_successor_is_idempotent` (200, no window reset); T-J1-08 `duplicate_deprecate_different_successor_rejected` (409 `already_deprecated`).
- **J1-R2:** T-J1-09 `unknown_capability_version_rejected` (404 before D1 write); T-J1-10 `unknown_successor_rejected`; T-J1-11 `missing_successor_id_rejected`.
- **J1-R3:** T-J1-12 `overlay_rows_are_not_live_grants` (`revoked_at = changed_at`); T-J1-13 `retire_window_uses_epoch_ms` (non-canonical `+00:00` `retire_after`).
- **J1-R4:** T-J1-14 `deprecate_audit_records_successor` (`after_pointer` = successor id).
- **J1-R5:** T-J1-15 unauthenticated 401; T-J1-16 retire gates; T-J1-17 discovery excludes retired; T-J1-18 etag invalidation; T-J1-19 deprecated serves after `retire_after` before operator retire; T-J1-20 published Identity without overlay.
- **J1-R6:** documentation-only (no new production test).

### 7.3 Fix implemented

- **J1-R1:** `handleDeprecate` loads the latest global overlay; rejects `retired` / conflicting duplicate deprecate; same-successor duplicate returns idempotent `200` without a new overlay row.
- **J1-R2:** Both handlers require a registered target version; deprecate requires a registered successor identity (`capabilityId` or `capabilityId@version`).
- **J1-R3:** Overlay inserts set `revoked_at = changed_at` (A5 `granted_at` remains `NOT NULL`, mirrored to `changed_at`); retire compares window via `Date.parse` epoch ms.
- **J1-R4:** Deprecate and retire `control_audit` rows record the successor in `after_pointer`; `target` stays `{id}@{version}`.
- **J1-R5:** Fifteen review-branch cases added; existing fixtures use `buildJ1Registry()` so successor validation stays green.
- **J1-R6:** Contract §2.4 documents that production `createD1ConfigReader` must gain `grants` / `global/…` before the request pipeline enforces overlays — documented handoff, not a silent production reader rewrite in J1.
- Spec Kit aligned: `spec.md` edge cases + test-plan rows; `plan.md` Constraints/files; `quickstart.md`; `contracts/capability-deprecation.md` state guard, validation, overlay hygiene, audit extension, reader handoff.

### 7.4 Verification

Full `ai-platform` suite (`npm test`):

- Node pool: **41** files, **639** tests passed
- Workers pool: **19** files, **285** tests passed (includes `capability-deprecation.test.ts` **20** cases T-J1-01..20)

Modified/added tests: `ai-platform/test/capability-deprecation.test.ts`. Production: `ai-platform/src/control/capability-lifecycle.ts`, `ai-platform/src/capability/index.ts`.
