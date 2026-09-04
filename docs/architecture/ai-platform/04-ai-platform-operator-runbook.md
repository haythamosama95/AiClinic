# AI Platform — Operator Runbook

- Purpose: Explain how to run the implemented AI platform stack locally, what is visible from the Flutter UI, and how to observe each band’s behaviour through Wrangler (D1, R2, logs, crons) and control-plane HTTP.
- Read this when: exercising AI features after delivery-plan slices are complete, debugging a request by reference, or verifying enroll / support / deprecation / canary operations.
- Canonical for: day-to-day run and observe recipes across bands A–J (as built). Not a substitute for architecture decisions in `01-ai-platform.md` or slice boundaries in `03-ai-platform-delivery-plan.md`.
- Usually paired with: [`03-ai-platform-delivery-plan.md`](03-ai-platform-delivery-plan.md), [`01-band-a`](implementation-references/01-band-a-implementation-reference.md) / [`02-band-b`](implementation-references/02-band-b-implementation-reference.md) / [`03-band-c`](implementation-references/03-band-c-implementation-reference.md) band references, and per-slice `specs/*/quickstart.md`.

> **Honesty rule:** Automated tests are the primary proof of slice completion (delivery-plan DP-3). Several client and pipeline pieces ship as libraries + suites before full product wiring. This runbook marks those gaps explicitly so UI and Wrangler expectations stay accurate.

---

## Table of Contents

1. [What You Can Observe Today](#1-what-you-can-observe-today)
2. [Prerequisites](#2-prerequisites)
3. [Start the Local Stack](#3-start-the-local-stack)
4. [Frontend UI — Clinic AI Hub](#4-frontend-ui--clinic-ai-hub)
5. [Enable AI for a Clinic Installation](#5-enable-ai-for-a-clinic-installation)
6. [Wrangler Environment](#6-wrangler-environment)
7. [HTTP Surfaces](#7-http-surfaces)
8. [Observe by Band](#8-observe-by-band)
9. [Verification Without the UI](#9-verification-without-the-ui)
10. [Spec Index](#10-spec-index)
11. [Where to Read More](#11-where-to-read-more)

---

## 1. What You Can Observe Today

| Surface | What works in a local clinic build | Primary verification |
| --- | --- | --- |
| **Worker `/health`** | Build + environment identity | `curl` against Wrangler dev |
| **Control plane** | Enroll / lifecycle, support lookup, purge, deprecate/retire, canary, token rotation | Bearer-authenticated `curl` + D1 `control_audit` |
| **Journal get-request** | `GET /v1/requests/{reference}` | AAT + D1/R2 |
| **Flutter AI hub (`/ai`)** | Availability gate, visit-summary host shell, degraded-mode demos, design-system AI widgets | Visual + availability RPC |
| **Live visit-summary invoke** | Host loads when enrolled; **invoke stays idle** until production AAT mint / HTTPS submit adapters are composed on the hub | Widget tests / injected host deps |
| **Clinical accept (F2)** | Library + SQL/Flutter tests; **not** wired into E4 advisory accept | SQL + Flutter suites |
| **Conversational chat (H3)** | Store + negotiation loop library; **no product chat screen** on `AiPage` | Unit tests + D1 conversation columns |
| **`context_required` self-heal (J2)** | Library; production host wiring deferred | Flutter unit tests |
| **Discovery** | In-process `discover()` library | Workers tests (no HTTP route yet) |
| **Inference / stream broker** | Modules + fixture/eval suites; composition exercised heavily in Vitest | `npm test`, eval harness, load suite |

---

## 2. Prerequisites

| Piece | Requirement |
| --- | --- |
| Node | **22+** (`nvm use` from repo root; see `.nvmrc`) |
| Flutter | SDK per `frontend/pubspec.yaml` |
| Supabase | Local stack with AI migrations applied (keystore, AAT issuer, availability, context RPC, acceptance) |
| Cloudflare | Account + Wrangler login for remote deploy; **not** required for Vitest Miniflare suites |
| Secrets (Worker) | `OPERATOR_BEARER_TOKEN`; provider keys `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` for live smoke only |

---

## 3. Start the Local Stack

### 3.1 AI gateway (Wrangler)

```bash
nvm use
cd ai-platform
npm install
npx wrangler secret put OPERATOR_BEARER_TOKEN --env development   # once per machine/env
npm run dev
# → http://127.0.0.1:8787
```

Smoke:

```bash
curl -s http://127.0.0.1:8787/health | jq .
# {"build":"…","environment":"development"}
```

Apply local D1 migrations when inspecting a real local D1 (not only Miniflare tests).
D1 is defined only under named envs in `wrangler.toml`, so always pass `--env development`
(or `staging` / `production`):

```bash
cd ai-platform
npx wrangler d1 migrations list ai-platform-development --local --env development
npx wrangler d1 migrations apply ai-platform-development --local --env development
```

### 3.2 Clinic backend (Supabase)

Start local Supabase as usual for this repo, then confirm AI RPCs exist, for example:

```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "\df public.issue_ai_token"
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "\df public.get_ai_availability"
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "\df public.record_ai_acceptance"
```

Trust / acceptance SQL suites:

```bash
bash backend/tests/run_ai_platform_trust_tests.sh
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/ai_acceptance_recording.sql
```

### 3.3 Flutter client

```bash
cd frontend
flutter run
```

There is **no** AI-specific `--dart-define` for the Worker URL. The clinic reads `{ enrolled, platform_base_url }` from `public.get_ai_availability()` (seeded in `ai_internal.app_settings`).

---

## 4. Frontend UI — Clinic AI Hub

### 4.1 Navigation

1. Sign in to the desktop app against local Supabase.
2. Open the sidebar item **AI** (`AppNavItem` id `ai`) → route `/ai`.
3. Page implementation: `frontend/lib/features/ai/presentation/pages/ai_page.dart` (`AiPage`).

Standalone CP3 / widget host (injected dependencies): route `/ai/feature-host` → `AiFeatureHostPage`.

### 4.2 Sections on `/ai`

| Section | What to look at | Slice |
| --- | --- | --- |
| **Visit summary** | Enter a visit UUID → **Load surface**. When enrolled, the live host mounts `AiFeatureHostPage` (availability + reachability). Caption states invoke is idle until mint/submit adapters are wired. Below: static provisional prose, demo request reference, Accept/Discard buttons (demo only). | E4 |
| **Degraded modes** | Buttons cycle `AiDegradedMode` banners (`unreachable`, `quotaExhausted`, `providerUnavailable`, …). These are first-class states, not error dialogs. | E4 |
| **AI mode toggle / thinking / bubbles / suggestion / proposed action / AI panel** | Design-system widgets for future surfaces (including conversational chrome). Not live Worker traffic. | UI kit |
| **Message bubbles / AI panel** | Visual stand-ins for H-band chat; the real H3 loop lives under `frontend/lib/core/ai/conversation_*.dart`. | H (library) |

### 4.3 What success looks like for visit summary (today)

| Clinic state | Expected UI |
| --- | --- |
| `enrolled: false` | Live affordance hidden; no Worker probe for non-enrolled installations |
| `enrolled: true`, Worker down | Degraded **unreachable** (normal-state banner) after `/health` probe fails |
| `enrolled: true`, Worker up | Host shell for the visit; **no automatic invoke** on the hub page (`autoInvoke: false`) |
| Failure path (when invoke is wired via tests/host) | `RequestReferenceView` shows `Reference: …` for support |

### 4.4 Features not on a product screen yet

| Feature | Where it lives | How to observe |
| --- | --- | --- |
| Clinical accept / provenance (F2) | `frontend/lib/features/ai/acceptance/` | `flutter test` + `record_ai_acceptance` SQL |
| Conversation store / context negotiation (H3) | `conversation_store.dart`, `conversation_loop.dart` | Flutter unit tests; D1 `conversation_id` / `turn_ordinal` |
| `context_required` self-heal (J2) | `context_required_self_heal.dart` | `flutter test test/unit/core/ai/context_required_self_heal_test.dart` |
| Architecture guard (E1) | `frontend/tool/architecture_guard/` | `dart run tool/architecture_guard/architecture_guard.dart` |

---

## 5. Enable AI for a Clinic Installation

End-to-end enrollment spans **clinic Supabase** (keypair + availability flag) and **platform D1** (control-plane enroll).

### 5.1 Clinic: mint installation key material

As an owner/admin session on local Supabase, call the keystore enroll RPC (see B1 quickstart / `02-band-b`):

```sql
SELECT public.enroll_installation_keypair();
-- returns kid, installation_id, public_jwk (shape per B1 contract)
```

### 5.2 Platform: enroll the installation

With Wrangler `npm run dev` and `OPERATOR_BEARER_TOKEN` set:

```bash
export OPERATOR_BEARER_TOKEN='…'   # same value put via wrangler secret
export INSTALLATION_ID='…'
export GATEWAY='http://127.0.0.1:8787'

curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "org_id": "<clinic-org-uuid>",
    "kid": "<kid>",
    "public_key": "<ed25519-public-material-per-contract>",
    "plan": "<plan-id>"
  }' | jq .
# → includes platform_base_url (gateway origin)
```

Other lifecycle actions (same Bearer auth):

| Action | Path |
| --- | --- |
| Rotate | `POST /control/installations/{id}/rotate` |
| Revoke key | `POST /control/installations/{id}/revoke-key` |
| Suspend / resume | `POST /control/installations/{id}/suspend` \| `…/resume` |
| Delete | `POST /control/installations/{id}/delete` |
| Purge stores (F3) | `POST /control/installations/{id}/purge` |

Audit every mutation:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT action, operator_id, recorded_at FROM control_audit ORDER BY recorded_at DESC LIMIT 20"
```

> Enroll creates entitlement status **`pending`** with empty grants. Guard entitlement / quota behaviour for real inference requires activating grants and budgets (control / data setup beyond the enroll happy path). Treat pending enroll as “registered, not yet entitled.”

### 5.3 Clinic: flip availability

```sql
UPDATE ai_internal.app_settings
SET value_json = jsonb_build_object(
  'enrolled', true,
  'platform_base_url', 'http://127.0.0.1:8787'
)
WHERE key = 'ai.availability';

SELECT public.get_ai_availability();
```

### 5.4 Staff AAT (when invoke adapters exist)

```sql
SELECT public.issue_ai_token();
-- scopes derived from RBAC ai.* permissions; never caller-supplied
```

---

## 6. Wrangler Environment

### 6.1 Topology (`ai-platform/wrangler.toml`)

| Env | Worker name | D1 binding name | R2 bucket name |
| --- | --- | --- | --- |
| `development` | `ai-platform-gateway-development` | `ai-platform-development` | `ai-platform-development` |
| `staging` | `ai-platform-gateway-staging` | `ai-platform-staging` | `ai-platform-staging` |
| `production` | `ai-platform-gateway-production` | `ai-platform-production` | `ai-platform-production` |

Per env: Durable Object class `GatewayObject`, rate-limit bindings, vars `BUILD_SHA`, `ENVIRONMENT`, `OPERATOR_ID`.

Scripts (`ai-platform/package.json`):

| Script | Use |
| --- | --- |
| `npm run dev` | Local Worker (`--env development`) |
| `npm run deploy -- --env development` | Deploy that env (after real `database_id` / buckets) |
| `npm test` | Manifest gates + unit + workers suites |
| `npm run test:load` | F5 load / cost assertions |
| `npm run verify-manifests` | Manifest + prompt registry gates only |
| `npm run types` | `wrangler types` |

### 6.2 Inspect D1

```bash
cd ai-platform

# Recent requests
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_reference, state, capability_id, routing_tier,
          conversation_id, turn_ordinal, terminal_error_code, created_at
   FROM ai_request ORDER BY created_at DESC LIMIT 20"

# Attempts + usage
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, attempt_ordinal, provider_id, outcome FROM ai_attempt ORDER BY created_at DESC LIMIT 20"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT * FROM usage_event ORDER BY created_at DESC LIMIT 20"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT * FROM usage_rollup LIMIT 20"

# Conversation legs (H3)
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_reference, turn_ordinal, state
   FROM ai_request
   WHERE conversation_id = '<conversation-uuid>'
   ORDER BY turn_ordinal"
```

Omit `--local` for remote D1 after deploy (keep `--env development`).

### 6.3 Inspect R2

Journal diagnostic envelope key pattern:

```text
request/{request_id}/envelope
```

Routing-policy artifacts (J3):

```text
control/routing-policy/{policyId}/{version}.json
```

```bash
npx wrangler r2 object get ai-platform-development \
  "request/<request_id>/envelope" --file /tmp/envelope.json --local
```

### 6.4 Durable Objects (quota / admission)

Class: `GatewayObject`, id typically derived from installation id. There is no first-class Wrangler “dump DO storage” recipe in-repo. Observe via:

- Admission / credit behaviour in workers tests (`test/quota-do.test.ts`, `test/admission-credit.test.ts`)
- Worker logs during `POST /v1/requests`
- Soft-threshold fields on journal rows / SSE (`routing_tier`, degraded notices) after F4

### 6.5 Crons and logs

| Cron (UTC) | Job |
| --- | --- |
| `0 3 * * *` | Retention purge (F3) |
| `0 4 * * *` | Usage rollup + reconciliation (F3) |

Locally, scheduled handlers are covered by Vitest; on Cloudflare, use Workers → Triggers / Logs for the env.

```bash
npx wrangler tail --env development
```

### 6.6 Remote provision (once)

From `specs/015-ai-worker-skeleton/quickstart.md`:

```bash
cd ai-platform
npx wrangler login
npx wrangler d1 create ai-platform-development
npx wrangler r2 bucket create ai-platform-development
# paste real database_id into wrangler.toml
export BUILD_SHA="$(git -C .. rev-parse HEAD)"
npx wrangler deploy --env development --var BUILD_SHA:"$BUILD_SHA"
npx wrangler d1 migrations apply ai-platform-development --env development
```

---

## 7. HTTP Surfaces

All control routes require `Authorization: Bearer $OPERATOR_BEARER_TOKEN`.

### 7.1 Public / client

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| `GET` | `/health` | none | `{ build, environment }` |
| `POST` | `/v1/requests` | AAT (when pipeline auth is engaged) | SSE adapter entry (`handleAdapterRequest`) |
| `GET` | `/v1/requests/{reference}` | AAT | Journal get-request (C3) |

Discovery is **not** an HTTP route; use library `discover()` / workers tests (`03-band-c`).

### 7.2 Support lookup (F3)

```bash
curl -s -X POST "$GATEWAY/control/support/lookup?reference=XXXX-XXXX" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" | jq .
```

Expect one indexed D1 lookup + at most one R2 `GetObject` worth of envelope data when the diagnostic horizon still holds.

### 7.3 Compatibility / ops (band J)

| Concern | Example path |
| --- | --- |
| Deprecate / retire capability version (J1) | `POST /control/capabilities/{id}/versions/{v}/deprecate` \| `…/retire` |
| Cohort activate / promote (J3) | `POST /control/capabilities/{id}/versions/{v}/activate` \| `…/promote` |
| Routing policy canary (J3) | `POST /control/routing-policies/publish` \| `…/{id}/versions/{v}/canary` \| `promote` \| `rollback` |
| Token contract rotation (J4) | `POST /control/token-contract/begin-rotation` \| `…/retire` |

Confirm each mutation in `control_audit` and, for canary, D1 `routing_policy` / R2 policy objects.

---

## 8. Observe by Band

### 8.1 Band A — Foundations

| Observe | How |
| --- | --- |
| Env isolation + health | `npm run dev` + `/health`; `test/env-deploys.test.ts`, `test/health.test.ts` |
| Contracts | Unit/contract suites under `ai-platform/test/` (errors, canonical types, manifests, schema, SSE framing) |

No clinic UI.

### 8.2 Band B — Trust and admission

| Observe | How |
| --- | --- |
| Keystore / AAT | Supabase RPCs + `backend/tests/run_ai_platform_trust_tests.sh` |
| Enrollment | Control `curl` (§5) + D1 `installation` / `installation_key` / `entitlement` / `control_audit` |
| Guard rejects | Workers tests (`test/guard*.ts` / related); no `ai_request` row on guard rejection |
| Quota DO | `test/quota-do.test.ts`, `test/admission-credit.test.ts` |

### 8.3 Band C — Capability, context, journal

| Observe | How |
| --- | --- |
| Resolver / discovery | Workers tests; discovery library only |
| Context validation | Missing keys → `context_required` (tests); clinic context RPC `get_visit_chief_complaint` |
| Journal | `GET /v1/requests/{ref}`; D1 + R2 envelope; `test/journal.test.ts` |

### 8.4 Band D — Inference path

| Observe | How |
| --- | --- |
| Prompts / routing / retry / stream / validators / adapters | Focused Vitest files (`prompt`, `routing`, `invocation`, `stream-broker`, provider fixtures, response validator) |
| Real providers | Secrets + `test/eval/live-smoke.test.ts` (skipped without keys) |
| Second provider (D7) | Adapter fixtures + routing-policy-only registration |

UI does not yet drive a live stream from the hub page.

### 8.5 Band E — Client integration

| Observe | How |
| --- | --- |
| E1 guard | `cd frontend && dart run tool/architecture_guard/architecture_guard.dart` |
| E2 SDK | `flutter test test/unit/core/ai/ai_client_sdk_test.dart` |
| E3 resolver | Context provider tests + live-manifest contract tests per E3 quickstart |
| E4 surface | `/ai` visit summary + degraded demos; `flutter test test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart` |

### 8.6 Band F — Hardening

| Observe | How |
| --- | --- |
| F1 evals | `npx vitest run test/eval/golden.test.ts test/eval/live-smoke.test.ts …` → reports under `ai-platform/test/eval/reports/` |
| F2 acceptance | SQL + Flutter clinical accept tests; registry row `visit_clinical_notes` |
| F3 support / retention / rollups / dashboards | Support `curl`; crons; `test/support-lookup.test.ts`, `retention`, `rollup-reconciliation`, `journal-dashboards` |
| F4 soft threshold | `routing_tier` / degraded SSE; `test/soft-threshold-routing.test.ts` |
| F5 load | `npm run test:load` |

### 8.7 Band H — Conversational

| Observe | How |
| --- | --- |
| Manifest conversational fields | Manifest build gates |
| Transcript budgets / composer | Unit/golden tests (H2) |
| Journal columns + client loop | D1 conversation query; `test/conversational-journaling.test.ts`; Flutter conversation unit tests |
| Conversation evals (H4) | `npx vitest run test/eval/conversation.test.ts` |

`AiPage` message bubbles / AI panel are **visual only**.

### 8.8 Band J — Compatibility

| Observe | How |
| --- | --- |
| J1 deprecation | Control deprecate/retire + discovery announce in tests |
| J2 self-heal | Flutter `context_required_self_heal_test.dart` (host wiring deferred) |
| J3 canary | Control canary/promote/rollback + `control_audit` + policy R2 |
| J4 token `ver` overlap | Control begin-rotation / retire + verifier tests |

---

## 9. Verification Without the UI

Prefer these when confirming a slice after a pull:

### 9.1 Full platform suite

```bash
cd ai-platform
npm test
npm run test:load
```

### 9.2 High-signal focused suites

```bash
cd ai-platform
npx vitest run --config vitest.workers.config.ts test/control.test.ts
npx vitest run --config vitest.workers.config.ts test/quota-do.test.ts test/admission-credit.test.ts
npx vitest run --config vitest.workers.config.ts test/journal.test.ts
npx vitest run --config vitest.workers.config.ts \
  test/support-lookup.test.ts test/retention.test.ts \
  test/rollup-reconciliation.test.ts test/journal-dashboards.test.ts
npx vitest run --config vitest.workers.config.ts test/soft-threshold-routing.test.ts
npx vitest run --config vitest.workers.config.ts test/conversational-journaling.test.ts
npx vitest run --config vitest.workers.config.ts test/capability-deprecation.test.ts
npx vitest run --config vitest.workers.config.ts \
  test/cohort-activate-promote.test.ts test/routing-policy-canary.test.ts

npx vitest run test/eval/golden.test.ts test/eval/conversation.test.ts
```

### 9.3 Frontend

```bash
cd frontend
flutter test test/widget/ai/first_ai_feature_surface_test.dart \
             test/widget/ai/ai_degraded_mode_test.dart
flutter test test/widget/ai/clinical_accept_path_test.dart \
             test/unit/ai/clinical_acceptance_client_test.dart
flutter test test/unit/core/ai/ai_client_sdk_test.dart
flutter test test/unit/core/ai/conversation_store_test.dart \
             test/unit/core/ai/conversation_loop_test.dart
flutter test test/unit/core/ai/context_required_self_heal_test.dart
dart run tool/architecture_guard/architecture_guard.dart
```

---

## 10. Spec Index

Delivery-plan slices map to Spec Kit directories:

| Band | Specs |
| --- | --- |
| A | `015`–`020` |
| B | `021`–`024` |
| C | `025`–`027` |
| D | `028`–`034` |
| E | `035`–`038` |
| F | `039`–`043` |
| H | `044`–`047` |
| J | `048`–`051` |

Each directory has `quickstart.md` with slice-scoped commands. Use this runbook for cross-cutting operator flow; use the quickstart for a single slice’s Done-when suite.

---

## 11. Where to Read More

| Doc | Use |
| --- | --- |
| [`01-ai-platform.md`](01-ai-platform.md) | Canonical architecture |
| [`02-ai-platform-overview.md`](02-ai-platform-overview.md) | Mental model |
| [`03-ai-platform-delivery-plan.md`](03-ai-platform-delivery-plan.md) | Slice sequence and checkpoints |
| [`01-band-a`](implementation-references/01-band-a-implementation-reference.md) / [`02-band-b`](implementation-references/02-band-b-implementation-reference.md) / [`03-band-c`](implementation-references/03-band-c-implementation-reference.md) | What bands A–C built |
| `ai-platform/README.md` | Gateway directory orientation |
| `specs/*/quickstart.md` | Per-slice run / inspect / test |

### 11.1 Known product gaps (do not treat as bugs of this runbook)

1. Hub-page live invoke adapters (AAT mint + HTTPS submit) are not composed — `/ai` visit summary stays idle by design.
2. HTTP discovery route is not wired.
3. F2 clinical accept, H3 chat, and J2 self-heal are library + test proven; product screens / host wiring follow later integration work.
4. Band G (commercial) and band K (explicitly later) remain out of scope per `03-ai-platform-delivery-plan` §4.
