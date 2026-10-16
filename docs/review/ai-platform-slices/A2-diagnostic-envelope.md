# Slice Review Report — A2: Diagnostic Envelope

**Spec:** `specs/016-ai-diagnostic-envelope/spec.md` · **Branch:** `ai/016-a2-diagnostic-envelope` · **Canonical:** §5.4, §6.2, §7.6

## Executive Summary

A2 freezes the closed §5.4 error taxonomy, Crockford-base32 request references, ULID trace propagation, and the stable error-body contract (`code`, `request_reference`, `trace_id`, `retry_safe`). Implementation in `errors.ts`, `reference.ts`, and `trace.ts` is thorough; `taxonomy.test.ts` exercises normative HTTP status, retryability, quota consumption, and supplementary fields across the taxonomy table. One test defect undermines CI reliability.

## Critical Issues

None in production code.

## Bugs

1. **Request-reference uniqueness test is statistically flaky** (`ai-platform/test/reference.test.ts:12-26`). The test draws 1,000,000 references from an 8-symbol Crockford-base32 space (~40 bits of entropy). Birthday-paradox collision probability is material (~36% for 1M draws). The test asserts strict uniqueness (`expect(seen.has(reference)).toBe(false)`), so intermittent CI failures are expected, not rare. This has been observed in other verification runs (e.g. full-suite runs reporting `reference.test.ts` failure). The generator may be correct; the test methodology is wrong.

## Architectural Deviations

None identified. Taxonomy codes, request-reference format, and trace propagation align with §5.4 and A2 spec.

## Missing or Weak Tests

1. Uniqueness should be tested statistically (collision rate bound) or with a smaller draw count safely below the birthday threshold, not strict uniqueness at 1M draws.

## Recommended Improvements

- Replace the 1M strict-uniqueness loop with either (a) a bounded draw count with probabilistic slack, or (b) a deterministic property test on format/normalization only, plus a separate collision-rate statistical test with explicit tolerance.
- Keep `normalizeRequestReference` tests (T28) — those are sound.

---

## 1. Review Resolution

### 1.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **A2-R1 — T21 uniqueness methodology** | Bugs #1 (flaky 1M uniqueness); Missing/Weak Tests #1; Recommended Improvements (replace strict 1M uniqueness; keep T28) | `ai-platform/test/reference.test.ts`; Spec Kit: `specs/016-ai-diagnostic-envelope/{spec.md,plan.md,tasks.md}` |

One stage only — every finding is the same T21 birthday-paradox / test-methodology defect. No production-code change. No architecture-doc change.

### 1.2 Test case created first

Before treating the methodology as fixed, T21 in `ai-platform/test/reference.test.ts` was rewritten to the non-flaky contract:

- Format property on every draw: `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`, uppercase, no `I`/`L`/`O`/`U`.
- Strict uniqueness over **20,000** draws (not 1,000,000).
- T28 normalisation cases left unchanged.

Justification: over the 32⁸ (~2⁴⁰) Crockford space, birthday `P(collision)` at n=20,000 is ≈ **0.028%** (≪ 0.1% false-fail target). At n=1,000,000 it is ≈ **36%**, which made CI intermittent.

### 1.3 Fix implemented

- Replaced `GENERATION_RUN = 1_000_000` with `GENERATION_RUN = 20_000` and updated the T21 test title.
- No change to `generateRequestReference` / `normalizeRequestReference` — the generator was correct; the assertion was not.
- Spec Kit aligned: clarify Q&A, acceptance #21, T21 table row, SC-004, edge-case / assumptions wording in `spec.md`; T21 references in `plan.md` and `tasks.md` T003.
- Architecture docs (`01-ai-platform.md`) untouched — format, support-handle-not-key, and A6 D1 uniqueness unchanged.

### 1.4 Verification

Full `ai-platform` suite: **37 files, 411 tests passed**, including `reference.test.ts` (T21 @ 20k draws + T28).
