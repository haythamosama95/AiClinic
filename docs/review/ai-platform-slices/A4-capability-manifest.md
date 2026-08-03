# Slice Review Report — A4: Capability Manifest Schema & Loader

**Spec:** `specs/018-ai-capability-manifest/spec.md` · **Branch:** `ai/018-a4-capability-manifest` · **Canonical:** §5.1, §5.7

## Executive Summary

The schema covers all ten §5.1 field groups with the correct contents, the `single_shot` default and conversational-field rejection work, and the ten per-group omission/malformation tests (T-A4-01…17) are present and meaningful. Two structural problems: (1) the loader contract's headline property — "an in-place edit to a published version **fails the build**" — is not wired to any build; the registry mechanism exists only as a function called from unit tests, and no checked-in registry file exists; (2) the manifest's immutability is theatre — a Proxy that silently swallows writes to one field while leaving all other groups freely mutable. The `unknown`-typed field pattern from A3 repeats here.

## Critical Issues

1. **In-place-edit build gate is not implemented — only simulated in a test.** The spec froze: "A checked-in append-only registry mapping `(capability_id, version)` → manifest content hash; the build computes the manifest hash and fails if it differs" (spec Clarifications, 2026-07-30; FR-004, SC-003). Evidence against: `verifyPublishedRegistry` is called only from `test/manifest.test.ts` and `test/conversational-manifest.test.ts` (grep of `src/`, scripts, package.json); `ai-platform/package.json` has no build/validate script (`"test": "vitest run"` only); no checked-in capability-manifest registry file exists anywhere in the repo (only test/eval fixtures). Nothing computes manifest hashes at build time, so an in-place edit to a published manifest would ship undetected. The "Done when" of A4 is met only in the sense that a function *could* fail a build if something called it.

## Bugs

1. **Manifest mutation is silently swallowed, not rejected** (`src/manifest/index.ts:379-386`). The Proxy `set` trap returns `true` without mutating when `prop === "interactionMode"` — a caller assigning `manifest.interactionMode = "conversational"` receives no error and no effect. Fail-silent mutation of a contract object is worse than throwing: the caller proceeds believing the mode changed. T-A4-17 (`test/manifest.test.ts:287-296`) codifies this by asserting the assignment has no effect.
2. **All other manifest groups are mutable at runtime.** The Proxy passes every non-`interactionMode` write through `Reflect.set`. `loaded.Output.mode = "structured"` on a published manifest succeeds. §5.1's "immutable per version" is enforced for zero fields (the one "protected" field is protected by silent discard, not immutability).

## Architectural Deviations

1. **Provider/model guard is trivially bypassable (§5.1 "A manifest never names a provider or a model").** `assertRoutingNeverNamesProviderOrModel` rejects only the two literal keys `provider` and `model` in the Routing group (`index.ts:83, 277-287`). `Routing: { preferredProvider: "gemini" }`, `Prompt binding: { modelHint: "gpt-4" }`, or any provider-shaped key anywhere else loads cleanly, since `assertManifestKeys` checks required-key presence but never rejects unknown keys. T-A4-16 tests exactly the two literal keys the guard checks, so the test proves the guard, not the property.
2. **Field typing repeats A3's `unknown` pattern.** Every group field is `unknown` (`ManifestGroupRecord`, `index.ts:87-89`); e.g. `Output.mode` is not constrained to `prose | structured | structured_atomic` (FR-009) and `Governance.acceptanceMode` is not constrained to the three §5.1 values (FR-010) — neither at type level nor at validation time. A manifest with `acceptanceMode: "yolo"` loads. The schema validates *shape* (key presence) but almost no *content*, despite FR-001 freezing "the field contents … of each group".
3. **Scope creep into H1:** `validateConversationalContextRequirements` validates `permittedKeySet` contents against the context-key vocabulary (`index.ts:195-225`), which the spec explicitly assigns to H1 ("A4 enforces the presence/absence rule, H1 validates the field contents", spec Out of Scope). Harmless but a boundary violation. (Likely an H1-era edit to this file; noted for the H1 review.)

## Missing or Weak Tests

1. **No test that the registry gate runs in the build** — impossible, since nothing runs it (Critical Issue 1).
2. **No rejection test for unknown/extra keys** in any group — extra keys are silently accepted, so schema drift (a misspelled required key plus a correct one, an injected provider hint) passes.
3. **No content-enum tests** for `Output.mode`, `Governance.acceptanceMode`, `Identity.lifecycleState` — invalid values load.
4. **No test that mutating a non-`interactionMode` field fails** — the mutable-runtime defect is untested.

## Recommended Improvements

- Add a build/CI step (e.g. `scripts/verify-manifests.ts` wired into package.json) that walks checked-in manifests, computes hashes, and runs `verifyPublishedRegistry` against a checked-in append-only registry file; check in the registry.
- Replace the Proxy with `Object.freeze` (deep) so mutation throws in strict mode instead of being silently swallowed; drop the swallow trap.
- Reject unknown keys per group in `assertManifestKeys` (exact key-set equality), and extend the provider/model guard to a denylist pattern across all groups, or validate Routing values against the routing-policy registry.
- Use a real content hash (WebCrypto SHA-256) instead of 32-bit FNV-1a (`index.ts:405-412`) — collision resistance matters if the registry is the integrity anchor, and Workers provides it natively.
- Constrain enum fields (`interactionMode` already is; add `mode`, `acceptanceMode`, `lifecycleState`) at validation time.
