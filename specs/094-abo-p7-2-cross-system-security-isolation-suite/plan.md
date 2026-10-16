# Implementation Plan: Cross-system security and isolation suite

**Branch**: `ai/094-abo-p7-2-cross-system-security-isolation-suite` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/094-abo-p7-2-cross-system-security-isolation-suite/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Nine H-FS scenarios prove the outsider, wrong-clinic, compromised-ABO, operator, and credential boundaries already named in 02 §2, 02 §4.2, 02 §4.3, and 05 §8 rows A22, A26, A27, A35, and A36. This is phase P7, size M, and **Depends** P6.4 and P4.11.

## Technical Context

**Language/Version**: Node.js tests (`node:test`) under `e2e/fullstack/`, the existing TypeScript harness worker, and one Dart driver. The frontend package `ai_clinic` is already on Dart SDK ^3.11.5.

**Primary Dependencies**: The H-FS stack this repo already runs: local Supabase, `wrangler` for the platform worker, the ABO worker, and the Paymob stub, plus `tsx`, `@supabase/supabase-js`, and `vendor-contracts` (`canonicalize` for the paid-grant envelope). The Dart driver uses `DiscoveryClient`, `PlatformHttpsSubmitPort` (the `HttpsSubmitPort` in `https_submit_port.dart`), `UsageSummaryClient`, and `AboClient`. No new library.

**Storage**: N/A. This unit defines no entities. Tests read and write only the local Supabase database and the local D1 databases the H-FS stack already uses.

**Testing**: Harness H-FS. Three Node files, one per user story. Each E2E id is one test whose title starts with that id (rule V3). Tests are written before any product edit and observed failing before a defect fix. This plan does not boot wrangler and does not run the suite. The command for this unit only, from `e2e/fullstack/`:

`node --import tsx --test test/p7-2-untrusted-callers.test.mjs test/p7-2-vendor-entrypoint.test.mjs test/p7-2-credential-isolation.test.mjs`

**Target Platform**: Local H-FS. Platform `http://127.0.0.1:8787`, ABO `http://127.0.0.1:8788`, Paymob stub `http://127.0.0.1:8789`, harness worker `http://127.0.0.1:8790`. Billing host `billing.vendor.test`. Ops host `ops.vendor.test`.

**Project Type**: Tests in `e2e/fullstack/` only. No wiring exception. No new platform route and no new ABO route. No file under `frontend/test/`.

**Performance Goals**: N/A. This unit adds no request path.

**Constraints**: On `POST /notify/{provider}` the body cap is 1_048_576 bytes and the limit is 60 requests per 60 seconds keyed by `CF-Connecting-IP` (a missing header uses the key `unknown`). Over-cap is HTTP 413 and over-limit is HTTP 429, both with an empty body and nothing stored or enqueued. `/return` only schedules an inquiry. The tenant comes from the session. Paid grants use the ABO grant key the H-FS platform already trusts (`kid` `abo-grant-test`). Class H and class HP go through the harness worker in the rule V2 `vendorCall` shape (`access_jwt`, and `assertion` when present). The CI/staging case sends a fixture token and no assertion. A defect fix, if a red test shows one, changes no contract.

**Scale/Scope**: Size M (rule S3: three user stories, one codebase, nine E2E ids). Implied task count is 16 (the sequencing below).

The harness worker is the existing test-only worker `e2e/fullstack/src/register-issuer.ts`, already bound to the real platform `VendorEntrypoint`. This unit adds `POST /vendor-call` on that worker. The body is `{ method, args }`. `args` is the `vendorCall` payload. The worker calls `env.PLATFORM[method](args)` only for `grant`, `suspend`, `resume`, `armKillSwitch`, `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, and `voidGrant`. Any other method answers 404. The Node runner is the only caller. `POST /register-issuer-key` stays as it is.

A paid grant is `grant` with `abo_kid`, `abo_signature`, and `envelope_b64`. The envelope is canonicalized with `vendor-contracts` and signed with the H-FS ABO grant key. A grant past the published plan version's term units or allowance maximum is rejected and does not apply. A grant inside that bound applies. The published plan row already on the H-FS platform is the bound. The within-bound grant has no ABO payment.

AL-11 and AL-17 are captured from the platform development `SEND_EMAIL` binding (rule V6). Local wrangler logs `send_email binding called with MessageBuilder` and the text-file path. The story-2 test reads that log from the platform worker and reads the text file. The AL-11 text is the decoded operation. After the within-bound grant, the test triggers the ABO cron `0 6 * * *` through the local `/__scheduled` path (`--test-scheduled` on the ABO process this unit starts). That runs `scheduled()` → `runReconciliation`. The ABO D1 `finding` row kind is `grant_without_payment`.

The CI/staging fixture is the literal string `ci-staging-token` in the story-2 test. It is not read from the environment. It is sent as `access_jwt` with `assertion` omitted.

The Dart driver records every outbound URL and `Authorization` header. The Supabase session JWT is in the driver process and is not the AI token or the billing token those clients send.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no `research.md`. Freezes are none, so there is no `contracts/` directory. The spec defines no entities, so there is no `data-model.md`. The same boxes hold after this plan. This unit adds no constitution violation, so Complexity Tracking stays empty.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One clinic's staff and administrator stay inside that clinic. An internet caller cannot create service by posting to payment URLs. The suite proves those boundaries on the local full stack (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The change is H-FS tests, one route on the existing harness worker, and a Dart driver. No new worker, queue, or service (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  The suite calls the existing desktop clients, PostgREST, the ABO worker, and the platform worker. It adds no domain rule (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit defines no tables, constraints, RLS policies, or RPCs. Clinic-side integrity stays where it already is. Vendor-side integrity stays on the existing D1 and entrypoint checks (spec §4.1, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  The tenant comes from the session. Foreign ids answer `not_found`. Staff cannot mint a billing token or write status. Class HP needs a passkey. Worker configs hold no Supabase credential (spec §4.1, 02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  The suite proves the workers hold no database credential and the desktop session JWT never leaves for the ABO or the platform. It does not hard-lock clinical work (spec §4.1, 02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One H-FS suite. No new service. |
| II. Replaceable layer boundaries | Codebase is `e2e/fullstack/`. The desktop, Supabase, ABO, and platform stay behind the calls the spec names. |
| III. Backend authority and data integrity | No tables and no RPCs. Status stays without a write RPC. |
| IV. Secure and human-gated operations | Session tenant, staff refusal, plan bounds, passkey for HP, no Supabase credential in worker config. |
| V. Operational continuity | The suite observes refusals. It does not lock the clinic out of existing data. |
| Workflow automation | The ABO daily cron is triggered only so reconciliation can raise `grant_without_payment`. No new scheduler. |
| Higher operational burden | No new operational part. |

## Project Structure

### Documentation (this feature)

```text
specs/094-abo-p7-2-cross-system-security-isolation-suite/
├── plan.md
├── spec.md
├── escalations.md
└── quickstart.md          # after this unit's tests are green; outline below
```

`research.md` is omitted. Spikes are none. `data-model.md` is omitted. The spec defines no entities. `contracts/` is omitted. This unit freezes no wire shape.

`quickstart.md` is not written in this phase. After the harness is green, implement fills only these sections:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only, from `e2e/fullstack/`: `node --import tsx --test test/p7-2-untrusted-callers.test.mjs test/p7-2-vendor-entrypoint.test.mjs test/p7-2-credential-isolation.test.mjs`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour. These nine scenarios are harness-visible, so the outline has no manual step

### Source Code (repository root)

```text
e2e/fullstack/src/register-issuer.ts
e2e/fullstack/test/p7-2-stack.mjs
e2e/fullstack/test/p7-2-untrusted-callers.test.mjs
e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs
e2e/fullstack/test/p7-2-credential-isolation.test.mjs
e2e/fullstack/dart/pubspec.yaml
e2e/fullstack/dart/bin/session_jwt_capture.dart
```

**Structure Decision**: All of this unit lives under `e2e/fullstack/`. The three test files are the three user stories. `p7-2-stack.mjs` boots the same H-FS processes `e2e/fullstack/test/p5-2.test.mjs` already boots, and is imported by all three test files. `register-issuer.ts` remains the harness worker and gains `POST /vendor-call`. The Dart package path-depends on `frontend/` so the driver can construct the four existing clients. `e2e/fullstack/package.json` is left on its current `test` script so this unit does not replace the earlier-suite command.

## Consumes Binding

None. P6.4 and P4.11 publish no Outputs / freezes line. This unit does not import or modify their modules.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `e2e/fullstack/src/register-issuer.ts` | Modify. Add `POST /vendor-call` for the eight methods in Technical Context. Leave `POST /register-issuer-key` in place | FR-005, FR-006, FR-007 |
| `e2e/fullstack/test/p7-2-stack.mjs` | Create. Boot local Supabase, the platform worker, the harness worker, the Paymob stub, and the ABO worker the way `p5-2.test.mjs` does. Start the ABO process with `--test-scheduled`. Capture platform `send_email` text from the worker log. Read ABO D1 with `wrangler d1 execute` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` | Create. One test each for E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04 | FR-001, FR-002, FR-003, FR-004 |
| `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs` | Create. One test each for E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 | FR-005, FR-006, FR-007 |
| `e2e/fullstack/test/p7-2-credential-isolation.test.mjs` | Create. One test each for E2E-P7.2-07 and E2E-P7.2-08 | FR-008, FR-009 |
| `e2e/fullstack/dart/pubspec.yaml` | Create. Package `abo_p7_2_session_capture`, `publish_to: none`, SDK ^3.11.5, path dependency `ai_clinic` → `../../../frontend` | FR-009 |
| `e2e/fullstack/dart/bin/session_jwt_capture.dart` | Create. Driver. Constructs the four clients with a recording `http.Client`. Prints JSON `{url, authorization}` for each outbound call | FR-009 |
| `specs/094-abo-p7-2-cross-system-security-isolation-suite/quickstart.md` | Create after this unit's tests are green | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |

Product files are not in this table. If a scenario is red because existing behaviour misses its FR, the later implement step fixes that behaviour with no contract change and no new platform or ABO route.

## Test Layout

Harness H-FS. A row is one test (rule V3). Each test is red before any product edit.

| ID | Title prefix | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P7.2-01 | `E2E-P7.2-01` | ABO `fetch` → `POST /notify/paymob` and `GET /return/paymob` on `BILLING_HOST` | Junk is rate-limited and not stored. A body over 1_048_576 bytes is HTTP 413 with an empty body and nothing stored or enqueued. The request past 60 in 60 seconds is HTTP 429 with an empty body and nothing stored or enqueued. The key is `CF-Connecting-IP`, and a missing header uses `unknown`. `/return` does not create or extend service |
| E2E-P7.2-02 | `E2E-P7.2-02` | PostgREST `public.issue_billing_token` and staff RPCs including `get_ai_status`; platform `GET /v1/coverage` | A staff user cannot obtain a billing token. `/v1/coverage` is 403. No RPC writes status. The status row is unchanged |
| E2E-P7.2-03 | `E2E-P7.2-03` | ABO `handleBillingV1` paths `/v1/offers`, `/v1/subscription`, `/v1/payments`, `/v1/billing-contact`, `/v1/checkouts`, `/v1/checkouts/{id}`; PostgREST RPCs the administrator session can execute; platform `GET /v1/capabilities`, `POST /v1/requests`, `GET /v1/coverage`, `GET /v1/feed/coverage` | Org A's administrator replays B's ids. The answer is not found. B is unchanged. No token is obtained for B. A's open checkout locks nothing of B's. The ABO and RPCs take the tenant only from the session |
| E2E-P7.2-04 | `E2E-P7.2-04` | ABO `POST /notify/paymob`, then the ABO inquiry of that callback against the H-FS Paymob stub | A callback forged with the leaked HMAC secret (the secret the ABO worker is started with) does not confirm. No payment is created. Inquiry answers are matched to the checkout's stored order id, amount, and currency |
| E2E-P7.2-05 | `E2E-P7.2-05` | Harness `POST /vendor-call` → `VendorEntrypoint.grant` and the class HP methods. Platform `SEND_EMAIL` for AL-11 and AL-17. ABO `scheduled` cron `0 6 * * *` → `runReconciliation` | A paid grant beyond the published plan bound is rejected. One within the bound applies and raises AL-11, AL-17, and finding kind `grant_without_payment`. An HP call without an assertion is rejected. The AL-11 body shows the operation the passkey signed, when that operation is not the one shown to the operator |
| E2E-P7.2-06 | `E2E-P7.2-06` | Class H: harness `POST /vendor-call` → `suspend`, `resume`, `armKillSwitch`; ABO `POST /ops/checkouts/{id}/cancel` and `POST /ops/parked/{id}/retry` with `Cf-Access-Jwt-Assertion`. Class HP: `grant` (complimentary), `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant` | An Access JWT alone allows the class H actions and rejects the class HP actions. A passkey plus a session still enforces ceilings. A complimentary grant of a year is blocked by the 31-day ceiling |
| E2E-P7.2-07 | `E2E-P7.2-07` | `abo/wrangler.toml` and `ai-platform/wrangler.toml`; PostgREST on local Supabase | Neither config holds a Supabase credential. A billing token, an AI token, and a feed token presented to PostgREST are rejected |
| E2E-P7.2-08 | `E2E-P7.2-08` | Story-3 Node test → `dart run bin/session_jwt_capture.dart` → `DiscoveryClient`, `PlatformHttpsSubmitPort`, `UsageSummaryClient`, `AboClient` | The captured URL and `Authorization` headers for the ABO and the platform do not contain the Supabase session JWT |
| E2E-P7.2-09 | `E2E-P7.2-09` | Harness `POST /vendor-call` → class HP methods `grant`, `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant` | The fixture token `ci-staging-token`, with no assertion, cannot reach any of those methods |

## Sequencing

Tests before implementation. The nine tests are observed failing, then any defect fix, then those tests pass. Implied task count: 16. Do not run `npm test` in `e2e/fullstack`. The command is the three-file `node --test` line in Technical Context.

1. Add `POST /vendor-call` on `e2e/fullstack/src/register-issuer.ts` for the eight methods.
2. Add `e2e/fullstack/dart/pubspec.yaml` and `e2e/fullstack/dart/bin/session_jwt_capture.dart`.
3. Add `e2e/fullstack/test/p7-2-stack.mjs` to boot H-FS, capture `send_email`, and read ABO D1.
4. Add the failing test `E2E-P7.2-01` in `p7-2-untrusted-callers.test.mjs`.
5. Add the failing test `E2E-P7.2-02` in the same file.
6. Add the failing test `E2E-P7.2-03` in the same file.
7. Add the failing test `E2E-P7.2-04` in the same file.
8. Add the failing test `E2E-P7.2-05` in `p7-2-vendor-entrypoint.test.mjs`.
9. Add the failing test `E2E-P7.2-06` in the same file.
10. Add the failing test `E2E-P7.2-09` in the same file.
11. Add the failing test `E2E-P7.2-07` in `p7-2-credential-isolation.test.mjs`.
12. Add the failing test `E2E-P7.2-08` in the same file. It starts the Dart driver.
13. Run the three-file command and confirm the nine tests fail before any product edit.
14. Where a failure is existing behaviour that misses that test's FR, fix it with no contract change and no new platform or ABO route.
15. Re-run the same three-file command until E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-07, E2E-P7.2-08, and E2E-P7.2-09 pass.
16. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded in 02 §7 for this unit. Nothing to justify.
