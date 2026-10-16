# Feature Specification: Administrator billing: offers, contact and checkout flow

**Feature Branch**: `ai/091-abo-p6-3-administrator-billing-offers-contact-checkout`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P6.3 — Administrator billing: offers, contact and checkout flow

## 1. Unit Contract

**Implements** — Read: 04 §2.2 (rows offers, billing contact, the three checkout rows, Rules); 04 §2.3; 04 §3.1 rows `issue_billing_token`, `request_ai_status_refresh`; 03 §5.1 (shown-state table); 04 §3.5 row "Frontend billing"; 05 §8 rows A1, A2, A12, A30.

- billing-token client (minted per use, renewed before 300 s); ABO client with `Abo-Contract-Version`; offers screen (localised copy, terms acceptance); billing-contact form; checkout → system browser via `url_launcher`; progress polling (Waiting/Failed/Paid/Active/Abandoned); `starts after_current` shown before paying; resume open checkouts from any desktop; on Active, call `request_ai_status_refresh`; error handling (`offer_unavailable`, `billing_contact_required`, `terms_not_accepted`, `provider_unavailable`, `rate_limited`); en/ar strings; administrator-only entry point.

**Freezes** — CP-E.

**Consumes** — None. P6.1 and P4.5 publish no Outputs / freezes line.

**Open questions relied on** — OQ-6: "Default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL)."

**Spikes** — None.

## Clarifications

### Session 2026-10-08

- Q: Where should the new administrator billing screens, billing-token client, and ABO client live, and how should the shell open them? → A: Put the screens, the billing-token client, and the ABO client in `frontend/lib/features/ai/billing/`, and open that flow with a route from the existing administrator renew and buy actions in `frontend/lib/app/router.dart`. Widget scenarios live under `frontend/test/widget/`; Dart client tests tagged `fullstack` live under `frontend/test/integration/`. `[implementation choice — no §citation]`
- Q: How should E2E-P6.3-02 construct the second desktop session? → A: One Dart `fullstack` test drives two clients against the same clinic on H-FS, with different branch claims, and neither client writes the tenant to disk. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - An administrator buys coverage and AI turns on (Priority: P1)

An administrator opens billing from the live desktop shell, accepts the current terms, saves a billing contact, and checks out. The desktop opens the provider page in the system browser. Polling the checkout reaches Active. The desktop then calls `request_ai_status_refresh`. `get_ai_status` is active, and an AI request succeeds.

**Why this priority**: CP-E is this thread. Resume, a queued term, a price change, and a declined attempt all use the same billing screens.

**Independent Test**: E2E-P6.3-01 in harness H-FL on H-FS, payment via the H-PAY fixture.

**Acceptance Scenarios**:

1. **Given** an administrator session, **When** the administrator goes from offers to billing contact to checkout and completes the stub payment, **Then** polling the checkout shows Active, the desktop calls `request_ai_status_refresh`, `get_ai_status` is active, and an AI request succeeds. The admin desktop shows Active by polling the checkout, then calls `request_ai_status_refresh()`. (E2E-P6.3-01) [CP-E, A1]

### 2.2 User Story 2 - Any desktop can see an open checkout (Priority: P2)

A second desktop session for the same clinic sees this tenant's open checkout and, once paid, Active status. Closing the app while payment is in progress still leaves provisioning to complete. The tenant comes from the backend session. The desktop stores nothing for that tenant.

**Why this priority**: This story uses the checkout screens from User Story 1. The provisioning path does not need the first desktop to stay open.

**Independent Test**: E2E-P6.3-02 in harness H-FL on H-FS, payment via the H-PAY fixture.

**Acceptance Scenarios**:

1. **Given** a checkout opened from one desktop, **When** a second desktop session (other branch) loads billing, **Then** it sees the open checkout via `GET /v1/checkouts?open=1` and, after payment, Active status. Closing the app mid-payment still provisions. Nothing on the provisioning path needs the desktop. Any desktop's `get_ai_status()` shows active on open. The tenant comes from the backend session; nothing is stored on the desktop. (E2E-P6.3-02) [A2, A12]

### 2.3 User Story 3 - The administrator sees the term and the price before paying (Priority: P3)

An active clinic buying again sees "starts after the current term" before paying. A price change mid-flow returns `offer_unavailable` and the new price is shown before paying. A declined attempt shows Failed, and a retry on the same page can still reach Active.

**Why this priority**: These are the checkout boundaries on the screens from User Story 1. Each one is decided before or without leaving that checkout page.

**Independent Test**: E2E-P6.3-03, E2E-P6.3-04, and E2E-P6.3-05 in harness H-FL on H-FS, payment via the H-PAY fixture.

**Acceptance Scenarios**:

1. **Given** an active clinic, **When** the administrator buys again, **Then** the app shows "starts after the current term" before paying. `POST /v1/checkouts` answers `starts: after_current`. The app offers the change for the next term only; nothing changes now. (E2E-P6.3-03) [A30]
2. **Given** an offer the administrator is checking out, **When** the price changes mid-flow, **Then** the ABO answers `offer_unavailable` and the new price is shown before paying. (E2E-P6.3-04) [A8]
3. **Given** an open checkout whose last attempt was declined, **When** the administrator retries on the same page, **Then** the shown state is Failed and, after the later success, Active. (E2E-P6.3-05) [A5]

### 2.4 User Story 4 - Staff have no billing entry, and an old app shows the update state (Priority: P4)

A staff session has no billing entry point and never calls `issue_billing_token`. When the ABO answers an unsupported contract version, the billing screens show the update state.

**Why this priority**: The purchase thread already exists. This story is who may open it, and what the billing screens show when the ABO refuses the desktop's contract version.

**Independent Test**: E2E-P6.3-06 and E2E-P6.3-07 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** a staff session on the live desktop shell, **When** the session runs, **Then** there is no billing entry point and `issue_billing_token` is never called. (E2E-P6.3-06) [AD-2]
2. **Given** billing screens, **When** the ABO answers an unsupported version, **Then** those screens show the update state. (E2E-P6.3-07)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P6.3-01 | H-FL on H-FS, payment via the H-PAY fixture | Administrator billing screens composed in the app shell from the renew action on `AiFeatureHostPage` (`frontend/lib/features/ai/host/ai_feature_host_page.dart`, key `ai_notice_renew`) and the renew or buy action on `AiDegradedView` (`kAiDegradedRenewOrBuyKey`), composed from `frontend/lib/app/router.dart` and `frontend/lib/features/ai/presentation/pages/ai_page.dart`. Checkout opens `redirect_url` with `url_launcher` (`frontend/pubspec.yaml`) | offers → contact → checkout → stub payment → polling shows Active → refresh RPC → `get_ai_status` active → an AI request succeeds [CP-E, A1] | FR-001, FR-002, FR-003, FR-004, FR-006 | User Story 1 |
| E2E-P6.3-02 | H-FL on H-FS, payment via the H-PAY fixture | A second desktop session's billing screens in that same shell, reading `GET /v1/checkouts?open=1` | a second desktop session (other branch) sees the open checkout via `?open=1` and Active status; closing the app mid-payment still provisions [A2, A12] | FR-005 | User Story 2 |
| E2E-P6.3-03 | H-FL on H-FS, payment via the H-PAY fixture | The checkout screen in that shell, before the system browser opens | an active clinic buying again sees "starts after the current term" before paying [A30] | FR-004 | User Story 3 |
| E2E-P6.3-04 | H-FL on H-FS, payment via the H-PAY fixture | The same checkout screen, on `POST /v1/checkouts` | the price changes mid-flow → `offer_unavailable` → the new price is shown before paying [A8] | FR-007 | User Story 3 |
| E2E-P6.3-05 | H-FL on H-FS, payment via the H-PAY fixture | The same checkout page, polling `GET /v1/checkouts/{id}` | decline, then a retry on the same page → Failed, then Active [A5] | FR-006, FR-007 | User Story 3 |
| E2E-P6.3-06 | H-FL on H-FS, payment via the H-PAY fixture | Staff session of `AiFeatureHostPage` in the app shell | Staff user: no billing entry point; `issue_billing_token` never called [AD-2] | FR-008 | User Story 4 |
| E2E-P6.3-07 | H-FL on H-FS, payment via the H-PAY fixture | The administrator billing screens in that shell | ABO answers unsupported version → billing screens show the update state | FR-009 | User Story 4 |

### 2.6 Edge Cases

- Shown progress (03 §5.1, FR-14): Waiting when `open` with no attempt, or with a pending attempt; Failed when `open` and the last attempt was declined, and the same page can still be retried (A5, E2E-P6.3-05); Paid when `paid` or `paid_late` and the grant is not yet applied; Active when the grant outcome is `applied` or `already_applied` (E2E-P6.3-01); Abandoned when `expired`, `cancelled`, or `open_failed` with no payment.
- `offer_unavailable` is HTTP 409 when the offer is retired or the version is superseded. The body includes the current version. `offer_version` must be the current sellable version, so a price change between viewing and opening is shown before paying (A8, E2E-P6.3-04). (04 §2.2, 04 §2.3)
- `billing_contact_required` is HTTP 409 when there is no billing contact yet. A new checkout needs a billing contact and the current terms version. (04 §2.2, 04 §2.3)
- `terms_not_accepted` is HTTP 409 when `terms_version` is not current. The offers screen accepts the current terms before checkout. (04 §2.2, 04 §2.3)
- `provider_unavailable` is HTTP 503 when the provider refused or timed out when creating the checkout. `open_failed` is the checkout state when the provider refused creation, and the desktop shows Abandoned when that state has no payment. (04 §2.3, 03 §5.1)
- `rate_limited` is HTTP 429 for the §2.2 limits: 10 checkouts per tenant per hour and 60 requests per token. (04 §2.2, 04 §2.3)
- `contract_version_unsupported` is HTTP 400 when `Abo-Contract-Version` is missing or outside N and N−1. The body includes `accepted_versions` (`[N−1, N]`, N−1 then N) and `contract_version` N. The response header `Abo-Contract-Version` is that same N. The check runs before authentication, so an outdated desktop gets this and not `unauthenticated`. Billing screens show the update state. (04 §2.3, E2E-P6.3-07)
- A staff session has no billing entry point and never calls `issue_billing_token`. That RPC is `administrator` only and returns `{token, abo_base_url, expires_at}`, or `FORBIDDEN_ROLE` or `RATE_LIMITED` (20 per user per 10 minutes). (04 §3.1, E2E-P6.3-06)
- Closing the app mid-payment still provisions. `GET /v1/checkouts?open=1` returns this tenant's open and recently paid checkouts so any desktop can resume. The tenant is the token's `org` only. Nothing is stored on the desktop. (04 §2.2, 05 §8 A2, A12, E2E-P6.3-02)
- An active clinic buying again is shown `starts` `after_current` (with `projected_start`) before paying, as the sentence "starts after the current term". Nothing changes now. (04 §2.2, 05 §8 A30, E2E-P6.3-03)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The desktop MUST provide an administrator-only billing entry from the live app shell: the renew action on `AiFeatureHostPage` and the renew or buy action on `AiDegradedView`. The entry opens the offers screen, the billing-contact form, and checkout. Strings for the feature live in `frontend/lib/l10n/app_en.arb` and `frontend/lib/l10n/app_ar.arb`. (04 §3.5, Implements)
- **FR-002**: The billing-token client MUST mint a billing token per use and renew it before 300 s. It calls `issue_billing_token(p_contract_version)`, which returns `{token, abo_base_url, expires_at}`. The billing token's `exp − iat` is ≤ 300 s. Every ABO call MUST send `Authorization: Bearer <billing token>` and `Abo-Contract-Version`. The ABO base URL is the `abo_base_url` returned with the token. Hostname for those calls is `billing.<vendor-domain>`. (04 §2.1, 04 §2.2, 04 §3.1)
- **FR-003**: The offers screen MUST show `GET /v1/offers`: `offers[]` of `offer_id`, `version`, `plan_display_name`, `term_unit`, `term_count`, `price_minor`, `currency`, `allowance_credits`, `grace_days`, and localized `copy`; and `terms` with `version` and text. The administrator accepts the current terms on that screen before checkout. (04 §2.2, FR-05, FR-17)
- **FR-004**: The billing-contact form MUST read `GET /v1/billing-contact` (`version`, `name`, `email`, `phone`, or `not_found`) and save with `PUT /v1/billing-contact` (`client_request_id`, `name`, `email`, `phone` in E.164), which returns the new version. Checkout MUST `POST /v1/checkouts` with `client_request_id`, `offer_id`, `offer_version`, and `terms_version`. The response is `checkout_id`, `reference`, `redirect_url`, `expires_at`, and `starts` (`now` or `after_current`, with `projected_start`). The desktop MUST open `redirect_url` in the system browser via `url_launcher`. Before paying, the administrator sees whether the term queues. An active clinic buying again sees "starts after the current term" before paying. `POST /v1/checkouts` answers `starts: after_current` for that case. The app offers the change for the next term only; nothing changes now. `POST` and `PUT` are idempotent by `client_request_id` per tenant. (04 §2.2, 04 §3.5, 05 §8 A30, FR-30, FR-31, FR-51, E2E-P6.3-01, E2E-P6.3-03)
- **FR-005**: Any desktop MUST be able to resume this tenant's open and recently paid checkouts from `GET /v1/checkouts?open=1`. A second desktop session (other branch) sees the open checkout and Active status. Closing the app mid-payment still provisions. Nothing on the provisioning path needs the desktop. The tenant comes from the backend session; nothing is stored on the desktop. The tenant is the token's `org` only. (04 §2.2, 05 §8 A2, A12, FR-14, E2E-P6.3-02)
- **FR-006**: The desktop MUST poll `GET /v1/checkouts/{id}` and show the derived progress state: Waiting, Failed, Paid, Active, or Abandoned, using the 03 §5.1 shown-state table. The response carries `reference`, that shown state, an offer summary, `payment_reference`, `term_ref`, and `updated_at`. When the shown state is Active, the desktop MUST call `request_ai_status_refresh(p_contract_version)`. Success `data` is `{requested_at}` and the call starts an immediate pull. The admin desktop shows Active by polling the checkout, then calls `request_ai_status_refresh()`. `get_ai_status` is then active, and an AI request succeeds. (03 §5.1, 04 §2.2, 04 §3.1, 05 §8 A1, FR-14, FR-62, E2E-P6.3-01)
- **FR-007**: The desktop MUST handle ABO errors `offer_unavailable`, `billing_contact_required`, `terms_not_accepted`, `provider_unavailable`, and `rate_limited` as specified in 04 §2.3. A price change mid-flow returns `offer_unavailable`, and the new price is shown before paying. A declined attempt shows Failed, and a retry on the same page can reach Active. (04 §2.2, 04 §2.3, 03 §5.1, E2E-P6.3-04, E2E-P6.3-05)
- **FR-008**: A staff user MUST have no billing entry point, and the desktop MUST never call `issue_billing_token` for that session. (04 §3.1, E2E-P6.3-06, AD-2)
- **FR-009**: When the ABO answers `contract_version_unsupported`, billing screens MUST show the update state. That refusal is HTTP 400, checked before authentication, and includes `accepted_versions`. A call on the accepted version proceeds through the clinic API. (04 §2.3, E2E-P6.3-01, E2E-P6.3-07)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: frontend. The unit row names no wiring exception. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic administrator buys or queues AI coverage from the desktop: offers, billing contact, checkout in the system browser, and progress until Active. A staff member has no billing entry and does not mint a billing token. An active clinic sees that a new purchase starts after the current term.
- **Layer Placement**: Flutter owns the billing screens, the billing-token client, the ABO client, `url_launcher`, polling, and the call to `request_ai_status_refresh` when the checkout shows Active. Supabase exposes `issue_billing_token` and `request_ai_status_refresh`. The ABO owns offers, billing contact, checkout, and payment. The desktop does not grant coverage and does not store the tenant.
- **Data Integrity & Security**: This unit defines no tables. `issue_billing_token` is `administrator` only. Every ABO call carries the billing token and `Abo-Contract-Version`. The tenant is the token's `org` only. `POST` and `PUT` send `client_request_id`. Nothing about the tenant is stored on the desktop (A12).
- **Failure Handling**: `offer_unavailable` shows the current price before paying. `billing_contact_required` and `terms_not_accepted` stop a checkout that lacks a contact or the current terms. `provider_unavailable` is the provider refusal or timeout on checkout creation; `open_failed` with no payment is shown as Abandoned. `rate_limited` is the §2.2 limit. A declined attempt stays on the same page as Failed and can be retried. An unsupported ABO contract version shows the update state, the check having run before authentication. Closing the app mid-payment still provisions.

## 5. Out of Scope

- The unit row states no Out of scope list.
- No Do-not-read material. The unit row names none. The cited 04 §2.2 span is the offers row, the billing-contact row, the three checkout rows (`POST /v1/checkouts`, `GET /v1/checkouts/{id}`, `GET /v1/checkouts?open=1`), and the Rules. The cited 04 §2.3 span is the ABO error table. The cited 04 §3.1 span is the rows `issue_billing_token` and `request_ai_status_refresh`. The cited 03 §5.1 span is the shown-state table. The cited 04 §3.5 span is the row "Frontend billing". The cited 05 §8 span is rows A1, A2, A12, and A30.
- No Consumes contract to rewrite. P6.1 and P4.5 publish no Outputs / freezes line.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. The offers screen, billing-contact form, checkout, polling, and the billing-token client are reached from the administrator billing entry in the app shell.
- No S9 path owned by a later unit. Payment history in the Frontend billing row, `GET /v1/subscription`, and `GET /v1/payments` stay with P6.4.
- No second codebase beyond frontend. H-FL is Dart client tests against H-FS plus widget scenario tests (`frontend/test/integration/`, `frontend/test/widget/`), extended here and not forked. Payment in these scenarios uses the H-PAY fixture.
- Status reads on open, resume, `next_change_at`, and the 5-minute timer, and notice rendering, stay with P6.1. This unit wires that unit's administrator renew action into billing.
- Denial taxonomy, the administrator gauge, and staff coverage calls stay with P6.2. This unit wires that unit's renew or buy action into billing.
- ABO checkout creation, Paymob, sweeps, grants, and inquiry stay with P4. The desktop calls the frozen clinic API and polls the shown state.
- `issue_billing_token` and `request_ai_status_refresh` stay with the backend units named in D1 for 04 §3.1. This unit calls them.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P6.3-01, E2E-P6.3-02, E2E-P6.3-03, E2E-P6.3-04, E2E-P6.3-05, E2E-P6.3-06, and E2E-P6.3-07 are green in harness H-FL on H-FS, with payment via the H-PAY fixture where the scenario pays.
- **SC-002**: Every earlier suite stays green (rule S2).
- **SC-003**: CP-E holds: one thread goes from the admin desktop client to checkout, payment, grant, status, and an AI request (E2E-P6.3-01).

## 7. Assumptions

- OQ-6 default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL).
- Rule S9: this unit names no transitional path. Payment history and the subscription and payments reads remain P6.4.
