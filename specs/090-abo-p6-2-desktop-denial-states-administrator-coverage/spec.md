# Feature Specification: Desktop denial states and the administrator coverage view

**Feature Branch**: `ai/090-abo-p6-2-desktop-denial-states-administrator-coverage`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P6.2 — Desktop denial states and the administrator coverage view

## 1. Unit Contract

**Implements** — Read: 04 §3.4 (denial table); 04 §4.2 (denial-code table; rows `/v1/coverage`, `/v1/usage`); 04 §3.5 rows "Frontend status" and "Frontend usage"; 02 §2 row TB-3.

- taxonomy for the 04 §4.2 codes mapped to the FR-65 classes in `AiDegradedView` (inline only; staff vs administrator wording; `retry_after`); a denial triggers a status refresh; `usage_summary_client` becomes a `/v1/coverage` client; the gauge is administrator-only; staff never call `/v1/coverage` or `/v1/usage`.

**Freezes** — None.

**Consumes** — None.

**Open questions relied on** — OQ-6: "Default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL)."

**Spikes** — None.

## Clarifications

### Session 2026-10-08

- Q: Where do the H-FL widget scenarios for this unit live? → A: One new file, `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart`. Seven tests, titles prefixed `E2E-P6.2-01` through `E2E-P6.2-07`. A row that names two triggers or two sessions asserts both inside that single test. Fake ports only, composed from `AiFeatureHostPage` in the app shell. `[implementation choice — no §citation]`
- Q: Which code fetches coverage and refreshes status after a denial? → A: Keep `frontend/lib/core/ai/usage_summary_client.dart` as the only `/v1/coverage` client. `AiFeatureHostPage` calls it only for an administrator and does not call `/v1/usage`. A denial refreshes status through the status reader the live AI composition already uses. No second coverage client and no second scheduler. `[implementation choice — no §citation]`
- Q: What does the administrator renew or buy action do before P6.3 wires checkout? → A: Render it as a visible control on the inline denial state. The control does not navigate, mint a token, or call billing. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1)

A clinic member uses AI from the live desktop host. When the platform denies the request, `AiDegradedView` shows an inline state for that code. Staff and administrators see the wording in the denial table. A denial refreshes status. The state is never a dialog.

**Why this priority**: Later coverage display still depends on the member being able to tell a lapsed or exhausted clinic, a paid clinic with nothing available, a safety limit, and an unreachable platform apart. Those states are this story.

**Independent Test**: E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, and E2E-P6.2-07 in harness H-FL.

**Acceptance Scenarios**:

1. **Given** a lapsed clinic, **When** an AI request is denied `coverage_lapsed`, **Then** the staff member sees the inline state "AI not available, contact your administrator", and the administrator sees a renew or buy action. The state is inline, never a dialog. (E2E-P6.2-01) [FR-65]
2. **Given** an AI request denied `allowance_exhausted`, **When** the desktop shows that denial, **Then** the mapped state is shown and status is refreshed. Staff see "AI not available, contact your administrator". The administrator sees a renew or buy action. (E2E-P6.2-02)
3. **Given** an AI request denied `suspended`, **When** an administrator views the denial, **Then** they see "Contact support" and the subscription reference. Staff see "AI not available, contact your administrator". (E2E-P6.2-03)
4. **Given** an AI request denied `concurrency_limited` or `rate_limited`, **When** the denial is shown, **Then** staff and administrators see "AI busy, try again shortly" with `retry_after`. (E2E-P6.2-04)
5. **Given** an AI request denied `coverage_unknown`, or a network failure, **When** the desktop shows that outcome, **Then** staff and administrators see the inline state "AI service unreachable". (E2E-P6.2-05) [G5]
6. **Given** an AI request denied `forbidden_capability`, **When** an administrator views the denial, **Then** they see the plan name. Staff see "Not included in your clinic's AI plan". (E2E-P6.2-07)

### 2.2 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2)

An administrator's desktop gauge shows live allowance from `GET /v1/coverage`. A staff session never calls `GET /v1/coverage` or `GET /v1/usage`. The gauge is not shown to staff.

**Why this priority**: This story uses the same live AI host as User Story 1. It is the administrator coverage view, and it removes the staff usage call.

**Independent Test**: E2E-P6.2-06 in harness H-FL. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** an administrator session, **When** the live AI host shows the gauge, **Then** the gauge shows live allowance from `GET /v1/coverage`. **Given** a staff session on that same host, **When** the session runs, **Then** it makes no `GET /v1/coverage` call and no `GET /v1/usage` call. (E2E-P6.2-06) [A28]

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P6.2-01 | H-FL, widget scenario with fake ports | `AiFeatureHostPage` composed in the app shell (`frontend/lib/features/ai/presentation/pages/ai_page.dart`, `frontend/lib/app/router.dart`), rendering `AiDegradedView` from `resolveDegradedMode` and `frontend/lib/core/ai/taxonomy.dart` | Lapsed clinic: AI request denied `coverage_lapsed` → staff inline "AI not available, contact your administrator"; the administrator sees renew/buy. Inline only, never a dialog [FR-65] | FR-001, FR-002 | User Story 1 |
| E2E-P6.2-02 | H-FL, widget scenario with fake ports | The same live host. The denial path refreshes status (`AiFeatureHostPage` terminal-failure path) | `allowance_exhausted` → the mapped state is shown (staff "AI not available, contact your administrator"; administrator renew/buy) and status is refreshed | FR-001, FR-002, FR-003 | User Story 1 |
| E2E-P6.2-03 | H-FL, widget scenario with fake ports | The same `AiDegradedView` composition | `suspended` → staff see "AI not available, contact your administrator"; the administrator sees "Contact support" and the subscription reference | FR-001, FR-002, FR-005 | User Story 1 |
| E2E-P6.2-04 | H-FL, widget scenario with fake ports | The same `AiDegradedView` composition | `concurrency_limited`/`rate_limited` → "AI busy, try again shortly" with `retry_after` for staff and administrators | FR-001, FR-002 | User Story 1 |
| E2E-P6.2-05 | H-FL, widget scenario with fake ports | The same `AiDegradedView` composition | `coverage_unknown` or network failure → inline "AI service unreachable" for staff and administrators [G5] | FR-001, FR-002 | User Story 1 |
| E2E-P6.2-06 | H-FL, widget scenario with fake ports | `UsageGauge` in `AiFeatureHostPage`, fed by the `/v1/coverage` client that replaces `UsageSummaryClient.fetchUsage` (`frontend/lib/core/ai/usage_summary_client.dart`) | The administrator gauge shows live allowance from `/v1/coverage`; a staff session makes no `/v1/coverage` or `/v1/usage` call [A28] | FR-004, FR-005 | User Story 2 |
| E2E-P6.2-07 | H-FL, widget scenario with fake ports | The same `AiDegradedView` composition | `forbidden_capability` shows the plan name to administrators; staff see "Not included in your clinic's AI plan" | FR-001, FR-002 | User Story 1 |

### 2.4 Edge Cases

- Denials are inline states, never dialogs (FR-64), extending `AiDegradedView` (`frontend/lib/features/ai/degraded/ai_degraded_view.dart`). (04 §3.4, E2E-P6.2-01)
- `allowance_exhausted` and `coverage_lapsed` are the class "Not paid, lapsed or used up". Staff see "AI not available, contact your administrator". The administrator also sees a renew or buy action. `allowance_exhausted` is HTTP 403 and replaces `quota_exhausted` for allowance, with no extra fields. `coverage_lapsed` is HTTP 403 and replaces `quota_exhausted` on a config miss, with extra field `coverage_reason`. The shown sentences are the denial-table sentences. (04 §3.4, 04 §4.2, E2E-P6.2-01, E2E-P6.2-02)
- `suspended` is the same class. Staff see the same staff sentence. The administrator also sees "Contact support" and the subscription reference. The code is HTTP 403 and replaces `installation_suspended`, with no extra fields. (04 §3.4, 04 §4.2, E2E-P6.2-03)
- `forbidden_capability` is the class "Paid, nothing available". Staff see "Not included in your clinic's AI plan". The administrator also sees the plan name. (04 §3.4, E2E-P6.2-07)
- `capability_disabled` and `provider_unavailable` are the class "Paid, nothing available". Staff and administrators see "AI temporarily unavailable". (04 §3.4)
- `coverage_unknown`, network failure, and `status_stale` are the class "Platform unreachable". Staff and administrators see "AI service unreachable". `coverage_unknown` is HTTP 503 with extra field `retry_after`. The shown sentence is "AI service unreachable". E2E-P6.2-05 proves `coverage_unknown` and network failure. (04 §3.4, 04 §4.2, E2E-P6.2-05)
- `concurrency_limited` and `rate_limited` are the class "Safety limit (FR-09)". Staff and administrators see "AI busy, try again shortly" with `retry_after`. `concurrency_limited` is HTTP 429 and replaces `quota_exhausted` for concurrency, with extra field `retry_after`. `rate_limited` is HTTP 429 and is unchanged, with extra fields unchanged. (04 §3.4, 04 §4.2, E2E-P6.2-04)
- `contract_version_unsupported` from the platform, the ABO, or an RPC is the class "App too old (NFR-09)". Staff and administrators see "Update the app to use AI". On the platform code table it is HTTP 400, checked before token verification, with extra field `accepted_versions`. Billing screens show the same state under P6.3. (04 §3.4, 04 §4.2)
- `GET /v1/coverage` is `role = administrator` only (TB-3). It returns `subscription_ref`, the live snapshot from the DO (read-only, no write), queued terms (plan and duration), and the last 12 terms with usage (FR-60, P-09). The desktop gauge shows live allowance from that response to administrators. A staff session does not call it. (04 §4.2, 02 §2 TB-3, E2E-P6.2-06)
- `GET /v1/usage` is removed. Staff desktops call it today (`frontend/lib/features/ai/host/ai_feature_host_page.dart`), which FR-61 forbids. This unit's staff session does not call it. (04 §4.2, 04 §3.5, E2E-P6.2-06)
- An `allowance_exhausted` denial shows its state and triggers a status refresh. (E2E-P6.2-02)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` and `frontend/lib/core/ai/taxonomy.dart` MUST take the 04 §4.2 codes. Denials MUST be inline states in `AiDegradedView`, never dialogs (FR-64). (04 §3.4, 04 §3.5)
- **FR-002**: The desktop MUST map each denial-table row to its FR-65 class, staff sentence, and administrator sentence:

  | Platform code | FR-65 class | Staff sees | Administrator also sees |
  | --- | --- | --- | --- |
  | `allowance_exhausted`, `coverage_lapsed` | Not paid, lapsed or used up | "AI not available, contact your administrator" | Renew or buy action |
  | `suspended` | Not paid, lapsed or used up | Same | "Contact support" and the subscription reference |
  | `forbidden_capability` | Paid, nothing available | "Not included in your clinic's AI plan" | Plan name |
  | `capability_disabled`, `provider_unavailable` | Paid, nothing available | "AI temporarily unavailable" | Same |
  | `coverage_unknown`, network failure, `status_stale` | Platform unreachable | "AI service unreachable" | Same |
  | `concurrency_limited`, `rate_limited` | Safety limit (FR-09) | "AI busy, try again shortly" with `retry_after` | Same |
  | `contract_version_unsupported` from the platform, the ABO, or an RPC | App too old (NFR-09) | "Update the app to use AI" | Same |

  The taxonomy MUST recognize the 04 §4.2 codes `allowance_exhausted` (HTTP 403), `coverage_lapsed` (HTTP 403, extra field `coverage_reason`), `coverage_unknown` (HTTP 503, extra field `retry_after`), `suspended` (HTTP 403), `concurrency_limited` (HTTP 429, extra field `retry_after`), `rate_limited` (HTTP 429), and `contract_version_unsupported` (HTTP 400, extra field `accepted_versions`, checked before token verification). (04 §3.4, 04 §4.2)

- **FR-003**: A denial MUST trigger a status refresh. `allowance_exhausted` MUST show its mapped state and refresh status. (E2E-P6.2-02)
- **FR-004**: `frontend/lib/core/ai/usage_summary_client.dart` MUST become a `GET /v1/coverage` client. The gauge in `AiFeatureHostPage` MUST be shown to administrators only (FR-61). A staff session MUST NOT call `GET /v1/coverage` or `GET /v1/usage`. (04 §3.5, 04 §4.2, E2E-P6.2-06)
- **FR-005**: For an administrator, the gauge MUST show live allowance from `GET /v1/coverage`. That route is `role = administrator` only and returns `subscription_ref`, the live snapshot from the DO (read-only, no write), queued terms (plan and duration), and the last 12 terms with usage (FR-60, P-09). The administrator `suspended` denial MUST show "Contact support" and the subscription reference. (04 §4.2, 02 §2 TB-3, 04 §3.4, E2E-P6.2-03, E2E-P6.2-06)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: frontend. The unit row names no wiring exception. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A staff member who is denied AI sees an inline sentence and is told to contact the administrator, with no purchase action. An administrator sees renew or buy, "Contact support" with the subscription reference, the plan name when the capability is forbidden, and a gauge of live allowance. Safety limits and an unreachable platform use the same sentence for both roles.
- **Layer Placement**: Flutter owns the denial taxonomy, `AiDegradedView`, the status refresh triggered by a denial, and the administrator `/v1/coverage` client and gauge. The platform remains the source of the denial codes and of the coverage snapshot. The desktop does not grant, write coverage, or decide admission. TB-3: `/v1/coverage` requires `role = administrator`.
- **Data Integrity & Security**: This unit defines no tables, RPCs, or writes. Staff sessions do not call `/v1/coverage` or `/v1/usage`. `GET /v1/coverage` is read-only and returns `subscription_ref` to the administrator. The `suspended` denial shows that subscription reference. The `forbidden_capability` denial shows the plan name to administrators.
- **Failure Handling**: `coverage_unknown`, network failure, and `status_stale` show the inline state "AI service unreachable", never a dialog (G5, FR-64). `concurrency_limited` and `rate_limited` show "AI busy, try again shortly" with `retry_after`. A denial refreshes status.

## 5. Out of Scope

- The unit row states no Out of scope list.
- No Do-not-read material. The unit row names none. The cited 04 §3.4 span is the denial table. The cited 04 §4.2 span is the denial-code table and the `/v1/coverage` and `/v1/usage` rows. The cited 04 §3.5 span is the Frontend status and Frontend usage rows. The cited 02 §2 span is row TB-3.
- No Consumes contract to rewrite. P6.1 freezes nothing for this unit.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. `AiDegradedView`, the degraded-mode taxonomy, the `/v1/coverage` client, and the gauge are reached from `AiFeatureHostPage` in the app shell.
- No S9 path owned by a later unit. This unit replaces the desktop `GET /v1/usage` call. It does not leave that desktop call alive. Platform removal of `GET /v1/usage` stays with P3.9 (04 §4.2 in D1).
- No second codebase beyond frontend. H-FL widget scenarios use fake ports (`frontend/test/widget/`). H-FL is the harness from 06 §3 V1, extended here and not forked.
- Status reads on open, resume, `next_change_at`, and the 5-minute timer, notice rendering, and the inline "Update the app to use AI" channel behavior stay with P6.1 (D1: 04 §3.4 reads). This unit maps the denial-table row for `contract_version_unsupported` onto that same sentence.
- Billing screens that show the update state, wiring the renew or buy action into checkout, offers, billing contact, and billing-token minting are P6.3.
- The subscription page, payment history, and commercial notices are P6.4. This unit shows "Contact support" and the subscription reference on the `suspended` denial.
- The platform's denial responses and the worker check that `/v1/coverage` requires `role = administrator` stay with the platform units named in D1 for 04 §4.2. This unit's desktop does not call that route for staff.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-06, and E2E-P6.2-07 are green in harness H-FL.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-6 default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL).
- Rule S9: the desktop `GET /v1/usage` call is replaced in this unit. Platform removal of that route remains P3.9. This unit names no other transitional path.
