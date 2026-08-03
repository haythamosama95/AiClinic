# Slice Review Report — A3: Canonical Inference Representation

**Spec:** `specs/017-ai-canonical-inference/spec.md` · **Branch:** `ai/018-a3-canonical-inference-representation` · **Canonical:** §5.3, §9.10

## Executive Summary

A3 freezes the four §5.3 canonical elements (request, stream chunk, result, error) as TypeScript types plus a JSON codec, with the four chunk kinds as a closed set and a provider-shape guard. All seven required tests (T-A3-01…07) exist and assert the right things at the level the spec defined them. However, the spec — and faithfully the implementation — made two decisions that undermine the slice's purpose per DP-4 ("contracts frozen as *code* so the implementer is constrained by the type system"): the §5.3 *contents descriptions* were frozen as literal JSON field names, and every field is typed `unknown`, so the type system constrains nothing. These are primarily **spec defects** (the architecture names contents, not identifiers), but they propagate into every downstream slice and are reported here where they originate.

## Critical Issues

None (the representation is consumed consistently downstream; the defects are structural, not behavioural).

## Bugs

None within the slice's own logic. Round-trip, chunk-kind exhaustiveness, terminal-flag invariant, and taxonomy-code binding to A2's set all behave as specified.

## Architectural Deviations

1. **§5.3 "Contents" prose was frozen as literal field names — spec transcription error (documentation issue).** §5.3 lists *contents* ("ordered role-tagged message parts", "provider+model actually used", "whether the attempt consumed budget", "tool/function declarations (reserved for future)"). The spec's Assumptions section declares these are "field names … taken verbatim", and `src/contracts/canonical.ts` `CANONICAL_FIELD_MANIFEST` uses them as JSON keys — including `"tool/function declarations (reserved for future)"`, a parenthesized annotation, as an actual key. The architecture defines no such identifiers; per the precedence rule this is a spec/implementation deviation from §5.3's intent. Every downstream consumer (composer, both provider adapters, journal) now writes and casts these prose keys.
2. **The frozen "contract as code" carries no type information.** `ManifestRecord` maps every key to `unknown` (`src/contracts/canonical.ts:50-52`). DP-4's rationale — "A frozen, typed contract is a constraint a weak implementer cannot drift away from" — is defeated: consumers must `as`-cast every read (e.g. `request["max output tokens"] as string[]` patterns in `provider/gemini.ts:144-170`), so a malformed canonical value compiles fine and fails only at runtime. The four chunk kinds and the closed role-tag implications are the only genuinely typed parts.

## Missing or Weak Tests

1. **The provider-shape guard is static-only.** `assertNoProviderShapedFieldNames` is invoked in tests against the hard-coded manifest keys (which can never contain a provider name) and in the composer against its own fixed key set. The codec's decode path (`pickManifestKeys`) **silently strips** any extra/provider-shaped key rather than rejecting it — so the guard cannot actually fire on real drift in a value; it can only fire if someone edits the manifest itself. T-A3-05's "introducing a provider-shaped key makes the guard fail" constructs an artificial poisoned key list rather than exercising the codec. The protection the architecture wants ("nothing upstream may contain a provider-shaped field") is therefore weaker than it appears: an extra field introduced upstream is erased, not detected.
2. **No test asserts rejection of extra keys on decode** (only that encoded wire keys match the manifest).

## Recommended Improvements

- Rename canonical fields to real identifiers (`parts`, `formatDirective`, `maxOutputTokens`, `terminal`, `consumedBudget`, …) via a contract-change review per Delivery Plan §2.3 — this touches all consumers but removes the prose-key defect at its root. If left as-is, document the choice explicitly in the architecture set, since §5.3 does not sanction it.
- Give the manifest a typed schema (per-field types) so `CanonicalRequest`/`CanonicalResult` are real types; delete the `as` casts in adapters.
- Make the decode path reject unknown keys (fail closed) so the provider-shape guard has runtime teeth.
