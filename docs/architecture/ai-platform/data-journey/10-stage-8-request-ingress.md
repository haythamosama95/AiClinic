# AI Platform Data Journey — Stage 8 — Request ingress (`POST /v1/requests`)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [Required headers — every field](#3-required-headers-every-field)
  - `[Authorization](#31-authorization)`
  - `[x-idempotency-key](#32-x-idempotency-key)`
  - `[x-capability-version](#33-x-capability-version)`
  - `[x-trace-id](#34-x-trace-id)`
  - `[Content-Length](#35-content-length)`
4. [Body — every field](#4-body-every-field)
  - `[capability_id](#41-capability_id)`
  - `[user_intent](#42-user_intent)`
  - `[context](#43-context)`
  - `[conversation_id](#44-conversation_id)`
  - `[turn_ordinal](#45-turn_ordinal)`
  - `[transcript](#46-transcript)`
  - [Ignored body keys](#47-ignored-body-keys)
5. [Ingress validation (before guard)](#5-ingress-validation-before-guard)
6. [Pre-accept (](#6-pre-accept-createproductionpreaccept)`createProductionPreAccept`[)](#6-pre-accept-createproductionpreaccept)
7. [Visit summary example body](#7-visit-summary-example-body)
8. [Behavioral verification](#8-behavioral-verification)
   - [8.1 Setup](#81-setup)
   - [8.2 Coverage](#82-coverage)
   - [8.3 Ordered probes](#83-ordered-probes)
     - [8.3.1 Worker up and curl skeleton](#831-worker-up-and-curl-skeleton)
     - [8.3.2 Oversized body](#832-oversized-body)
     - [8.3.3 JSON parse never reaches the guard](#833-json-parse-never-reaches-the-guard)
     - [8.3.4 Required headers omitted or empty](#834-required-headers-omitted-or-empty)
     - [8.3.5 Optional x-trace-id and Content-Length](#835-optional-x-trace-id-and-content-length)
     - [8.3.6 Who may call](#836-who-may-call)
     - [8.3.7 Pre-accept capability_id and request_reference](#837-pre-accept-capability_id-and-request_reference)
     - [8.3.8 Ignored routing body keys](#838-ignored-routing-body-keys)
     - [8.3.9 Optional and conversational body fields](#839-optional-and-conversational-body-fields)
     - [8.3.10 Mint an AAT and visit summary through ingress](#8310-mint-an-aat-and-visit-summary-through-ingress)
     - [8.3.11 Listed wrong values after ingress](#8311-listed-wrong-values-after-ingress)
     - [8.3.12 What this stage does not do](#8312-what-this-stage-does-not-do)

---



## 1. Plain language

The client submits an AI job: which capability, what context, optional intent text. The adapter validates size and headers before the guard runs.

## 2. Metaphor

**Checking in at the gate** — security scans your bag (body size), checks your ticket number (idempotency key), before you enter the terminal (SSE stream).

## 3. Required headers — every field


| Header                 | Required        | Validation              | Used for                                     |
| ---------------------- | --------------- | ----------------------- | -------------------------------------------- |
| `Authorization`        | effectively yes | `Bearer <AAT>`          | Guard stage 2                                |
| `x-idempotency-key`    | **yes**         | non-empty after trim    | Quota DO idempotency                         |
| `x-capability-version` | **yes**         | non-empty after trim    | Guard stages 3, 5, 10                        |
| `x-trace-id`           | optional        | if present, non-empty   | Correlation; server generates ULID if absent |
| `Content-Length`       | optional        | if > 1_048_576 → reject | Pre-read size gate                           |




### 3.1 `Authorization`


| Aspect      | Detail                                                                                                                                                               |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wire format | `Bearer <AAT>` — single space after `Bearer`, token is the compact JWS from [Stage 6 — Minting an AAT](08-stage-6-minting-an-aat.md)                                 |
| Meaning     | Proves **who** is invoking: which installation, staff actor, org, branch, and granted `ai.`* scopes                                                                  |
| When parsed | Guard stage 2 (inside `createProductionPreAccept`, before SSE opens)                                                                                                 |
| On success  | Produces the **Principal** (`installationId`, `organizationId`, `branchId`, `actorId`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`) used by every later guard stage |
| On failure  | HTTP JSON with taxonomy code (typically `401 unauthenticated` or `installation_suspended`) — no SSE stream                                                           |
| Note        | The adapter does not reject a missing header itself; the guard does. In practice every production client must send a valid AAT.                                      |




### 3.2 `x-idempotency-key`


| Aspect            | Detail                                                                                                                                                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wire format       | Opaque string chosen by the client (UUID, hash, or stable business key)                                                                                                                                                    |
| Meaning           | **Retry safety ticket** — identifies one logical AI job so network retries do not double-charge quota or spawn duplicate provider calls                                                                                    |
| Validation        | Required; whitespace-only after trim → HTTP 422 (adapter, before guard)                                                                                                                                                    |
| Where stored      | Passed to Quota DO admission (guard stage 8), journaled on `ai_request.idempotency_key` (stage 9)                                                                                                                          |
| Idempotent replay | Same `(installationId, idempotencyKey)` while the prior request is still in-flight or terminal → admission returns `idempotent`; guard **skips** journal INSERT and prompt compose; SSE replays the prior terminal outcome |
| Client guidance   | Generate once per user action; reuse the same key on retries of that action; use a new key for a genuinely new job                                                                                                         |




### 3.3 `x-capability-version`


| Aspect         | Detail                                                                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Wire format    | Semver string matching a published manifest version (e.g. `1.0.0`)                                                                               |
| Meaning        | **Which revision** of the capability playbook the client compiled against — pairs with body `capability_id` to select the frozen manifest bundle |
| Validation     | Required; whitespace-only after trim → HTTP 422                                                                                                  |
| Guard stage 3  | Entitlement / grant checks use `(capability_id, capability_version)` against D1 `capability_grant`                                               |
| Guard stage 5  | Registry lookup key: `{capability_id}@{x-capability-version}` — unknown → `404 capability_unknown`; retired lifecycle → `capability_retired`     |
| Guard stage 10 | Resolved manifest drives context requirements, prompt artifacts, economics ceilings, and routing policy ref for compose                          |
| Discovery link | Values should match what [Stage 7 — Discovery](09-stage-7-discovery.md) returned for that capability                                             |




### 3.4 `x-trace-id`


| Aspect          | Detail                                                                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Wire format     | Any non-empty string; convention is ULID                                                                                                     |
| Meaning         | **End-to-end correlation id** — ties adapter logs, guard stages, D1 journal row, SSE events, and support lookup to one client-visible trace  |
| Validation      | Optional; if the header is present it must be non-empty after trim (empty → HTTP 422)                                                        |
| Default         | Server generates a ULID via `resolveTraceId` when the header is absent                                                                       |
| Propagation     | Stored on `ai_request.trace_id`; echoed on every SSE event (`accepted`, `heartbeat`, `text_delta`, terminal events) and on HTTP error bodies |
| Client guidance | Supply your own trace id when bridging from clinic-app logging; omit to let the platform assign one                                          |




### 3.5 `Content-Length`


| Aspect      | Detail                                                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| Wire format | Standard HTTP content length in bytes                                                                                      |
| Meaning     | **Early size hint** — lets the adapter reject oversize bodies before streaming the full payload                            |
| Validation  | Optional; when present and numeric, values **> 1_048_576 (1 MiB)** → HTTP 413 `request_too_large` without reading the body |
| Fallback    | When absent, the adapter stream-reads the body and aborts at the first chunk that would exceed the same 1 MiB cap          |
| Note        | The guard re-checks UTF-8 byte length at stage 1; this header is an optimization, not the sole gate                        |




## 4. Body — every field

JSON object (`Content-Type: application/json`). Must parse to a **plain object** (not array, not scalar). Empty body parses as failure → HTTP 422.


| Field             | Aliases          | Required             | Default | Consumer                             |
| ----------------- | ---------------- | -------------------- | ------- | ------------------------------------ |
| `capability_id`   | `capability`     | **yes** (pre-accept) | —       | Entire pipeline                      |
| `user_intent`     | `intent`         | no                   | `""`    | Context validate, compose, preflight |
| `context`         | —                | no                   | `{}`    | Must be object if present; stage 6   |
| `conversation_id` | `conversationId` | conversational only  | —       | Journal, conversational validate     |
| `turn_ordinal`    | `turnOrdinal`    | conversational only  | —       | Must be finite number                |
| `transcript`      | —                | conversational only  | —       | Conversational history               |




### 4.1 `capability_id`


| Aspect        | Detail                                                                                                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Aliases       | `capability` (legacy / alternate wire name)                                                                                                                                                       |
| Type          | Non-empty string                                                                                                                                                                                  |
| Meaning       | **Which AI feature** to run — stable id from the capability manifest registry (e.g. `clinic.visit_summary`)                                                                                       |
| Required when | Before pre-accept: missing or non-string → `internal_error` (HTTP 500 JSON, no SSE)                                                                                                               |
| Consumers     | Guard stage 3 (entitlement allow-list), stage 4 (rate limit dimension `installation+capability`), stage 5 (manifest resolve), stage 6+ (context rules, routing, compose), journal `capability_id` |
| Pairing       | Must match `Identity.capabilityId` inside the manifest selected by `capability_id` + `x-capability-version`                                                                                       |




### 4.2 `user_intent`


| Aspect         | Detail                                                                                                                                                            |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Aliases        | `intent`                                                                                                                                                          |
| Type           | String (optional)                                                                                                                                                 |
| Default        | `""` when omitted or wrong type                                                                                                                                   |
| Meaning        | **Natural-language instruction** from the staff member — what they want the model to do with the supplied context (e.g. "Summarize today's visit for the chart.") |
| Guard stage 6  | Included in context validation inputs where the manifest expects intent-shaped content                                                                            |
| Guard stage 7  | Serialized with `filteredContext` (and conversational `transcript` when present) for token/cost pre-flight estimation                                             |
| Guard stage 10 | Woven into `CanonicalRequest.parts[]` by the prompt composer as the last `user` part, after `neutralizeText` (`</` → `\u003c/`) — the same delimiter-injection hygiene applied to context blocks and transcript turns |
| Note           | Not a substitute for structured `context` keys — manifests still require their declared context fields                                                            |




### 4.3 `context`


| Aspect                | Detail                                                                                                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Type                  | Plain object (optional); wrong type (array, string, …) → guard `context_invalid`                                                                                   |
| Default               | `{}` when omitted                                                                                                                                                  |
| Meaning               | **Structured clinic facts** the capability needs — chief complaint, vitals, chart snippets, etc. Keys use the manifest vocabulary (`domain.field@vN`)              |
| Tenant binding        | `context.org` must equal AAT `organizationId`; `context.branch` must equal AAT `branchId` — mismatch → `context_invalid`                                           |
| Guard stage 6         | Manifest `Context requirements` define required keys, permitted keys, shapes, and `maxSize` per key; output is `filteredContext` containing only allow-listed keys |
| Visit summary example | `visit.chief_complaint@v1` — required string, max 4096 bytes (see [§7 Visit summary example body](#7-visit-summary-example-body))                                  |
| Not in context        | Patient identifiers, routing hints, quota state — those come from auth, admission, or server-side policy                                                           |




### 4.4 `conversation_id`


| Aspect        | Detail                                                                                                                              |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Aliases       | `conversationId`                                                                                                                    |
| Type          | String                                                                                                                              |
| Required when | Capabilities with `Interaction.interactionMode = conversational` — omitted on single-shot capabilities                              |
| Meaning       | **Stable thread id** for a multi-turn dialogue — groups turns in the journal and lets the platform enforce per-conversation budgets |
| Journal       | Written to `ai_request.conversation_id` on fresh admission (NULL for single-shot)                                                   |
| Validation    | Conversational validator ties this id to `turn_ordinal` and `transcript` continuity                                                 |




### 4.5 `turn_ordinal`


| Aspect          | Detail                                                                                                                        |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Aliases         | `turnOrdinal`                                                                                                                 |
| Type            | Finite number (integer ordinals in practice)                                                                                  |
| Required when   | Conversational mode — must align with the leg being submitted                                                                 |
| Meaning         | **Which turn** this request represents in the conversation — monotonic counter the client increments each user/model exchange |
| Validation      | Non-finite or missing (when conversational) → `context_invalid` or `conversation_budget_exhausted`                            |
| Transcript link | Each `transcript[]` entry carries its own `turn_ordinal`; the wire field names the active leg                                 |




### 4.6 `transcript`


| Aspect         | Detail                                                                                                                       |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Type           | Array of turn objects (conversational only)                                                                                  |
| Meaning        | **Prior dialogue history** for the thread — user/model turns and optional context-request/resolution legs                    |
| Turn shapes    | `{ turn_ordinal, kind: "user" | "model", text }` or context handshake kinds `context_requested` / `context_resolved`         |
| Guard stage 6  | Validated against conversational budgets and permitted keys; out-of-set keys are dropped from `context_resolved` payloads **and** historical `context_requested` `requests` (matching the supplied-context allowlist). Failures → `conversation_budget_exhausted` or `context_invalid` |
| Guard stage 7  | Included in cost pre-flight so growing transcripts are priced before admission completes                                     |
| Guard stage 10 | Feeds prompt compose for multi-turn capabilities                                                                             |
| Single-shot    | Ignored — visit summary and similar capabilities do not read this field                                                      |




### 4.7 Ignored body keys

These keys are **never read** from the request body. Ingress ignores them structurally: `ADAPTER_ROUTING_BODY_FIELDS = []` in `src/adapter.ts`, so `parseAdapterRequestBody` does not consult them (they may still appear on the parsed JSON object). There is no production request-path helper that scans the body for injection keys — `bodyHasClientRoutingInjection` lives only in `test/soft-threshold-routing.test.ts`. Clients must not rely on these keys; the gateway sets routing/degraded state from Quota DO admission (`routingTierFromAdmission` / `degradedNoticeFromAdmission`).


| Key               | Why ignored                                                                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `routing_tier`    | Set server-side from admission outcome (`standard` vs `degraded`) — see [Stage 9 — Admission](11-stage-9-the-guard.md#11-stage-8-admission-quota-do) |
| `degraded`        | Internal admission flag; not client-supplied                                                                                                         |
| `degraded_notice` | Emitted on SSE `accepted` when tier is degraded — not accepted from body                                                                             |




## 5. Ingress validation (before guard)


| Check            | Limit               | Failure                      |
| ---------------- | ------------------- | ---------------------------- |
| Body bytes       | ≤ 1_048_576 (1 MiB) | HTTP 413 `request_too_large` |
| JSON parse       | plain object        | HTTP 422 empty body          |
| Required headers | see above           | HTTP 422                     |




## 6. Pre-accept (`createProductionPreAccept`)

1. Generate `request_reference` — format `XXXX-XXXX` (Crockford base32).
2. Extract `capability_id` — missing → `internal_error` (no SSE).
3. Run full guard ([The guard — Stage 9](11-stage-9-the-guard.md#1-plain-language)) against the
   isolate-scoped `ConfigCache` (one instance per Worker isolate, 30 s TTL) shared with
   `GET /v1/requests/{ref}` and invoke-path routing.
4. Store `AcceptContext` in request-scoped map for event source.



## 7. Visit summary example body

```json
{
  "capability_id": "clinic.visit_summary",
  "user_intent": "Summarize today's visit for the chart.",
  "context": {
    "org": "<must match AAT org>",
    "branch": "<must match AAT branch>",
    "visit.chief_complaint@v1": "Patient reports headache for 3 days."
  }
}
```

**Manifest context requirement:**


| key                        | required | maxSize    |
| -------------------------- | -------- | ---------- |
| `visit.chief_complaint@v1` | true     | 4096 bytes |


## 8. Behavioral verification

Live probes against a local Worker (`POST /v1/requests`). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§8.3](#83-ordered-probes) top to bottom**. If every probe matches, this stage is working.

This stage is **ingress + pre-accept**. Adapter size/JSON/header failures never call the guard. Missing `capability_id` fails inside `createProductionPreAccept` before `runGuard`. A well-formed body with the two required adapter headers reaches pre-accept, which runs the full guard ([Stage 9](11-stage-9-the-guard.md#1-plain-language)). Do **not** treat later guard codes (`rate_limited`, `quota_exhausted`, kill switches, compose) as this stage — only the failures [§3](#3-required-headers-every-field)–[§6](#6-pre-accept-createproductionpreaccept) name.

### 8.1 Setup

- Local Worker: `cd ai-platform && npm run dev` → `http://127.0.0.1:8787` ([runbook §3.1](../04-ai-platform-operator-runbook.md#31-ai-gateway-wrangler)).
- [§8.3.1](#831-worker-up-and-curl-skeleton)–[§8.3.9](#839-optional-and-conversational-body-fields) need **only** the Worker. No AAT, no enroll.
- From [§8.3.10](#8310-mint-an-aat-and-visit-summary-through-ingress): clinic Supabase with a Stage 2 keypair, that installation enrolled on this Worker (Stage 3), staff who can `issue_ai_token` (Stage 6). `OPERATOR_BEARER_TOKEN` for the one-shot entitle in that subsection and for the operator-is-not-a-caller probes.
- Prefer a throwaway local D1. [§8.3.12](#8312-what-this-stage-does-not-do) suspends the installation.

Export once:

```bash
export GATEWAY='http://127.0.0.1:8787'
export CAP_VER='1.0.0'
```

Use a **new** `x-idempotency-key` on every POST (UUID or `probe-stage8-<n>`). Save SSE or JSON bodies you will compare.

How to tell the three failure classes apart:

| Class | HTTP | Body | `request_reference` | Stream |
| ----- | ---- | ---- | ------------------- | ------ |
| Size | 413 | taxonomy JSON `request_too_large` | `""` | no |
| JSON / required headers | 422 | empty, `content-type: text/plain` | none (no JSON) | no |
| Pre-accept (including guard) | taxonomy status | taxonomy JSON | Crockford `XXXX-XXXX` | no |

### 8.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Body bytes **>** 1_048_576 → HTTP 413 `request_too_large`; empty `request_reference` / `trace_id`; no SSE | [§8.3.2](#832-oversized-body) |
| `Content-Length` numeric and **>** 1 MiB rejects **without** reading the body | [§8.3.2](#832-oversized-body) |
| Absent `Content-Length`: stream-read aborts at the first chunk that would exceed 1 MiB | [§8.3.2](#832-oversized-body) |
| Cap is **bytes** (UTF-8), not character count | [§8.3.2](#832-oversized-body) |
| Oversize wins over missing headers (413, not 422) | [§8.3.2](#832-oversized-body) |
| Empty body, malformed JSON, array, `null`, scalar → HTTP 422 empty body; never reaches the guard | [§8.3.3](#833-json-parse-never-reaches-the-guard) |
| JSON must be a **plain object** | [§8.3.3](#833-json-parse-never-reaches-the-guard) |
| Omit or whitespace-only `x-idempotency-key` → HTTP 422 (adapter, before guard) | [§8.3.4](#834-required-headers-omitted-or-empty) |
| Omit or whitespace-only `x-capability-version` → HTTP 422 | [§8.3.4](#834-required-headers-omitted-or-empty) |
| `x-trace-id` present but empty after trim → HTTP 422 | [§8.3.4](#834-required-headers-omitted-or-empty) |
| Non-empty after trim is enough for the two required headers (spaces around a value are not 422) | [§8.3.4](#834-required-headers-omitted-or-empty) |
| Omit `x-trace-id` → server ULID on the pre-accept error body | [§8.3.5](#835-optional-x-trace-id-and-content-length) |
| Any non-empty `x-trace-id` (including non-ULID) is echoed on HTTP error bodies | [§8.3.5](#835-optional-x-trace-id-and-content-length) |
| Absent `Content-Length` with a small body is not 413 | [§8.3.5](#835-optional-x-trace-id-and-content-length) |
| Adapter does **not** reject a missing `Authorization`; the guard does (`401 unauthenticated`, JSON, no SSE) | [§8.3.6](#836-who-may-call) |
| `anon` / no Bearer is not a caller of this route | [§8.3.6](#836-who-may-call) |
| Operator bearer is `/control/*` only — junk on `/v1/requests` | [§8.3.6](#836-who-may-call) |
| Wrong `Authorization` values (`Basic`, empty Bearer, non-JWS) → `401 unauthenticated` | [§8.3.6](#836-who-may-call) |
| Intended caller is clinic staff with an AAT | [§8.3.10](#8310-mint-an-aat-and-visit-summary-through-ingress) |
| Missing / non-string `capability_id` → `internal_error` HTTP 500 JSON, no SSE (pre-accept; guard is not run) | [§8.3.7](#837-pre-accept-capability_id-and-request_reference) |
| Alias `capability` is read when `capability_id` is absent | [§8.3.7](#837-pre-accept-capability_id-and-request_reference) |
| Pre-accept mints `request_reference` `XXXX-XXXX` (Crockford base32) | [§8.3.7](#837-pre-accept-capability_id-and-request_reference) |
| `ADAPTER_ROUTING_BODY_FIELDS = []` — `routing_tier` / `degraded` / `degraded_notice` are not read from the body | [§8.3.8](#838-ignored-routing-body-keys), [§8.3.10](#8310-mint-an-aat-and-visit-summary-through-ingress) |
| `user_intent` / `intent` optional; omitted or wrong type is not an ingress 422 (default `""`) | [§8.3.9](#839-optional-and-conversational-body-fields) |
| `context` omitted is not an ingress 422 (default `{}`) | [§8.3.9](#839-optional-and-conversational-body-fields) |
| `conversation_id` / `turn_ordinal` / `transcript` ignored on single-shot visit summary | [§8.3.9](#839-optional-and-conversational-body-fields) |
| [§7](#7-visit-summary-example-body) body through ingress: not 413/422; first guard taxonomy **or** SSE `accepted` | [§8.3.10](#8310-mint-an-aat-and-visit-summary-through-ingress) |
| SSE `accepted` carries Crockford `request_reference` and echoed `trace_id`; `degraded_notice` is not taken from the body | [§8.3.10](#8310-mint-an-aat-and-visit-summary-through-ingress) |
| Wrong non-empty `x-capability-version` / unknown `capability_id` pass ingress → `404 capability_unknown` | [§8.3.11](#8311-listed-wrong-values-after-ingress) |
| `context.org` / `context.branch` must match AAT `org` / `branch` → `context_invalid` | [§8.3.11](#8311-listed-wrong-values-after-ingress) |
| `visit.chief_complaint@v1` required, max 4096 bytes | [§8.3.11](#8311-listed-wrong-values-after-ingress) |
| Non-object `context` is not ingress 422; extractors fall back to `{}` | [§8.3.11](#8311-listed-wrong-values-after-ingress) |
| Invalid JSON never reaches the guard (would have been 500 with a reference) | [§8.3.3](#833-json-parse-never-reaches-the-guard), [§8.3.12](#8312-what-this-stage-does-not-do) |
| `installation_suspended` (the other `Authorization` failure this file names) | [§8.3.12](#8312-what-this-stage-does-not-do) |
| This stage does not entitle, mint AATs, or run the invoke stream past `accepted` | [§8.3.12](#8312-what-this-stage-does-not-do) |


Unprobeable from this HTTP surface (no live probe): isolate `ConfigCache` 30 s TTL; request-scoped `AcceptContext` map; Principal object on success (not serialized on `accepted`); `neutralizeText` on `user_intent`; idempotent replay skipping journal INSERT (Quota DO / Stage 9); `capability_retired` (needs a control-plane retire); conversational *required-when* rules (this file’s example is single-shot); guard stage-1 size re-check as a **second** 413 on the same oversize request (the adapter never forwards that body).

### 8.3 Ordered probes

#### 8.3.1 Worker up and curl skeleton

**Do:**

```bash
curl -sS "$GATEWAY/health"
```

**Expect:** JSON with `environment` (typically `"development"`). The same origin serves `POST /v1/requests`.

Skeleton used below (headers vary per probe):

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-skel" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

#### 8.3.2 Oversized body

**Do:** declare `Content-Length` one byte over the cap with a **small** JSON body:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-cl" \
  -H "x-capability-version: $CAP_VER" \
  -H "Content-Length: 1048577" \
  -d '{"capability_id":"clinic.visit_summary"}'
cat /tmp/stage8-body; echo
```

**Expect:** HTTP 413, `content-type` JSON (not `text/event-stream`). Body `code` is `request_too_large`, `request_reference` is `""`, `trace_id` is `""`. The adapter rejected the header before reading (or finishing) the payload.

**Do:** omit `Content-Length` by piping a 1 MiB + 1 byte body (curl uses chunked transfer on a pipe):

```bash
python3 -c 'import sys; sys.stdout.buffer.write(b"x"*(1048576+1))' | \
  curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: probe-stage8-size" \
    -H "x-capability-version: $CAP_VER" \
    --data-binary @-
cat /tmp/stage8-body; echo
```

**Expect:** HTTP 413, same empty-reference `request_too_large` body. Stream-read aborted at the cap.

**Do:** same oversize pipe, omit the required headers:

```bash
python3 -c 'import sys; sys.stdout.buffer.write(b"x"*(1048576+1))' | \
  curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
    -H "Content-Type: application/json" \
    --data-binary @-
cat /tmp/stage8-body; echo
```

**Expect:** still HTTP 413, not 422. Size runs first ([§5](#5-ingress-validation-before-guard)).

**Do:** UTF-8 body whose **byte** length exceeds 1 MiB while the character count does not (Arabic `م` is two UTF-8 bytes):

```bash
python3 - <<'PY' | curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-utf8" \
  -H "x-capability-version: 1.0.0" \
  --data-binary @-
import sys
ch = "م"
# enough characters that UTF-8 bytes > 1_048_576
n = 1048576 // 2 + 1
sys.stdout.buffer.write(ch.encode("utf-8") * n)
PY
```

**Expect:** HTTP 413. The gate is byte length.

#### 8.3.3 JSON parse never reaches the guard

Use valid required headers on every call in this subsection so a 422 is the parse, not a missing header.

**Do:** empty body:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-empty" \
  -H "x-capability-version: $CAP_VER"
cat /tmp/stage8-body; echo
```

**Do:** malformed JSON:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-malformed" \
  -H "x-capability-version: $CAP_VER" \
  -d 'not json'
```

**Do:** array:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-array" \
  -H "x-capability-version: $CAP_VER" \
  -d '[1,2,3]'
```

**Do:** `null`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-null" \
  -H "x-capability-version: $CAP_VER" \
  -d 'null'
```

**Do:** JSON string scalar:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-scalar" \
  -H "x-capability-version: $CAP_VER" \
  -d '"hello"'
```

**Expect (all):** HTTP 422, `content-type: text/plain`, **empty** body. Not taxonomy JSON. Not SSE. No `request_reference` was minted (`generateRequestReference` runs only after parse + headers succeed).

If these had reached the guard, stage 1 would have returned HTTP 500 `internal_error` **with** a Crockford `request_reference`. That is the proof invalid JSON never enters [Stage 9](11-stage-9-the-guard.md#4-stage-1-ingress-size-json).

#### 8.3.4 Required headers omitted or empty

Valid JSON object on every call in this subsection.

**Do:** omit `x-idempotency-key`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Do:** whitespace-only `x-idempotency-key`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key:    " \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Do:** omit `x-capability-version`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-no-cver" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Do:** whitespace-only `x-capability-version`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-cver-ws" \
  -H $'x-capability-version:\t' \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Do:** present-but-empty `x-trace-id`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-empty-trace" \
  -H "x-capability-version: $CAP_VER" \
  -H "x-trace-id:    " \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Expect (all):** HTTP 422, empty `text/plain` body, no SSE. Adapter, before pre-accept.

**Do:** surrounding whitespace on **valid** values:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key:  probe-stage8-trim  " \
  -H "x-capability-version:  1.0.0  " \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Expect:** **not** 422. Trim leaves non-empty strings, so pre-accept runs (typically `401 unauthenticated` JSON with a Crockford `request_reference` — no AAT yet).

#### 8.3.5 Optional x-trace-id and Content-Length

**Do:** omit `x-trace-id` and send a body that fails pre-accept (`{}` has no `capability_id`):

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-notrace" \
  -H "x-capability-version: $CAP_VER" \
  -d '{}'
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** HTTP 500 `internal_error` ([§8.3.7](#837-pre-accept-capability_id-and-request_reference)). `trace_id` is a 26-character Crockford ULID (`[0-7][0-9A-HJKMNP-TV-Z]{25}`). Server assigned it via `resolveTraceId`.

**Do:** non-ULID trace id:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-uuid-trace" \
  -H "x-capability-version: $CAP_VER" \
  -H "x-trace-id: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{}'
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** HTTP 500 `internal_error` with that **exact** `trace_id` on the JSON body (non-ULID is allowed).

**Do:** client ULID:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-ulid-trace" \
  -H "x-capability-version: $CAP_VER" \
  -H "x-trace-id: 01ARZ3NDEKTSV4RRFFQ69G5FAV" \
  -d '{}'
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** that ULID echoed as `trace_id`.

**Do:** small JSON on a pipe so curl omits `Content-Length`:

```bash
printf '%s' '{"capability_id":"clinic.visit_summary"}' | \
  curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: probe-stage8-chunked" \
    -H "x-capability-version: $CAP_VER" \
    --data-binary @-
```

**Expect:** not 413. Pre-accept runs (`401` without an AAT).

#### 8.3.6 Who may call

Production clients send `Authorization: Bearer <AAT>`. The adapter does not check it. `createProductionPreAccept` passes the Bearer token into guard stage 2.

**Do:** well-formed ingress, **no** `Authorization`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-anon" \
  -H "x-capability-version: $CAP_VER" \
  -H "x-trace-id: probe-anon-trace" \
  -d '{"capability_id":"clinic.visit_summary"}'
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** **not** 422. HTTP 401, `code` `unauthenticated`, `trace_id` `probe-anon-trace`, Crockford `request_reference`, `content-type` JSON, no SSE. `anon` is not a caller; identity is the guard, after ingress.

**Do:** non-JWS Bearer:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer not-a-jws" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-junk" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Do:** `Basic` instead of `Bearer`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Basic Zm9vOmJhcg==" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-basic" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Do:** `Bearer` with no token:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-empty-bearer" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Do:** operator secret on this route (not `/control/*`):

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-op" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Expect (all):** HTTP 401 `unauthenticated`, taxonomy JSON, no SSE. Wrong values and the operator bearer are not AATs. A valid AAT is [§8.3.10](#8310-mint-an-aat-and-visit-summary-through-ingress). `installation_suspended` is [§8.3.12](#8312-what-this-stage-does-not-do) (needs a control-plane suspend).

#### 8.3.7 Pre-accept capability_id and request_reference

**Do:**

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-nocap" \
  -H "x-capability-version: $CAP_VER" \
  -d '{}'
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** HTTP 500, `code` `internal_error`, JSON (not SSE). `request_reference` matches `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` (Crockford; no `I`, `L`, `O`, `U`). Pre-accept minted the reference, then `extractCapabilityId` failed — `runGuard` is not called.

**Do:** non-string `capability_id`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-cap-num" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":1}'
```

**Do:** empty-string `capability_id`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-cap-empty" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":""}'
```

**Expect:** same HTTP 500 `internal_error` JSON, no SSE.

**Do:** alias only:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-alias" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability":"clinic.visit_summary"}'
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** **not** 500 `internal_error`. Extract succeeded, so the guard runs — HTTP 401 `unauthenticated` (no AAT) with a Crockford `request_reference`.

#### 8.3.8 Ignored routing body keys

`ADAPTER_ROUTING_BODY_FIELDS` is empty. Ingress does not consult `routing_tier`, `degraded`, or `degraded_notice`. They may still appear on the parsed object; nothing on the production request path uses them.

**Do:**

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-route" \
  -H "x-capability-version: $CAP_VER" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "routing_tier": "degraded",
    "degraded": true,
    "degraded_notice": true
  }'
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** same as the [§8.3.6](#836-who-may-call) anon POST: HTTP 401 `unauthenticated`, not 422, not a client-selected degraded tier. Compare [§8.3.10](#8310-mint-an-aat-and-visit-summary-through-ingress) when `accepted` is on the wire: `degraded_notice` is absent unless admission actually degraded.

#### 8.3.9 Optional and conversational body fields

**Do:** omit `user_intent`, `context`, `conversation_id`, `turn_ordinal`, `transcript`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-omitbody" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Expect:** not 422. Pre-accept runs (401 without an AAT). Those fields are not ingress-required.

**Do:** wrong-type `user_intent` (number):

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-intent-num" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary","user_intent":123,"intent":"ignored-because-user_intent-wrong-type"}'
```

**Expect:** not 422. Wrong-type `user_intent` defaults to `""` at extract; ingress does not reject it.

**Do:** alias `intent` only:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-intent-alias" \
  -H "x-capability-version: $CAP_VER" \
  -d '{"capability_id":"clinic.visit_summary","intent":"Summarize today."}'
```

**Expect:** not 422 (same 401 without an AAT).

**Do:** conversational keys on this **single-shot** capability:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-conv" \
  -H "x-capability-version: $CAP_VER" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "conversation_id": "thread-should-be-ignored",
    "turn_ordinal": 99,
    "transcript": [{"turn_ordinal": 1, "kind": "user", "text": "hi"}]
  }'
```

**Expect:** same class of outcome as without those keys (401 without an AAT; later, if entitled, still not `conversation_budget_exhausted`). Visit summary does not read them ([§4.6](#46-transcript)).

#### 8.3.10 Mint an AAT and visit summary through ingress

**Do:** as clinic staff with `ai.*`:

```sql
SELECT public.issue_ai_token();
```

**Expect:** a compact JWS. Export it and decode `org` / `branch` / `iss`:

```bash
export AAT='<paste JWS>'
python3 - <<'PY'
import json, base64, os
tok = os.environ["AAT"]
p = tok.split(".")[1]
p += "=" * ((4 - len(p) % 4) % 4)
c = json.loads(base64.urlsafe_b64decode(p))
print("iss", c["iss"])
print("org", c["org"])
print("branch", c["branch"])
PY
export ORG='<org>'
export BRANCH='<branch>'
export INSTALLATION_ID='<iss>'
```

This stage does not mint tokens; Stage 6 did. You need the claims so [§7](#7-visit-summary-example-body) `context.org` / `context.branch` match.

**Do:** [§7](#7-visit-summary-example-body) body through ingress (stop at `accepted` — use `--max-time` so curl does not wait for the provider):

```bash
curl -sS -N --max-time 8 -D /tmp/stage8-hdr -o /tmp/stage8-body \
  -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-visit-1" \
  -H "x-capability-version: $CAP_VER" \
  -H "x-trace-id: probe-visit-trace" \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"$ORG\",
      \"branch\": \"$BRANCH\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
head -n 20 /tmp/stage8-hdr
head -c 2000 /tmp/stage8-body; echo
```

**Expect:** **not** HTTP 413 and **not** HTTP 422. Ingress passed. Then either:

- **First guard success on the wire:** HTTP 200, `content-type: text/event-stream`. First event is `event: accepted` with Crockford `request_reference`, `trace_id` `probe-visit-trace`, and **no** `degraded_notice` (fresh entitle is not degraded). Pre-accept stored `AcceptContext` and the adapter opened the stream. Stop here — later SSE events are Stage 10.
- **First guard taxonomy this file still allows you to see:** HTTP JSON with a Crockford `request_reference` and the same `trace_id`. Typical when Stage 4 has not run: `403 forbidden_capability` (`ai_disabled` while entitlement is `pending`). Identity already ran (this is not `unauthenticated`). That is enough to prove [§7](#7-visit-summary-example-body) cleared ingress and pre-accept started the guard.

If you got `forbidden_capability` and want `accepted`, entitle once ([Stage 4 example payload](06-stage-4-entitlement-and-capability-grants.md#6-example-entitle-payload-visit-summary)) — operator-only, **not** this route:

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "period_start": "2026-08-01T00:00:00.000Z",
    "period_end": "2026-09-01T00:00:00.000Z",
    "request_quota": 1000,
    "token_budget": 500000,
    "cost_budget": 50.0,
    "soft_threshold": 0.8,
    "allowed_capabilities": ["clinic.visit_summary"],
    "grants": [
      {
        "capability_id": "clinic.visit_summary",
        "capability_version": "1.0.0",
        "scope": "installation"
      }
    ]
  }'
```

Then repeat the visit-summary POST with a **new** idempotency key. **Expect:** `accepted` as above. This stage did not grant quotas; Stage 4 did.

**Do:** alias `capability` (no `capability_id`) plus ignored routing keys:

```bash
curl -sS -N --max-time 8 -D /tmp/stage8-hdr -o /tmp/stage8-body \
  -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-visit-alias" \
  -H "x-capability-version: $CAP_VER" \
  -H "x-trace-id: probe-visit-alias" \
  -d "{
    \"capability\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"routing_tier\": \"degraded\",
    \"degraded\": true,
    \"degraded_notice\": true,
    \"context\": {
      \"org\": \"$ORG\",
      \"branch\": \"$BRANCH\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
head -n 20 /tmp/stage8-hdr
head -c 2000 /tmp/stage8-body; echo
```

**Expect:** same class as the canonical [§7](#7-visit-summary-example-body) POST (`accepted` if entitled). Alias works. Body routing keys do not plant `degraded_notice` on `accepted`.

#### 8.3.11 Listed wrong values after ingress

These pass adapter parse + required headers, then fail inside pre-accept / guard. Skip them if the visit-summary POST still returns `unauthenticated` (not enrolled) or stop after identity if you never entitled — org/branch and chief-complaint checks need a resolved visit-summary manifest (entitled).

**Do:** non-empty but unknown version:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-badver" \
  -H "x-capability-version: not-a-published-version" \
  -d "{\"capability_id\":\"clinic.visit_summary\",\"context\":{\"org\":\"$ORG\",\"branch\":\"$BRANCH\",\"visit.chief_complaint@v1\":\"Patient reports headache for 3 days.\"}}"
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** not 422. After identity (and entitlement if active): HTTP 404 `capability_unknown`. Ingress only required non-empty after trim; the registry key is `{capability_id}@{x-capability-version}`.

**Do:** unknown `capability_id` with a published version:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-badcap" \
  -H "x-capability-version: $CAP_VER" \
  -d "{\"capability_id\":\"clinic.not_a_capability\",\"context\":{\"org\":\"$ORG\",\"branch\":\"$BRANCH\",\"visit.chief_complaint@v1\":\"Patient reports headache for 3 days.\"}}"
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** HTTP 404 `capability_unknown` (pairing with a published `Identity.capabilityId` failed). Not an ingress 422.

**Do:** entitled visit-summary POST with a mismatched `org`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-org" \
  -H "x-capability-version: $CAP_VER" \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"context\": {
      \"org\": \"not-the-aat-org\",
      \"branch\": \"$BRANCH\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
    }
  }"
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** HTTP 422 `context_invalid`, taxonomy JSON, no SSE. Tenant binding is guard stage 6 inside pre-accept.

**Do:** omit `visit.chief_complaint@v1`:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-nocc" \
  -H "x-capability-version: $CAP_VER" \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"context\": {
      \"org\": \"$ORG\",
      \"branch\": \"$BRANCH\"
    }
  }"
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** missing required context key after the manifest resolve — HTTP JSON `context_required` (not adapter 422). [§7](#7-visit-summary-example-body) marks that key required.

**Do:** chief complaint whose JSON byte length exceeds 4096 (keep matching `org` / `branch`):

```bash
python3 - <<'PY' | curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-cc-big" \
  -H "x-capability-version: $CAP_VER" \
  --data-binary @-
import json, os
print(json.dumps({
  "capability_id": "clinic.visit_summary",
  "context": {
    "org": os.environ["ORG"],
    "branch": os.environ["BRANCH"],
    "visit.chief_complaint@v1": "x" * 5000,
  },
}))
PY
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** HTTP 422 `context_invalid` (`maxSize` 4096). Not adapter 413 (the whole body is still under 1 MiB).

**Do:** `"context": []` (array) on an otherwise entitled visit-summary POST:

```bash
curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-ctx-arr" \
  -H "x-capability-version: $CAP_VER" \
  -d "{\"capability_id\":\"clinic.visit_summary\",\"context\":[]}"
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** not adapter 422 (the body is still a plain object). Both extractors treat a non-object `context` as `{}`, so the required chief-complaint key is missing → `context_required` once the manifest is resolved — not `context_invalid` from the array type alone.

#### 8.3.12 What this stage does not do

**Do:** discovery is a different route:

```bash
curl -sS -D - -o /tmp/stage8-body \
  -H "Authorization: Bearer $AAT" \
  "$GATEWAY/v1/capabilities"
```

**Expect:** that is Stage 7, not this POST. This stage does not list capabilities.

**Do:** compare a [§8.3.3](#833-json-parse-never-reaches-the-guard) 422 (empty, no reference) with a [§8.3.7](#837-pre-accept-capability_id-and-request_reference) 500 (taxonomy + Crockford reference). **Expect:** only the latter minted `request_reference`. Invalid JSON never reached the guard; missing `capability_id` never reached `runGuard` either.

**Do:** entitle with the staff AAT (not the operator secret):

```bash
curl -sS -D - -o /tmp/stage8-body \
  -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -d '{"period_start":"2026-08-01T00:00:00.000Z","period_end":"2026-09-01T00:00:00.000Z","request_quota":1,"token_budget":1,"cost_budget":1,"soft_threshold":0.8,"allowed_capabilities":["clinic.visit_summary"],"grants":[]}'
```

**Expect:** control-plane `401 unauthorized` (operator secret). Staff AATs do not entitle. This stage does not grant quotas.

**Do:** after an `accepted` visit-summary POST, leave curl connected without `--max-time`. **Expect:** further SSE (`heartbeat`, `text_delta`, terminal) is Stage 10. This stage’s happy path stops at pre-accept success / `accepted`.

**Do:** suspend, then invoke (mutates the throwaway installation — run last):

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/suspend" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

curl -sS -D - -o /tmp/stage8-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-stage8-susp" \
  -H "x-capability-version: $CAP_VER" \
  -d "{\"capability_id\":\"clinic.visit_summary\",\"context\":{\"org\":\"$ORG\",\"branch\":\"$BRANCH\",\"visit.chief_complaint@v1\":\"Patient reports headache for 3 days.\"}}"
python3 -m json.tool < /tmp/stage8-body
```

**Expect:** HTTP 403 `installation_suspended`, taxonomy JSON, no SSE. The other `Authorization` failure [§3.1](#31-authorization) names. Resume via Stage 3 if you still need this installation.

This stage also does **not**: mint AATs (Stage 6); register the installation (Stage 3); set routing/degraded state from the body ([§4.7](#47-ignored-body-keys)); dump the rest of the Stage 9 failure matrix.


