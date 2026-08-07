# Quickstart: Live client invoke on the first AI feature surface (I3)

I3 wires the Flutter `/ai` visit-summary host to the live Worker path: production AAT mint and HTTPS submit adapters, optional capability discovery for required context keys, SSE consume-to-terminal with provisional prose, and unchanged E4 degraded-mode behaviour.

**Scope rule:** This quickstart covers **only slice I3**. It lists I3 files, I3 tests, and I3 commands — not prior-slice regression suites or combined platform counts.

## 1. Architecture context

- **Delivery plan row:** I3 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) — live client invoke on the first AI feature surface (CP3 client half).
- **Architecture sections:** `§4.1` (client composition), `§5.5` (submit + SSE), `§5.4` (taxonomy / request reference), `§6.4` (provisional prose, no chunk assembly), `A11` (degraded / non-blocking).
- **Spec delivered:** Production mint/submit ports composed on the E4 hub; discovery client for required keys; eleven widget/integration tests (T1–T11).
- **Plan scoped:** `supabase_aat_mint_port.dart`, `https_submit_port.dart` (`PlatformHttpsSubmitPort`), `discovery_client.dart`, hub composition in `ai_page.dart`, and `live_client_invoke_test.dart` — no Worker or Consumes-module edits.

## 2. What was implemented

- **Production AAT mint** — `SupabaseAatMintPort` calling clinic `public.issue_ai_token`.
- **Production HTTPS submit** — `PlatformHttpsSubmitPort` posting to `POST /v1/requests` with A6 headers and streaming SSE.
- **Discovery client** — `GET /v1/capabilities` per I2 `discovery-http.md` (Bearer AAT, etag/`If-None-Match`, auth-failure taxonomy mapping).
- **Hub composition** — `_LiveVisitSummaryHost` / `composeLiveVisitSummaryHost` replaces unconfigured stubs; enables live invoke when enrolled.

See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | Production `AatMintPort` → `issue_ai_token` |
| `frontend/lib/core/ai/https_submit_port.dart` | Production `HttpsSubmitPort` → live SSE submit |
| `frontend/lib/core/ai/discovery_client.dart` | I2 discovery HTTP client + key extraction |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | Hub composition, `composeLiveVisitSummaryHost`, live host widget |
| `frontend/test/widget/ai/live_client_invoke_test.dart` | Named tests T1–T11 |

## 4. Run the automated suite

From the repository root:

```bash
cd frontend
flutter test test/widget/ai/live_client_invoke_test.dart
```

Expected: **12 passing tests** in this slice's file (eleven named T1–T11 cases plus one suspended-install discovery unit assertion).

## 5. Inspect the changes

1. Open `frontend/lib/features/ai/presentation/pages/ai_page.dart` — `composeLiveVisitSummaryHost` and `_LiveVisitSummaryHost` wire production ports and discovery.
2. Open `frontend/lib/core/ai/supabase_aat_mint_port.dart` and `https_submit_port.dart` — clinic mint and Worker submit clients.
3. Open `frontend/lib/core/ai/discovery_client.dart` — I2 wire consumption (auth failure → taxonomy, no manifests body).
4. Run the spy test: `flutter test test/widget/ai/live_client_invoke_test.dart --plain-name spy_production_mint_and_submit_ports_composed_on_hub`
5. Confirm R-12 guard on composition paths: `flutter test test/widget/ai/live_client_invoke_test.dart --plain-name live_host_contains_no_prompt_provider_or_model_identifiers`
