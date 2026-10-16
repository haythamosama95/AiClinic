# Implementation Plan: Administrator billing: offers, contact and checkout flow

**Branch**: `ai/091-abo-p6-3-administrator-billing-offers-contact-checkout` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

An administrator opens billing from the live desktop shell, accepts the current terms, saves a billing contact, and checks out in the system browser. Polling reaches Active, and the desktop calls `request_ai_status_refresh`. This is phase P6, size L, and **Depends** P6.1 and P4.5.

## Technical Context

**Language/Version**: Dart / Flutter stable. Desktop app in `frontend/`.

**Primary Dependencies**: Existing `url_launcher` (`frontend/pubspec.yaml`), the existing app router, `issue_billing_token(p_contract_version)`, and `request_ai_status_refresh(p_contract_version)`. The ABO base URL is `abo_base_url` from the token response. Hostname for those calls is `billing.<vendor-domain>`. No new library. `aboClinic` and `backendRpc` stay the constants in `frontend/lib/core/contract_versions.dart`.

**Storage**: N/A. This unit defines no entities. The tenant is the token's `org` only. Nothing about the tenant is stored on the desktop.

**Testing**: Harness H-FL on H-FS. One Dart file tagged `fullstack` under `frontend/test/integration/`. Payment uses the H-PAY fixtures `abo/test/fixtures/paymob/success.json` and `abo/test/fixtures/paymob/decline.json` on the running stack. No `integration_test/` driver (OQ-6). Titles start with the E2E id (rule V3). The seven tests are written to fail before the production changes. The tests do not start wrangler and do not run `npm test` in `e2e/fullstack/`.

**Target Platform**: Flutter desktop. Administrator billing is a route opened from the renew action and the renew or buy action.

**Project Type**: Frontend. The unit row names no wiring exception. This unit does not change `backend/`, `abo/`, `ai-platform/`, `packages/vendor-contracts/`, or `e2e/fullstack/`.

**Performance Goals**: The billing token's `exp − iat` is ≤ 300 s, and the client renews it before that lifetime ends. `issue_billing_token` is 20 per user per 10 minutes. Checkout polling repeats while the shown state is Waiting or Paid. `request_ai_status_refresh` is one call when the shown state becomes Active.

**Constraints**: Administrator-only entry. Staff have no billing control and the desktop never calls `issue_billing_token` for that session. Every ABO call sends `Authorization: Bearer <billing token>` and `Abo-Contract-Version` set to `aboClinic`. `POST` and `PUT` send `client_request_id` and are idempotent per tenant. The desktop does not grant coverage. Payment history, `GET /v1/subscription`, and `GET /v1/payments` stay with P6.4. Status reads on open, resume, `next_change_at`, and the 5-minute timer stay with P6.1. The denial taxonomy and the administrator gauge stay with P6.2.

**Scale/Scope**: Size L (rule S3: four user stories, one codebase, seven E2E ids). Implied task count is 33 (the sequencing below).

The checkout read and the open list use the shapes already written into 04 §2.2. `GET /v1/checkouts/{id}` is `{contract_version, reference, shown_state, offer, payment_reference, term_ref, updated_at}`. `shown_state` is `Waiting`, `Failed`, `Paid`, `Active`, or `Abandoned`. `offer` is `{offer_id, version, term_unit, term_count, charged_price_minor, currency}` with `version` the checkout's `offer_version`. `payment_reference` and `term_ref` are JSON null. `updated_at` is `checkout_status.last_event_at`. The path `{id}` is the POST `checkout_id` and is not a field of that body. `GET /v1/checkouts?open=1` is `{contract_version, checkouts}` of that same object for `checkout_status.state` of `open`, `paid`, or `paid_late`. Another desktop resumes by `reference`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no `research.md`. Freezes are CP-E, which is a checkpoint and not a wire shape, so there is no `contracts/` directory. The spec defines no entities, so there is no `data-model.md`. The same boxes hold after this plan. This unit adds no constitution violation, so Complexity Tracking stays empty.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  A clinic administrator buys or queues AI coverage from the desktop. A staff member has no billing entry. An active clinic sees that a new purchase starts after the current term (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The change is the Flutter desktop. Checkout, payment, and grant stay on the ABO and the platform. No new worker, queue, or service (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Flutter owns the billing screens, the billing-token client, the ABO client, `url_launcher`, polling, and the call to `request_ai_status_refresh` when the checkout shows Active. Supabase exposes the two RPCs. The ABO owns offers, billing contact, checkout, and payment. The desktop does not grant coverage (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit defines no tables. `issue_billing_token` and `request_ai_status_refresh` stay the existing RPCs. The desktop calls them. Clinic-side integrity stays in PostgreSQL (spec §4.1, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `issue_billing_token` is `administrator` only. Every ABO call carries the billing token and `Abo-Contract-Version`. The tenant is the token's `org` only. The desktop stores nothing for that tenant and deletes nothing (spec §4.1, 04 §2.1, 02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  The administrator starts checkout. The desktop does not write coverage. An unsupported ABO contract version shows the existing inline update state. `provider_unavailable` and Abandoned stay on the billing screens. Clinical work is not hard-locked (spec §4.1, 02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One administrator billing flow on the existing desktop shell. |
| II. Replaceable layer boundaries | Codebase is frontend. The ABO remains the source of offers, contact, and checkout. |
| III. Backend authority and data integrity | No tables. Token mint and status refresh stay RPCs. The shown state is the value the checkout read returns. |
| IV. Secure and human-gated operations | Staff cannot open billing and cannot mint a billing token. The tenant comes from the session. |
| V. Operational continuity | Closing the app mid-payment still provisions. The update state and Abandoned stay inline. |
| Workflow automation | Polling is the checkout screen repeating one read. No second scheduler and no queue. |
| Higher operational burden | No new operational part. The Dart tests extend harness H-FL. |

## Project Structure

### Documentation (this feature)

```text
specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/
├── plan.md
├── spec.md
└── quickstart.md          # after this unit's H-FL tests are green; outline below
```

`research.md` is omitted. Spikes are none. `data-model.md` is omitted. The spec defines no entities. `contracts/` is omitted. CP-E is not a wire shape.

`quickstart.md` is not written in this phase. After the harness is green, implement fills only these sections:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only, from `frontend/`:
  - `flutter test test/integration/administrator_billing_fullstack_test.dart --tags fullstack`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour (none are expected)

### Source Code (repository root)

```text
frontend/lib/app/app_routes.dart
frontend/lib/app/router.dart
frontend/lib/features/ai/billing/billing_token_client.dart
frontend/lib/features/ai/billing/abo_client.dart
frontend/lib/features/ai/billing/offers_screen.dart
frontend/lib/features/ai/billing/billing_contact_form.dart
frontend/lib/features/ai/billing/checkout_screen.dart
frontend/lib/features/ai/billing/administrator_billing_page.dart
frontend/lib/features/ai/host/ai_feature_host_page.dart
frontend/lib/features/ai/degraded/ai_degraded_view.dart
frontend/lib/l10n/app_en.arb
frontend/lib/l10n/app_ar.arb
frontend/lib/l10n/app_localizations.dart
frontend/lib/l10n/app_localizations_en.dart
frontend/lib/l10n/app_localizations_ar.dart
frontend/test/integration/administrator_billing_fullstack_test.dart
```

**Structure Decision**: Frontend only. The route is registered in `frontend/lib/app/router.dart` and named in `frontend/lib/app/app_routes.dart`. `AiPage` already composes `AiFeatureHostPage`; this unit does not change `ai_page.dart`. The renew action and the renew or buy action push the billing route. Screens, the billing-token client, and the ABO client live in `frontend/lib/features/ai/billing/`. `url_launcher` is already a dependency. H-FL for these seven ids is the tagged fullstack file, and each test pumps the shell widgets. `frontend/lib/core/contract_versions.dart` is not modified.

## Consumes Binding

None. The unit contract's Consumes cell is none. P6.1 and P4.5 publish no Outputs / freezes line. This unit does not modify their modules.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | Create. Call `issue_billing_token` with `p_contract_version` set to `backendRpc`. Read `{token, abo_base_url, expires_at}`. Mint when the billing page is opened and again before the current token's `expires_at`. Keep the token in memory for that page only. Do not write the tenant, the token, or the checkout | FR-002, FR-005, FR-008 |
| `frontend/lib/features/ai/billing/abo_client.dart` | Create. Send `Authorization: Bearer <billing token>` and `Abo-Contract-Version` set to `aboClinic` on every call to `abo_base_url`. `GET /v1/offers` reads `offers[]` (`offer_id`, `version`, `plan_display_name`, `term_unit`, `term_count`, `price_minor`, `currency`, `allowance_credits`, `grace_days`, localized `copy`) and `terms` (`version` and text). `GET /v1/billing-contact` reads `version`, `name`, `email`, `phone`, or `not_found`. `PUT /v1/billing-contact` sends `client_request_id`, `name`, `email`, and `phone` in E.164 and reads the new version. `POST /v1/checkouts` sends `client_request_id`, `offer_id`, `offer_version`, and `terms_version`, and reads `checkout_id`, `reference`, `redirect_url`, `expires_at`, and `starts` (`now` or `after_current`, with `projected_start`). `GET /v1/checkouts/{id}` and each `GET /v1/checkouts?open=1` element use the checkout object in Technical Context. The same `client_request_id` is reused for a repeated submit of the same PUT or POST. Map `offer_unavailable` (409, body includes the current version), `billing_contact_required` (409), `terms_not_accepted` (409), `provider_unavailable` (503), `rate_limited` (429), and `contract_version_unsupported` (400, `accepted_versions`) | FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-009 |
| `frontend/lib/features/ai/billing/offers_screen.dart` | Create. Show the offers and the terms text. The administrator accepts the current terms on this screen before checkout. Offer `copy` stays the localized text from the response | FR-001, FR-003 |
| `frontend/lib/features/ai/billing/billing_contact_form.dart` | Create. Show the saved contact or an empty form when the read is `not_found`. Save with the PUT. A checkout that returns `billing_contact_required` stays on this form | FR-001, FR-004, FR-007 |
| `frontend/lib/features/ai/billing/checkout_screen.dart` | Create. Before `url_launcher`, show whether the term queues. `starts` `after_current` shows "starts after the current term". Open `redirect_url` with `launchUrl` and `LaunchMode.externalApplication`. Poll `GET /v1/checkouts/{id}` on a one-second timer while `shown_state` is Waiting or Paid, and stop on Failed, Active, or Abandoned. Failed stays on this page. A later success on this page shows Active. When `shown_state` is Active, call `request_ai_status_refresh` with `p_contract_version` set to `backendRpc` once. `offer_unavailable` loads offers again and shows the new price before a launch. `terms_not_accepted` returns to the offers screen. `provider_unavailable` is shown here; a later read of Abandoned is that shown state. `rate_limited` is shown here. `contract_version_unsupported` shows `AiDegradedView` in the existing app-update mode ("Update the app to use AI"), inline, with no dialog | FR-001, FR-004, FR-006, FR-007, FR-009 |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | Create. The route builds this page for an administrator. It loads `GET /v1/checkouts?open=1` and, when a checkout is listed, shows that checkout by `reference` instead of starting another one. Otherwise it sequences offers, then contact, then checkout. It takes no tenant argument. A staff session does not build it and does not construct the token client | FR-001, FR-005, FR-008, FR-009 |
| `frontend/lib/app/app_routes.dart` | Modify. Add the administrator billing path next to the existing AI routes | FR-001 |
| `frontend/lib/app/router.dart` | Modify. Register that path. The builder opens `administrator_billing_page.dart` for an administrator and does not mint a token for anyone else | FR-001, FR-008 |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | Modify. The administrator renew control (`ai_notice_renew`) pushes the billing route. The staff notice stays the text with no purchase control | FR-001, FR-008 |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | Modify. The administrator renew or buy control (`kAiDegradedRenewOrBuyKey`) pushes the billing route. Staff still do not see that control | FR-001, FR-008 |
| `frontend/lib/l10n/app_en.arb` | Modify. English strings for the offers screen, the contact form, the checkout shown states, "starts after the current term", and the five ABO errors | FR-001 |
| `frontend/lib/l10n/app_ar.arb` | Modify. Arabic strings for those same keys | FR-001 |
| `frontend/lib/l10n/app_localizations.dart` | Modify. Generated from the arb files | FR-001 |
| `frontend/lib/l10n/app_localizations_en.dart` | Modify. Generated from the arb files | FR-001 |
| `frontend/lib/l10n/app_localizations_ar.dart` | Modify. Generated from the arb files | FR-001 |
| `frontend/test/integration/administrator_billing_fullstack_test.dart` | Create. Tagged `fullstack`. Seven tests, titles prefixed `E2E-P6.3-01` through `E2E-P6.3-07` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/quickstart.md` | Create after this unit's H-FL tests are green | FR-001, FR-006 |

`frontend/lib/features/ai/presentation/pages/ai_page.dart` already composes the host the renew action sits on. This unit does not change it. `frontend/pubspec.yaml` already depends on `url_launcher`. This unit does not change it.

## Test Layout

Harness H-FL on H-FS. One file, tagged `fullstack`. Each test pumps the shell from the renew action on `AiFeatureHostPage` or the renew or buy action on `AiDegradedView`, through the route in `router.dart`. `UrlLauncherPlatform` records `redirect_url` and does not open a browser. After that launch, the test completes payment by replaying the H-PAY fixture onto the running stack. The desktop never signs or posts the callback. The test does not boot wrangler. A row is one test (rule V3). Each new test is red before the production change it names. No `integration_test/` driver.

| ID | Title prefix | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P6.3-01 | `E2E-P6.3-01` | Renew action → billing route → offers screen → contact form → checkout screen → `url_launcher` → poll → `request_ai_status_refresh` → `get_ai_status` → the live AI submit | Offers, contact, and checkout complete. The stub payment is `success.json`. Polling shows Active. The refresh RPC runs. `get_ai_status` is active. An AI request succeeds |
| E2E-P6.3-02 | `E2E-P6.3-02` | Two in-memory clients for the same clinic, different branch claims, each opening the billing route → `GET /v1/checkouts?open=1` | The second session sees the open checkout by `reference` and, after payment, Active. The first session is disposed while payment is in progress, and provisioning still finishes. `get_ai_status` is active on open. Neither client is given a tenant to write |
| E2E-P6.3-03 | `E2E-P6.3-03` | The checkout screen, after an active clinic posts checkout | The screen shows "starts after the current term" before `launchUrl`. The POST body answer is `starts` `after_current` |
| E2E-P6.3-04 | `E2E-P6.3-04` | The checkout screen, on `POST /v1/checkouts`, after the running catalogue moves the sellable version | The POST of the version the screen held returns `offer_unavailable`. The screen shows the new price from a fresh offers read before any launch |
| E2E-P6.3-05 | `E2E-P6.3-05` | The same checkout page, polling `GET /v1/checkouts/{id}` | `decline.json` leaves the page on Failed. A later `success.json` on that same page shows Active |
| E2E-P6.3-06 | `E2E-P6.3-06` | Staff session of `AiFeatureHostPage` in the app shell | The renew control and the renew or buy control are absent. The recording session client sees no `issue_billing_token` call |
| E2E-P6.3-07 | `E2E-P6.3-07` | The administrator billing screens, with `Abo-Contract-Version` outside the accepted pair | The ABO answers `contract_version_unsupported`. The billing screens show the app-update state and no dialog |

## Sequencing

Tests before implementation. The new tests are observed failing, then the desktop changes, then those tests pass. Implied task count: 33.

1. Add the failing `E2E-P6.3-01` test in `administrator_billing_fullstack_test.dart`.
2. Add the failing `E2E-P6.3-02` test in the same file.
3. Add the failing `E2E-P6.3-03` test in the same file.
4. Add the failing `E2E-P6.3-04` test in the same file.
5. Add the failing `E2E-P6.3-05` test in the same file.
6. Add the failing `E2E-P6.3-06` test in the same file.
7. Add the failing `E2E-P6.3-07` test in the same file.
8. From `frontend/`, run `flutter test test/integration/administrator_billing_fullstack_test.dart --tags fullstack` against the running H-FS stack and confirm E2E-P6.3-01 through E2E-P6.3-07 fail.
9. Add the English billing strings to `app_en.arb`.
10. Add the Arabic strings for those keys to `app_ar.arb`.
11. Regenerate `app_localizations.dart`, `app_localizations_en.dart`, and `app_localizations_ar.dart`.
12. Add the billing path and register it on the router for an administrator.
13. Push that route from the host renew control.
14. Push that route from the degraded renew or buy control.
15. Add the billing-token client: mint on open, renew before `expires_at`, memory only.
16. Add the ABO client transport with the bearer token and `Abo-Contract-Version`.
17. Parse offers and terms on that client.
18. Parse billing-contact read and save on that client.
19. Parse checkout create, checkout read, the open list, and the error codes on that client.
20. Build the offers screen and accept the current terms there.
21. Build the billing-contact form.
22. Build the checkout screen and show `shown_state`.
23. Show "starts after the current term" before `launchUrl`.
24. Poll by `checkout_id` while the shown state is Waiting or Paid.
25. On Active, call `request_ai_status_refresh` once.
26. Resume a listed checkout by `reference` with no tenant argument.
27. Handle the five ABO errors, and show the new price after `offer_unavailable`.
28. Show the app-update state when the ABO answers `contract_version_unsupported`.
29. Keep Failed on the same checkout page so a later success shows Active.
30. Keep the staff host free of a billing control and of a token mint.
31. Compose offers, contact, and checkout on the page the route builds, including the open-list resume.
32. Re-run the fullstack file until E2E-P6.3-01 through E2E-P6.3-07 pass.
33. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded in 02 §7 for this unit. Nothing to justify.
