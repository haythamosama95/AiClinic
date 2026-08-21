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


