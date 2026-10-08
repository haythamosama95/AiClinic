# Administrator billing: offers, contact and checkout flow

**Unit**: P6.3 · **Branch**: `ai/091-abo-p6-3-administrator-billing-offers-contact-checkout` · **Harness**: H-FL · **Verification**: T032 (seven E2E ids)

## 1. What was implemented

The Flutter desktop gives administrators a billing route from the AI host renew control and the degraded renew-or-buy control. The flow mints a billing token in memory, calls the ABO for offers, billing contact, and checkout, opens Paymob in the system browser, polls checkout status, and calls `request_ai_status_refresh` when the shown state becomes Active. Staff sessions see no billing entry and never call `issue_billing_token`. An unsupported ABO contract version shows the inline app-update state.

- **Billing route** (`app_routes.dart`, `router.dart`) — Registers `/ai/administrator-billing` for administrators only; staff are redirected away (FR-001, FR-008).
- **Entry controls** (`ai_feature_host_page.dart`, `ai_degraded_view.dart`) — Administrator renew (`ai_notice_renew`) and renew-or-buy (`kAiDegradedRenewOrBuyKey`) push the billing route; staff see no purchase control (FR-001, FR-008).
- **Billing-token client** (`billing_token_client.dart`) — Calls `issue_billing_token` with `p_contract_version` set to `backendRpc`; mints on page open and renews before `expires_at`; token stays in memory for that page only (FR-002, FR-005, FR-008).
- **ABO client** (`abo_client.dart`) — Sends `Authorization: Bearer <billing token>` and `Abo-Contract-Version` set to `aboClinic` on every call; parses offers, billing contact, checkout create/read, the open list, and the six ABO error codes (FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-009).
- **Offers screen** (`offers_screen.dart`) — Shows offers and terms; administrator accepts the current terms before checkout (FR-001, FR-003).
- **Billing-contact form** (`billing_contact_form.dart`) — Reads and saves billing contact; stays on the form when checkout returns `billing_contact_required` (FR-001, FR-004, FR-007).
- **Checkout screen** (`checkout_screen.dart`) — Shows the queued-term sentence before `launchUrl`; opens `redirect_url` externally; polls while Waiting or Paid; keeps Failed on the same page for retry; calls `request_ai_status_refresh` once on Active; handles the five ABO errors and `contract_version_unsupported` inline via `AiDegradedView` (FR-001, FR-004, FR-006, FR-007, FR-009).
- **Administrator billing page** (`administrator_billing_page.dart`) — Loads `GET /v1/checkouts?open=1` and resumes a listed checkout by `reference`; otherwise sequences offers → contact → checkout; takes no tenant argument (FR-001, FR-005, FR-008, FR-009).
- **Localization** (`app_en.arb`, `app_ar.arb`, generated `app_localizations*.dart`) — English and Arabic strings for offers, contact, checkout shown states, the queued-term sentence, and the five ABO errors (FR-001).
- **H-FL harness** (`administrator_billing_fullstack_test.dart`) — Seven tests tagged `fullstack`, titles prefixed `E2E-P6.3-01` through `E2E-P6.3-07` (FR-001 through FR-009).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | FR-002, FR-005, FR-008 |
| `frontend/lib/features/ai/billing/abo_client.dart` | FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-009 |
| `frontend/lib/features/ai/billing/offers_screen.dart` | FR-001, FR-003, FR-007 |
| `frontend/lib/features/ai/billing/billing_contact_form.dart` | FR-001, FR-004, FR-007 |
| `frontend/lib/features/ai/billing/checkout_screen.dart` | FR-001, FR-004, FR-006, FR-007, FR-009 |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | FR-001, FR-005, FR-008, FR-009 |
| `frontend/lib/app/app_routes.dart` | FR-001 |
| `frontend/lib/app/router.dart` | FR-001, FR-008 |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | FR-001, FR-008 |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | FR-001, FR-008 |
| `frontend/lib/l10n/app_en.arb` | FR-001 |
| `frontend/lib/l10n/app_ar.arb` | FR-001 |
| `frontend/lib/l10n/app_localizations.dart` | FR-001 |
| `frontend/lib/l10n/app_localizations_en.dart` | FR-001 |
| `frontend/lib/l10n/app_localizations_ar.dart` | FR-001 |
| `frontend/test/integration/administrator_billing_fullstack_test.dart` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/quickstart.md` | FR-001, FR-006 |

## 3. Harness command for this unit's tests only

From `frontend/`:

```bash
flutter test test/integration/administrator_billing_fullstack_test.dart --tags fullstack
```

This delivery did not execute that command because the H-FS stack was not running and this workflow does not start wrangler.

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P6.3-01 | Renew action on `AiFeatureHostPage` → `router.dart` billing route → `AdministratorBillingPage` → `OffersScreen` → `BillingContactForm` → `CheckoutScreen` → `url_launcher` → poll `GET /v1/checkouts/{id}` → `request_ai_status_refresh` → `get_ai_status` → live AI submit |
| E2E-P6.3-02 | Two in-memory clients (same clinic, different branch claims) each open the billing route → `AdministratorBillingPage` → `GET /v1/checkouts?open=1` → resume by `reference` → `CheckoutScreen` → payment → Active |
| E2E-P6.3-03 | `CheckoutScreen` after an active clinic posts checkout → shows "starts after the current term" before `launchUrl`; POST answer is `starts` `after_current` |
| E2E-P6.3-04 | `CheckoutScreen` on `POST /v1/checkouts` after catalogue version moves → `offer_unavailable` → `OffersScreen` reload → new price shown before launch |
| E2E-P6.3-05 | Same `CheckoutScreen`, polling `GET /v1/checkouts/{id}` → `decline.json` leaves Failed → later `success.json` shows Active on the same page |
| E2E-P6.3-06 | Staff session of `AiFeatureHostPage` in the app shell → renew control and renew-or-buy control absent; no `issue_billing_token` call |
| E2E-P6.3-07 | Administrator billing screens with `Abo-Contract-Version` outside the accepted pair → ABO answers `contract_version_unsupported` → inline `AiDegradedView` app-update state, no dialog |
