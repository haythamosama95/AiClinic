# Slice Review: J2 — `context_required` self-healing round trip

**Reviewed against:** `docs/architecture/17-ai-platform.md` §8.4 and §5.2 (source of truth); `specs/049-context-required-self-healing/` (spec, plan, tasks, quickstart; no `contracts/` by design).
**Implementation reviewed:** `frontend/lib/core/ai/context_required_self_heal.dart`, the `PlatformHttpException` extension in `frontend/lib/core/ai/ports.dart`, the consumed E2/E3 surfaces (`frontend/lib/core/ai/ai_client_sdk.dart`, `context_resolver.dart`) for binding correctness, plus `frontend/test/unit/core/ai/context_required_self_heal_test.dart` and the J2 additions to `frontend/test/unit/core/ai/fakes.dart`.
**Method:** Static review only; no build, no test execution.

## 1. Executive Summary

J2 delivers the §8.4 shape faithfully at the control-flow level: a `single_shot`-gated heal loop that refreshes once, resolves the C2-named keys through the E3 Resolver, resubmits once, rethrows a second `context_required` (whose `requestReference` is both on the exception and recorded as `sdk.lastRequestReference`), and never loops to a third attempt. Conversational mode bypasses the loop entirely, the consumed C2/E2/E3 modules are not rewritten (the `ports.dart` extension matches Clarification Q2 exactly), no Worker or backend file is touched, and R-12 is respected.

However, the slice's central invariant — **resubmit once with the same idempotency key** — is not actually owned by the code that the plan says owns it. The plan's Structure Decision states "the heal helper owns a stable key factory for the action," and the helper's constructor accepts `idempotencyKeyFactory`, but the parameter is silently dropped and the resubmission goes through `AiClientSdk.invoke`, which mints a fresh key per call. Same-key behavior therefore depends entirely on the caller pre-configuring the *shared* SDK with a stable factory — which the default SDK factory does not provide and which no production call site does, because nothing in `frontend/lib` constructs `ContextRequiredSelfHeal` at all. With the default configuration the resubmission carries a **new** idempotency key: the B4 Quota DO sees a second, never-before-admitted action rather than the same action resubmitted, defeating FR-005 and the §6.6 idempotency interaction the architecture relies on. Secondary findings: a `ContextResolveFailure` is silently swallowed into a doomed resubmit that burns the single heal attempt, and the conversational exclusion rests on a hand-set constructor enum rather than the capability's manifest-declared interaction mode.

All four required test cases exist by name, but the happy-path test masks the dead factory parameter (it injects the same constant factory into both the SDK and the heal, so it cannot distinguish "heal owns the key" from "SDK happened to be configured that way"), and the resolve-failure and payload-less branches are untested.

## 2. Critical Issues

None found.

## 3. Bugs

- **[High] `idempotencyKeyFactory` is accepted by the heal helper and silently dropped; same-key resubmission is not guaranteed** — `frontend/lib/core/ai/context_required_self_heal.dart:26` declares the parameter; the initializer list (`context_required_self_heal.dart:27-30`) never assigns it, and the resubmission at `context_required_self_heal.dart:48` simply calls `_sdk.invoke(currentInput)` again. `AiClientSdk.invoke` mints the key per call (`ai_client_sdk.dart:38`), defaulting to a random 16-hex-digit key (`ai_client_sdk.dart:88-91`). So under the default SDK configuration the "resubmit once with the same idempotency key" requirement (FR-005; §8.4; spec Edge case "same idempotency key on resubmit") is violated: the resubmission is a brand-new idempotency identity. Because the original 422 was rejected at context validation (pre-admission), the resubmission *should* be a first admission under the **same** key; with a fresh key the B4 Quota DO admits what looks like a second independent user action — double-counted quota and no idempotent linkage to the rejected attempt. The plan explicitly assigns ownership to the heal ("the heal helper owns a stable key factory for the action and drives `AiClientSdk.invoke`", plan Structure Decision), so this is both a behavioral bug and a plan-vs-code mismatch. The dead parameter makes it worse: a caller reading the constructor reasonably believes passing a factory secures the invariant, as the tests themselves do (`context_required_self_heal_test.dart:27`). Note also that the suggested workaround — configuring a constant factory on the shared SDK — is unsafe in production, since one SDK instance serves many actions and a constant factory would collapse idempotency across *distinct* user actions; the heal genuinely needs to pin the key for its own two submits (e.g. by threading the key through `CapabilityInvokeInput` or a per-invoke override), which the current transport-only SDK surface does not allow.
- **[Medium] `ContextResolveFailure` is silently swallowed into a resubmit with unchanged context** — `context_required_self_heal.dart:61-64`: if the resolver returns `ContextResolveFailure` (e.g. `unknown_context_key` because the client's E3 registry predates the newly required key — the exact stale-client population this slice serves), the code falls through and resubmits the original context verbatim. The one automatic resubmission is spent on a request the client already knows cannot pass validation, and the typed failure reason (`unknown_context_key`, the offending key) is dropped rather than surfaced. The user ultimately sees a second `context_required`, which is the *wrong* defect signal: the real defect is local (registry gap), not platform-side. The failure branch should short-circuit the heal and surface immediately.
- **[Low] Payload-less `context_required` burns the single heal attempt** — `context_required_self_heal.dart:60`: `error.missingKeys ?? const <String>[]` means a `context_required` arriving without the C2 missing-key manifest (malformed payload, intermediary stripping the body) triggers refresh + `resolve([])` (which succeeds with an empty payload, `context_resolver.dart:45-47`) + a resubmit identical to the rejected request. A typed rejection whose entire value is its payload is treated as if it had named zero keys. Failing fast when `missingKeys` is null/empty would preserve the one attempt for a healable rejection.
- **[Low] `manifestVersion` / `manifestCapabilityId` are captured but never used** — `ports.dart:80-81` carries them (per Clarification Q2) and the fakes populate them (`fakes.dart:428-429`), but the heal resubmits with the original `input.capabilityVersion` (`context_required_self_heal.dart:81-88`). §5.2 Evolution ties "adding a required key" to a new capability version, so a stale client's resubmission against its old version relies on overlap-window resolution accepting the enriched context — plausible, but unexamined: no test or comment states the intended version semantics of the resubmit, and the refreshed manifest (FR-003) is never consulted for the version to use. At minimum the dead fields on the heal path deserve a documented decision.

## 4. Architectural Deviations

- **[Medium] Conversational exclusion is enforced by a hand-set constructor enum, not the capability's manifest-declared mode** — `context_required_self_heal.dart:5-8` introduces a second, client-config `InteractionMode` enum alongside the manifest's A14/H1-frozen `interactionMode` field, and the gate at `context_required_self_heal.dart:39-41` trusts it. FR-008 / §8.4 state conversational capabilities **must never** take this path; as implemented, a `ContextRequiredSelfHeal` constructed with `singleShot` will happily heal an invocation carrying `conversationId`/`transcript` for a conversational capability (`_mergeResolvedContext` even forwards those fields, `context_required_self_heal.dart:85-86`). The exclusion holds by caller discipline, not by the capability's declared mode — a parallel source of truth where the architecture froze one. Deriving the gate from the (refreshed) manifest's `interactionMode` for the submitted capability would close this; at minimum the duplication should be acknowledged.
- **[Low] No production wiring: the heal module is currently dead code** — nothing under `frontend/lib/` constructs `ContextRequiredSelfHeal` or implements `ManifestRefreshPort` (verified by search; only the module itself and tests reference them), although the plan states production "wires to C1 discovery revalidation" (Clarification Q3; plan Constraints). The Done-when behavior is therefore proven only against fakes. If wiring is deliberately deferred to E4/J-band integration, the plan/quickstart should say so; as written, the quickstart presents the slice as usable behavior (`quickstart.md` §2) when no call site exists.
- **Verified non-deviations (no-rework rule holds):** the `ports.dart` change is exactly the reserved optional-field extension (`ports.dart:60-82`); `AiClientSdk` remains transport-only and unmodified; the E3 Resolver API, C2 payload shape, and taxonomy are untouched; no `ai-platform/` or `backend/` file changed; the one-resubmission bound (`context_required_self_heal.dart:53`) and no-third-attempt behavior are structurally correct; request-reference surfacing on the second rejection works via both the rethrown exception and `AiClientSdk._recordRequestReference` (`ai_client_sdk.dart:59, 82-86`); no per-request server-side healing state is introduced; no prompt/provider/model identifiers appear in the new client code (R-12).

## 5. Missing or Weak Tests

Required-case status (delivery plan §3.11.8 J2 / spec Test plan):

| # | Required case | Status |
| --- | --- | --- |
| 1 | Stale client refreshes, resolves, resubmits once with same idempotency key, succeeds | **Present** (`context_required_self_heal_test.dart:10-48`) — but see weakness below |
| 2 | Second `context_required` stops and surfaces the request reference | **Present** (`context_required_self_heal_test.dart:49-89`) — asserts both the exception's `requestReference` and `sdk.lastRequestReference` |
| 3 | No automatic third attempt | **Present** (`context_required_self_heal_test.dart:90-127`) — spy counts prove submit=2, refresh=1, resolve=1 |
| 4 | Conversational capabilities never take the path | **Present** (`context_required_self_heal_test.dart:129-151`) — zero refresh/resolve, exactly one submit |

- **[Medium] Test 1's same-idempotency-key assertion masks the dead factory parameter** — the test injects `() => stableKey` into **both** the SDK (`context_required_self_heal_test.dart:21`) and the heal (`context_required_self_heal_test.dart:27`). The heal's factory does nothing, so the assertion `submit.idempotencyKeys == [stableKey, stableKey]` proves only that the SDK's injected factory is stable across two `invoke` calls — a property of the test harness, not of the slice. No test exercises the default-factory configuration (which would fail FR-005), and nothing would break in this suite if the heal's constructor parameter were deleted — it effectively has been.
- **[Medium] No test for the `ContextResolveFailure` branch** — the resolver-failure path (`context_required_self_heal.dart:62-64`, negative branch) is neither tested nor specified: the suite never constructs a resolver that returns `ContextResolveFailure`, so the silent doomed-resubmit behavior (§3) would regress unnoticed. Under the every-branch coverage rule and given that `unknown_context_key` is the most likely failure on a genuinely stale client, this branch needs a named case with a stated expected outcome.
- **[Low] No test for a payload-less `context_required`** — `missingKeys: null` is accepted by `contextRequiredErrorStep` (`fakes.dart:407, 417` falls back to a default key, so the suite *cannot* currently express a payload-less rejection without a new helper) and the null-coalescing branch at `context_required_self_heal.dart:60` is unexercised.
- **[Low] No test for non-`context_required` passthrough** — the rethrow branch at `context_required_self_heal.dart:50-52` (e.g. `quota_exhausted`, `context_invalid`) is uncovered in this suite. E2's own tests cover SDK-level passthrough generically, so this is a minor gap, but the heal's filter is new code whose selectivity (heal *only* `context_required`) is a stated rule of the slice.
- **[Low] Conversational exclusion is tested only at the constructor-flag level** — test 4 constructs the helper with `InteractionMode.conversational`; nothing tests the mismatch case (conversational `CapabilityInvokeInput` through a `singleShot`-gated helper), which is the configuration the architecture's "never" actually has to survive (see §4). A manifest-derived gate would make this testable against the capability declaration itself.

## 6. Recommended Improvements

1. **[High] Make the heal own the resubmission idempotency key, or delete the parameter.** Either (a) extend the E2 invoke surface so a caller can pin the idempotency key for a specific invocation (e.g. an optional `idempotencyKey` on `CapabilityInvokeInput`, defaulting to the factory), have the heal mint/capture the action's key once and reuse it on the resubmit — this matches the plan's stated design — or (b) remove `idempotencyKeyFactory` from the constructor and document that key stability is an SDK-construction concern, with a test proving the default configuration is *not* used for heal-wrapped actions. Option (a) also fixes the unsafe "constant factory on a shared SDK" workaround (§3; FR-005; §8.4).
2. **[Medium] Short-circuit on `ContextResolveFailure`.** Surface the typed resolution failure (with the offending key and the request reference from the original rejection) instead of resubmitting unchanged context; add a named test for the branch (§3, §5).
3. **[Medium] Gate the exclusion on the manifest-declared interaction mode.** Resolve the capability's `interactionMode` from the refreshed manifest (or require the caller to pass the manifest entry rather than a free-standing enum) so FR-008's "never" is enforced by the A14 declaration, not by parallel client config; remove or justify the duplicate `InteractionMode` enum (§4).
4. **[Low] Fail fast on payload-less `context_required`.** Treat null/empty `missingKeys` as unhealable and rethrow immediately, preserving the single attempt; extend `contextRequiredErrorStep` to allow an explicit null-payload case and test it (§3, §5).
5. **[Low] Decide and document the resubmission's capability-version semantics.** State whether the heal resubmits under the original `capabilityVersion` (relying on the overlap window) or the refreshed `manifestVersion`; use or remove the captured `manifestVersion`/`manifestCapabilityId` fields accordingly (§3; §5.2 Evolution; J1 overlap).
6. **[Low] Record the wiring gap honestly.** Either land the production construction of `ContextRequiredSelfHeal` + `ManifestRefreshPort` (C1 discovery revalidation) or state in plan/quickstart that wiring is deferred to a named later slice, so the Done-when is not read as already reachable from the app (§4).

---

## 7. Review Resolution

### 7.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **J2-R1 — Same-key idempotency ownership** | Bugs #1; Missing/Weak Tests #1; Recommended Improvements #1 | `frontend/lib/core/ai/context_required_self_heal.dart`; `context_required_self_heal_test.dart` (test 1 rewritten) |
| **J2-R2 — Short-circuit ContextResolveFailure** | Bugs #2; Missing/Weak Tests #2; Recommended Improvements #2 | `context_required_self_heal.dart` (`ContextHealResolveException`); test `context_resolve_failure_short_circuits_without_resubmit` |
| **J2-R3 — Fail fast on payload-less / empty missingKeys** | Bugs #3; Missing/Weak Tests #3; Recommended Improvements #4 | `context_required_self_heal.dart`; `fakes.dart` (`nullMissingKeys`); tests `payload_less_*`, `empty_missing_keys_*` |
| **J2-R4 — Manifest-declared interaction mode gate** | Architectural Deviations #1; Missing/Weak Tests #5; Recommended Improvements #3 | `ManifestRefreshPort.interactionModeFor`; removed constructor `InteractionMode`; tests 4 + `manifest_declared_conversational_mode_*` |
| **J2-R5 — Resubmit capability-version semantics** | Bugs #4; Recommended Improvements #5 | Keep original `capabilityVersion`; document C2 manifest fields as diagnostic; test `resubmit_keeps_original_capability_version_*` |
| **J2-R6 — Record wiring gap** | Architectural Deviations #2; Recommended Improvements #6 | Spec Kit `plan.md` Constraints, `quickstart.md` §2 — production C1/`ContextRequiredSelfHeal` wiring deferred |
| **J2-R7 — Non-context_required passthrough** | Missing/Weak Tests #4 | test `non_context_required_errors_passthrough_without_heal` |

Every numbered review item appears in exactly one stage. No escalations — all fixes stayed within J2 scope (Flutter sibling + Spec Kit). Architecture docs untouched.

### 7.2 Test cases created first

- **J2-R1:** Rewrote test 1 so the SDK factory would mint distinct keys per invoke (`sdk-minted-N`) while the heal factory supplies a stable key; asserts `submit.idempotencyKeys == [stableKey, stableKey]` and `sdkFactoryCalls == 0`.
- **J2-R2:** `context_resolve_failure_short_circuits_without_resubmit` — unknown key → `ContextHealResolveException` with typed failure + original request reference; submit count stays 1.
- **J2-R3:** `payload_less_context_required_rethrows_without_burning_heal_attempt` (`nullMissingKeys: true`) and `empty_missing_keys_context_required_rethrows_without_heal`.
- **J2-R4:** Updated test 4 to gate via `FakeManifestRefreshPort(modes: …)`; added `manifest_declared_conversational_mode_blocks_heal_even_for_single_shot_shaped_input`.
- **J2-R5:** `resubmit_keeps_original_capability_version_not_manifest_version` — rejection `manifestVersion: 2.0.0`, both submits keep `1.0.0`.
- **J2-R6:** documentation-only (no new production test).
- **J2-R7:** `non_context_required_errors_passthrough_without_heal` (`quota_exhausted`).

### 7.3 Fix implemented

- **J2-R1:** Heal stores `idempotencyKeyFactory`, mints once per action, and passes `idempotencyKey:` into both `AiClientSdk.invoke` calls (E2 per-invoke override already present).
- **J2-R2:** On `ContextResolveFailure`, throw `ContextHealResolveException` carrying the failure and the rejection's request reference — no resubmit.
- **J2-R3:** Null/empty `missingKeys` rethrows before refresh/resolve so the single heal attempt is preserved.
- **J2-R4:** Removed constructor `InteractionMode`; FR-008 gate reads `ManifestRefreshPort.interactionModeFor(capabilityId)` (re-checked after refresh).
- **J2-R5:** Resubmit keeps caller `capabilityVersion`; code comment + Spec Kit edge case state that C2 `manifestVersion` / `manifestCapabilityId` are diagnostic only (J1 overlap).
- **J2-R6:** Plan Constraints and quickstart §2 state that production construction / C1 wiring is deferred; Done-when is fake-proven in this slice.
- **J2-R7:** Passthrough coverage for non-`context_required` taxonomy codes.
- Spec Kit aligned: `spec.md` edge cases; `plan.md` Constraints / Structure Decision / Files; `quickstart.md`.

### 7.4 Verification

- Flutter AI unit suite: **105** tests passed (`frontend/test/unit/core/ai/`), including **10** in `context_required_self_heal_test.dart`.
- Full `ai-platform` suite (`npm test`): Node + Workers pools green (Workers: **19** files / **285** tests; prior full run also green for verify-manifests + Node pool).

Modified/added: `frontend/lib/core/ai/context_required_self_heal.dart`; `frontend/test/unit/core/ai/{context_required_self_heal_test,fakes}.dart`; Spec Kit under `specs/049-context-required-self-healing/`; this review resolution appendix.
