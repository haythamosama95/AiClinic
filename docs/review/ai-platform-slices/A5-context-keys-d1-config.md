# Slice Review Report — A5: Context Keys, D1 Schema, Config Cache

**Spec:** `specs/019-ai-context-keys-d1-config/spec.md` · **Branch:** `ai/019-a5-context-keys-d1-config` · **Canonical:** §5.2, §7.3, §13.4, §4.3.2, §4.4, §9.15

## Executive Summary

A5 delivers the context-key vocabulary and first published shape (`visit.chief_complaint@v1`), forward-only D1 migrations for all eleven §7.3 entities, a schema snapshot test, and an in-isolate config cache with TTL, typed miss handling, and spy-based I/O-budget tests. The config cache and migration suite are well aligned with the spec. Minor gaps: closed-key vocabulary conflates “unknown key” with “unknown version”; schema snapshot path differs from spec clarification; one migration test does not exercise D1 storage of request references; idempotency uniqueness is not indexed (relevant to C3).

## Critical Issues

None.

## Bugs

None identified in slice logic.

## Architectural Deviations

1. **Closed vocabulary of six §5.2 example keys** (`src/context/index.ts:60-73`). Only `visit.chief_complaint@v1` has a published shape; the other five example keys pass `validateKey` but fail `validatePayload` with `unknown_shape`. This matches “first key's shape published by this slice” but means `validateKey` rejects any well-formed key outside the six examples (e.g. a future `patient.demographics@v2`) with code `unknown_version` — semantically muddy but functionally acceptable until more keys ship.
2. **Schema snapshot location.** Spec clarification Q2 names `ai-platform/test/schema.snap.sql`; implementation uses `ai-platform/schema.snap.sql` (`migrations.test.ts:18`). Documentation mismatch only.
3. **Second migration** `20260802100000_capability_grant_lifecycle.sql` extends A5's schema after band J work — additive and forward-only, but the A5 snapshot must include it for `schema_snapshot_matches` to pass on `ai/master`.

## Missing or Weak Tests

1. **T-A5-15** (`migrations.test.ts:200-231`) validates A2 reference *format* via `generateRequestReference()` but never inserts into `ai_request` to prove the column accepts and returns the format — weak relative to “stores values in the format frozen by A2”.
2. **No unique index on `(installation_id, idempotency_key)`** on `ai_request` — not required by A5 spec (only `request_reference` uniqueness is frozen). C3 idempotency must address duplicate detection; flag for C3 review.
3. **Storage-named key rejection** relies on two patterns (`_table`, `get_*_rpc`) plus closed-set membership; keys like `visits.vitals_view@v1` are rejected as `unknown_version` rather than `storage_named_key`. Spec examples are covered; broader storage-shaped names are not explicitly rejected.

## Recommended Improvements

- Align snapshot path with spec clarification or update spec to match `schema.snap.sql` at repo root of `ai-platform/`.
- Add an integration insert/select test for `request_reference` column format in D1.
- Consider single-flight or stampede protection on config cache cold loads if concurrent guard consults become hot (not required by A5 spec).

---

## 1. Review Resolution

### 1.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **A5-R1 — Key rejection codes + storage-named breadth** | Architectural Deviations #1; Missing/Weak Tests #3 | `ai-platform/src/context/index.ts`; `ai-platform/test/context.test.ts`; Spec Kit: `contracts/context-key-schema.md`, `spec.md`, `plan.md`, `tasks.md` |
| **A5-R2 — Schema snapshot path alignment** | Architectural Deviations #2; Recommended Improvements (snapshot path) | Spec Kit only: `spec.md` Clarification Q2; `plan.md` Testing section — implementation path `ai-platform/schema.snap.sql` kept |
| **A5-R3 — request_reference D1 round-trip** | Missing/Weak Tests #1; Recommended Improvements (insert/select) | `ai-platform/test/migrations.test.ts` (T-A5-15); Spec Kit: `data-model.md`, `plan.md`, `tasks.md` |
| **A5-R4 — Idempotency uniqueness is C3** | Missing/Weak Tests #2 | `ai-platform/test/migrations.test.ts` (T-A5-15b negative assertion); Spec Kit: `spec.md` Out of Scope, `data-model.md`, `plan.md`, `tasks.md` — no D1 unique index (architecture §4.3.3 puts idempotency in Quota DO) |
| **A5-R5 — Snapshot includes additive post-A5 migrations** | Architectural Deviations #3 | Already satisfied on merge of `ai/master` (`schema.snap.sql` includes capability-grant lifecycle columns); Spec Kit: `data-model.md` note |
| **A5-R6 — Config-cache single-flight** | Recommended Improvements (stampede protection) | `ai-platform/src/config-cache/index.ts`; `ai-platform/test/config-cache.test.ts` (T-A5-21b); Spec Kit: `contracts/config-cache.md`, `plan.md` |

Every numbered review item appears in exactly one stage. No production change for A5-R2 or A5-R5. Architecture docs untouched.

### 1.2 Test cases created first

- **A5-R1:** `context.test.ts` — T-A5-03 asserts `storage_named_key` for undotted examples plus `visits.vitals_table@v1`, `visits.vitals_view@v1`, `clinic.get_visit_vitals_rpc@v1`; T-A5-04 asserts `unknown_version` for known-concept unpublished versions; T-A5-04b asserts `unknown_key` for `patient.allergies@v1`.
- **A5-R2:** No new test — documentation alignment only (Q2 path already exercised by T-A5-13 against `ai-platform/schema.snap.sql`).
- **A5-R3:** T-A5-15 extended — insert a `generateRequestReference()` value into `ai_request` and select it back unchanged before treating storage as proven.
- **A5-R4:** T-A5-15b — asserts zero unique indexes mentioning `idempotency` on `ai_request`.
- **A5-R5:** No new test — T-A5-13 already pins the post-migration DDL including additive lifecycle columns.
- **A5-R6:** T-A5-21b — concurrent cold `loadConfig` calls for the same kind+key produce exactly one `reader.read` and both resolve to the same row.

### 1.3 Fix implemented

- **A5-R1:** `validateKey` now rejects storage-named patterns (`_table`, `_view`, `get_*_rpc` on the concept segment) **before** format checks; distinguishes `unknown_key` (unknown `domain.concept`) from `unknown_version` (known concept, unpublished `@vN`). Contract extended with `unknown_key` and `_view` (allowed extension per delivery plan §2.3).
- **A5-R2:** Clarification Q2 and plan Testing section updated to `ai-platform/schema.snap.sql`. No production move of the snapshot file.
- **A5-R3:** T-A5-15 performs installation + `ai_request` insert/select of an A2 reference.
- **A5-R4:** Documented intentional absence of D1 idempotency uniqueness; T-A5-15b locks it. No unique index added (would contradict §4.3.3).
- **A5-R5:** Confirmed snapshot already includes band-J additive columns after `ai/master` merge; documented in `data-model.md`.
- **A5-R6:** `ConfigCache.beginInflight` coalesces concurrent cold loads; `loadConfig` uses it.

### 1.4 Verification

Full `ai-platform` suite: **38 files, 443 tests passed** (`npm test`), including `context.test.ts` (22), `config-cache.test.ts` (14), and `migrations.test.ts` (17 with T-A5-15 insert/select + T-A5-15b).
