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
