# Quickstart: First AI feature surface and degraded mode (E4)

E4 lands the first Flutter AI Feature Surface (`prose` / `advisory_display`), first-class degraded-mode UI, and the clinic-side AI availability flag so non-enrolled clinics hide AI affordances without probing the platform.

## 1. Architecture context

- **Delivery plan** — Band E row E4 in [`docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.6: first user-visible Feature Surfaces + degraded mode + AI availability flag.
- **Architecture** — Implements `docs/architecture/ai-platform/01-ai-platform.md` §4.1 (Feature Surfaces), §6.4 (provisional `prose` rules), §13.2 (request reference), §4.2 (availability flag), §5.4 (taxonomy client behaviours), and A11 (AI never blocks clinical work).
- **Spec** — Provisional draft rendering with no commit before `completed`, terminal-payload authority, accept/discard under `advisory_display`, request reference on every failure, and distinct degraded states.
- **Plan** — Flutter modules under `frontend/lib/features/ai/`, widget spy suite T1–T21, Supabase `get_ai_availability` migration, frozen `contracts/ai-availability-flag.md`, standalone host route for tests/CP3.

## 2. What was implemented

- First AI Feature Surface for `clinic.visit_summary` (`prose`, `advisory_display`) wired to E2 SDK + E3 Context Resolver.
- Provisional prose view (draft Key + `surfaceAi` / `textAi` / `borderAi` tokens), request-reference view, accept/discard after terminal `completed`.
- Degraded-mode states (non-enrolled, unreachable, quota, AI unavailable, installation suspended, forbidden capability).
- Clinic AI availability flag (`ai.availability` on `ai_internal.app_settings`) + `public.get_ai_availability()`.
- Standalone `AiFeatureHostPage` and `/ai/feature-host` route for widget tests and CP3 entry.

See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `frontend/lib/features/ai/availability/` | Availability model + Supabase reader |
| `frontend/lib/features/ai/degraded/` | Degraded state map + first-class UI |
| `frontend/lib/features/ai/surface/` | Provisional prose, request reference, first surface |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | Availability gate + surface host |
| `frontend/lib/app/app_routes.dart` | `aiFeatureHost` route constant |
| `frontend/lib/app/router.dart` | Host route registration |
| `frontend/test/widget/ai/` | Widget spy harness + T1–T21 suites |
| `backend/supabase/migrations/20260802140000_ai_availability_flag.sql` | Availability flag seed + RPC |
| `specs/038-first-ai-feature-surface/contracts/ai-availability-flag.md` | Frozen clinic-readable shape |

## 4. Run the automated suite

From the repository root:

```bash
cd frontend
flutter test test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart
```

Expected: **21 passing tests** (13 surface + 8 degraded/flag).

## 5. Inspect the changes

- Open `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` — E2 invoke + E3 resolve, terminal-payload display, accept/discard gating.
- Open `frontend/lib/features/ai/degraded/ai_degraded_view.dart` — distinct degraded banners (not error dialogs).
- Read `specs/038-first-ai-feature-surface/contracts/ai-availability-flag.md` — frozen `{ enrolled, platform_base_url }` shape.
- Run a focused widget test, e.g. `flutter test test/widget/ai/first_ai_feature_surface_test.dart --name surface_accept`.
- Confirm E1 guard stays clean: `dart run tool/architecture_guard/architecture_guard.dart` from `frontend/`.

## 6. Manual validation

Optional: when enrolled via the availability RPC, navigate to `/ai/feature-host` in a dev build to visually confirm provisional draft styling and degraded banners. Widget tests remain the primary verification path.
