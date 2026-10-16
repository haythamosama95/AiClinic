# Quickstart: Entitle-and-grant operator path and live `context_required` self-heal (I4)

I4 adds the operator-authenticated `POST /control/installations/{id}/entitle` mutation (activate pending entitlement, write capability grants, journal audit) and hosts J2 `ContextRequiredSelfHeal` on the I3 live submit path via a production `DiscoveryManifestRefreshPort`.

**Scope rule:** This quickstart covers **only slice I4**. It lists I4 files, I4 tests, and I4 commands — not prior-slice regression suites or combined platform counts.

## 1. Architecture context

- **Delivery plan row:** I4 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) — entitle-and-grant operator path and live `context_required` self-heal (CP6).
- **Architecture sections:** `§4.5` (control-plane entitle/grant), `§7.3` (entitlement / `capability_grant` / `control_audit` shapes), `§8.4` and `§5.2` (client self-heal bound).
- **Spec delivered:** Combined operator entitle mutation; pending enroll fails closed until activated; live E2 submit path performs one-shot `context_required` self-heal with same idempotency key; eight named tests (T1–T8).
- **Plan scoped:** `entitle.ts` + control dispatch, `discovery_manifest_refresh_port.dart`, surface/host/hub composition hooks — Consumes B2/I3/J2 modules unchanged aside from wiring.

## 2. What was implemented

- **Combined `/entitle` mutation** — `handleEntitle` activates entitlement budget fields, inserts `capability_grant` row(s), journals `control_audit` with operator identity in one D1 batch.
- **Production `ManifestRefreshPort`** — `DiscoveryManifestRefreshPort` refreshes via I3 `DiscoveryClient` and reads `interactionMode` from cached manifests.
- **Live self-heal hosting** — `FirstAiFeatureSurface._invoke` calls `ContextRequiredSelfHeal.invoke` instead of raw `sdk.invoke`; port injected through `AiFeatureHostDependencies`.

See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/control/entitle.ts` | Combined operator entitle handler |
| `ai-platform/src/control/types.ts` | `EntitlePayload` / grant input types |
| `ai-platform/src/control/index.ts` | `/entitle` route dispatch |
| `ai-platform/test/entitle-grant.test.ts` | Named tests T1–T4 (Workers integration) |
| `frontend/lib/core/ai/discovery_manifest_refresh_port.dart` | Production `ManifestRefreshPort` |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | `_invoke` heal hosting |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | `manifestRefreshPort` in host deps |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | Hub constructs production refresh port |
| `frontend/test/widget/ai/live_context_required_self_heal_test.dart` | Named tests T5–T8 (Flutter) |

## 4. Prerequisites

- **Workers pool:** Node.js and `ai-platform` dependencies (`npm install` in `ai-platform/`).
- **Flutter:** SDK per `frontend/pubspec.yaml` for widget tests.
- **Operator bindings:** When exercising control e2e via `SELF.fetch`, Miniflare must expose `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID` (same as B2 `control.test.ts`).

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run --config vitest.workers.config.ts test/entitle-grant.test.ts
```

Expected: **4 passing tests** (T1–T4).

```bash
cd frontend
flutter test test/widget/ai/live_context_required_self_heal_test.dart
```

Expected: **4 passing tests** (T5–T8).

## 6. Inspect the changes

1. Open `ai-platform/src/control/entitle.ts` — combined entitlement update, grant inserts, and `entitle` audit row.
2. Open `ai-platform/src/control/index.ts` — `entitle` action in `dispatchControlRequest`.
3. Open `frontend/lib/core/ai/discovery_manifest_refresh_port.dart` — discovery-backed refresh and `interactionModeFor`.
4. Open `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` — `ContextRequiredSelfHeal` in `_invoke`.
5. Confirm Consumes modules (`lifecycle.ts`, `context_required_self_heal.dart`, I3 mint/submit) are not rewritten — composition only.

## 7. Manual validation

Optional CP6 review: operator `curl` entitle against a local Worker for a pending installation, then exercise the desktop `/ai` host with a stale manifest to observe one-round self-heal. Omit when CI alone proves Done when.
