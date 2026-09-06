# Stage 08 — Request ingress (POST /v1/requests adapter gate + context provider RPC)

Source files read: `ai-platform/src/adapter.ts`, `ai-platform/src/worker.ts`, `ai-platform/src/context/context-request.ts`, `ai-platform/src/errors.ts`, `ai-platform/src/reference.ts`, `ai-platform/src/trace.ts`, `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql`, `docs/architecture/ai-platform/data-journey/10-stage-8-request-ingress.md` (orientation only).

Shared realistic values used throughout this chapter:

- Worker base URL: `http://127.0.0.1:8787` (vitest-pool-workers `SELF.fetch`).
- Published capability: `clinic.visit_summary` @ `1.0.0` (registry loaded from `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`).
- Installation ID (AAT `iss`): `7f3a9c1e-2b4d-4e6a-9c8f-0d1e2f3a4b5c`. Org: `c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f`. Branch: `b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e`.
- Visit ID (clinic Postgres): `5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b`.
- Example Crockford request references: `7K2Q-9MZX`, `T4W8-HJ3N`, `2F6K-8QRM` (format `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`; never contains `I`, `L`, `O`, `U`).
- Example client ULID trace id: `01ARZ3NDEKTSV4RRFFQ69G5FAV`.
- "Enrolled + entitled installation" below means: Stage 3 enrollment done, Stage 4 entitle applied with `allowed_capabilities: ["clinic.visit_summary"]`, grant `{capability_id: "clinic.visit_summary", capability_version: "1.0.0", scope: "installation"}`, period `2026-09-01T00:00:00.000Z`–`2026-10-01T00:00:00.000Z`, and a real AAT minted via Stage 6 `issue_ai_token()` with `ai.visit_summary` scope. Guard internals for every scenario that reaches preAccept are Stage 9 behavior; this chapter asserts only what Stage 8 puts on the wire.

---

## 1. Ingress contract (`handleAdapterRequest`)

Gate order: body size → JSON parse (plain object) → required headers → optional
`preAccept` → SSE stream. Everything below is enforced in `adapter.ts`; body-field
extraction for routing/compose runs later in the worker `preAccept` path.

### 1.1 Required headers

`parseRequiredHeaders` (`adapter.ts:L258-L284`) validates **non-empty-after-trim only**:

| Header | Required | Rule |
| ------ | -------- | ---- |
| `x-idempotency-key` | yes | Trim; reject if empty |
| `x-capability-version` | yes | Trim; reject if empty |
| `x-trace-id` | no | If present, trim; reject if empty after trim; otherwise server ULID |

There is **no** length cap, charset restriction, or semver/format validation at ingress
(S08-024, S08-025). Trimmed values are what reach preAccept and the guard.

### 1.2 Body parsing

- **No `Content-Type` check** — the adapter never branches on `Content-Type`; any
  content type whose bytes parse as JSON is accepted (S08-016).
- Body must be a JSON **plain object** (not array, not scalar); empty body fails parse →
  HTTP 422 bare `text/plain` (S08-010).
- Oversize bodies are rejected at `INGRESS_BODY_SIZE_LIMIT` (1 048 576 bytes) before parse
  or header validation (S08-003…S08-008).

### 1.3 `user_intent` / `intent` (preAccept extraction, not an ingress gate)

Neither field is required at ingress; wrong types are never adapter 422s. After ingress,
`extractUserIntent` (`worker.ts:L269-L277`) applies:

1. If `user_intent` is a string → use it.
2. Else if `intent` is a string → use it (alias).
3. Else → `""`.

When `user_intent` is present but **non-string** (e.g. a number), extraction **falls
through to the `intent` alias** — it does not default to `""` while ignoring `intent`
(S08-054 case c). This corrects orientation doc probe §8.3.9.

---

## Scenario S08-001 — Wrong HTTP method never reaches the adapter

| Field | Content |
|-------|---------|
| ID | S08-001 |
| Journey setup | None. Worker running with real D1 migrations applied. |
| Action | `GET /v1/requests` with headers `x-idempotency-key: 9b8f0e1d-2c3a-4b5c-8d6e-7f8a9b0c1d2e`, `x-capability-version: 1.0.0`. Also repeat with `PUT` and `DELETE`. |
| Expected outcome | HTTP 404, body `Not Found` (plain text). The worker route table (`worker.ts:1349` exact-match `pathname === "/v1/requests" && method === "POST"`) never invokes `handleAdapterRequest`; no size/parse/header gate runs. |
| Side effects | None — no D1/DO/R2 reads or writes; no request reference minted. |
| Code reference | `ai-platform/src/worker.ts:L1325-L1352` — default export `fetch` route dispatch (incl. the `/v1/requests` POST guard at L1349) |

## Scenario S08-002 — Trailing-slash path is not the ingress route

| Field | Content |
|-------|---------|
| ID | S08-002 |
| Journey setup | None. |
| Action | `POST /v1/requests/` (trailing slash) with a valid JSON body `{"capability_id":"clinic.visit_summary"}` and both required headers. |
| Expected outcome | HTTP 404 `Not Found`. The exact pathname match fails; the path is not a control route and the `GET /v1/requests/{ref}` branch requires method GET. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1349-L1352` — route dispatch; `ai-platform/src/worker.ts:L1440-L1445` — `route_not_found` |

## Scenario S08-003 — Declared Content-Length one byte over the 1 MiB cap rejects before reading the body

| Field | Content |
|-------|---------|
| ID | S08-003 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `Content-Length: 1048577` header but a small actual body `{"capability_id":"clinic.visit_summary"}`, plus valid `x-idempotency-key: 3d4e5f6a-7b8c-4d9e-0f1a-2b3c4d5e6f7a` and `x-capability-version: 1.0.0`. |
| Expected outcome | HTTP 413, `content-type: application/json`, body exactly `{"code":"request_too_large","request_reference":"","trace_id":"","retry_safe":false}`. Reference and trace are empty strings by design (FR-006 exception — the size gate runs before header parse and reference minting). No SSE. |
| Side effects | None — body never read to completion, no reference minted, no D1/DO/R2 write. |
| Code reference | `ai-platform/src/adapter.ts:L318-L326` — `readBodyWithinLimit` Content-Length pre-check; `ai-platform/src/adapter.ts:L191-L203` — `ingressTooLargeResponse` |

## Scenario S08-004 — Streamed body over 1 MiB without Content-Length aborts at the cap

| Field | Content |
|-------|---------|
| ID | S08-004 |
| Journey setup | None. |
| Action | `POST /v1/requests` with a chunked body of 1,048,577 bytes (`x` repeated), no `Content-Length` header, valid required headers. |
| Expected outcome | HTTP 413 with the same empty-reference `request_too_large` taxonomy body as S08-003. The stream reader aborts at the first chunk that would push `totalBytes` past 1,048,576 and cancels the reader. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L332-L358` — `readBodyWithinLimit` stream-read abort |

## Scenario S08-005 — Under-declared Content-Length does not smuggle an oversize body

| Field | Content |
|-------|---------|
| ID | S08-005 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `Content-Length: 1024` but an actual streamed body of 1,048,577 bytes, valid required headers. |
| Expected outcome | HTTP 413 `request_too_large` (empty reference/trace). The declared-length pre-check passes (1024 ≤ cap), but the byte-accurate stream gate backstops the lying header. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L318-L358` — `readBodyWithinLimit` both gates |

## Scenario S08-006 — Body of exactly 1,048,576 bytes is admitted (at-cap boundary)

| Field | Content |
|-------|---------|
| ID | S08-006 |
| Journey setup | None. |
| Action | `POST /v1/requests` with a body of exactly 1,048,576 bytes: a JSON object `{"capability_id":"clinic.visit_summary","pad":"<…>"}` where `pad` is sized so total UTF-8 bytes equal exactly 1,048,576; valid required headers; no `Authorization`. |
| Expected outcome | Not 413 — the gate is strictly `> INGRESS_BODY_SIZE_LIMIT`. The request proceeds to parse + headers + preAccept and fails identity: HTTP 401 `{"code":"unauthenticated","request_reference":"<Crockford XXXX-XXXX>","trace_id":"<server ULID>","retry_safe":true}`. |
| Side effects | No D1/DO writes (identity fails before admission — Stage 9 stage-2 behavior). A request reference is minted but never journaled. |
| Code reference | `ai-platform/src/adapter.ts:L323` — strict `>` comparison; `ai-platform/src/adapter.ts:L344-L347` — stream abort condition |

## Scenario S08-007 — The size gate counts UTF-8 bytes, not characters

| Field | Content |
|-------|---------|
| ID | S08-007 |
| Journey setup | None. |
| Action | `POST /v1/requests` with a body of 524,289 copies of the Arabic character `م` (2 UTF-8 bytes each → 1,048,578 bytes; character count well under 1 MiB), no `Content-Length`, valid required headers. |
| Expected outcome | HTTP 413 `request_too_large`. Byte length, not `string.length`, decides. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L336-L351` — `value.byteLength` accounting |

## Scenario S08-008 — Oversize wins over invalid JSON and missing headers (gate order)

| Field | Content |
|-------|---------|
| ID | S08-008 |
| Journey setup | None. |
| Action | `POST /v1/requests` with a 1,048,577-byte body of `not json`, no `x-idempotency-key`, no `x-capability-version`. |
| Expected outcome | HTTP 413 `request_too_large`, not 422. `readBodyWithinLimit` runs before JSON parse and before `parseRequiredHeaders` (`adapter.ts:379-399`). This is the only observable ordering among the three pre-guard gates (parse-vs-header order is unobservable — both emit the identical bare 422). |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L373-L399` — `handleAdapterRequest` gate sequence |

## Scenario S08-009 — Non-numeric Content-Length is ignored, not rejected

| Field | Content |
|-------|---------|
| ID | S08-009 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `Content-Length: abc`, small valid body `{"capability_id":"clinic.visit_summary"}`, valid required headers, no `Authorization`. |
| Expected outcome | Not 413, not 422. `Number("abc")` is NaN → `Number.isFinite` fails → the pre-check is skipped and the stream gate governs. Request reaches preAccept → HTTP 401 `unauthenticated` taxonomy JSON with a Crockford reference. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L320-L326` — `Number.isFinite(declared)` guard |

## Scenario S08-010 — Empty body is a bare 422, never taxonomy JSON

| Field | Content |
|-------|---------|
| ID | S08-010 |
| Journey setup | None. |
| Action | `POST /v1/requests` with no body at all, valid required headers. |
| Expected outcome | HTTP 422, `content-type: text/plain`, **empty** body (zero bytes). Not taxonomy JSON, no `request_reference` — `generateRequestReference` has not run. This is the adapter-local parse failure, deliberately distinct from the guard's taxonomy 422 codes (`context_required` / `context_invalid`, S08-046/047/048). |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L390-L393` — parse gate; `ai-platform/src/adapter.ts:L205-L211` — `adapterParseFailureResponse` |

## Scenario S08-011 — Malformed JSON is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-011 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `not json`, valid required headers. |
| Expected outcome | HTTP 422, `text/plain`, empty body. `JSON.parse` throws → `parseRequestBody` returns null. Proof the guard never ran: had it run, stage 1 would have produced HTTP 500 `internal_error` **with** a Crockford reference. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L288-L298` — `parseRequestBody` try/catch |

## Scenario S08-012 — JSON array body is a bare 422 (plain-object requirement)

| Field | Content |
|-------|---------|
| ID | S08-012 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `[1,2,3]`, valid required headers. |
| Expected outcome | HTTP 422, `text/plain`, empty body. Parses fine but `isPlainObject` rejects arrays. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L271-L272` — `isPlainObject`; `ai-platform/src/adapter.ts:L294-L297` |

## Scenario S08-013 — JSON `null` body is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-013 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `null`, valid required headers. |
| Expected outcome | HTTP 422, `text/plain`, empty body (`null` is not a plain object). |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L271-L272` — `isPlainObject` null check |

## Scenario S08-014 — JSON string scalar body is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-014 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `"hello"`, valid required headers. |
| Expected outcome | HTTP 422, `text/plain`, empty body. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L294-L297` — `parseRequestBody` |

## Scenario S08-015 — JSON number scalar body is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-015 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `42`, valid required headers. |
| Expected outcome | HTTP 422, `text/plain`, empty body. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L294-L297` — `parseRequestBody` |

## Scenario S08-016 — Content-Type is never checked: `text/plain` with a valid JSON object passes ingress

| Field | Content |
|-------|---------|
| ID | S08-016 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `Content-Type: text/plain`, body `{"capability_id":"clinic.visit_summary"}`, valid required headers, no `Authorization`. |
| Expected outcome | Not 422/415. The adapter contains **no content-type branch** — the body is parsed regardless (§1.2). Request reaches preAccept → HTTP 401 `unauthenticated` taxonomy JSON. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L373-L399` — `handleAdapterRequest` (no content-type gate exists) |

## Scenario S08-017 — Missing `x-idempotency-key` is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-017 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability_id":"clinic.visit_summary"}`, header `x-capability-version: 1.0.0`, no `x-idempotency-key`. |
| Expected outcome | HTTP 422, `text/plain`, empty body. Adapter rejects before preAccept; no reference minted. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L243-L246` — `parseRequiredHeaders` idempotency-key check |

## Scenario S08-018 — Whitespace-only `x-idempotency-key` is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-018 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `x-idempotency-key: "   "` (three spaces), valid body and `x-capability-version: 1.0.0`. |
| Expected outcome | HTTP 422, `text/plain`, empty body. Value is trimmed; empty-after-trim fails. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L243-L246` — `.trim()` then falsy check |

## Scenario S08-019 — Missing `x-capability-version` is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-019 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability_id":"clinic.visit_summary"}`, header `x-idempotency-key: 4e5f6a7b-8c9d-4e0f-1a2b-3c4d5e6f7a8b`, no `x-capability-version`. |
| Expected outcome | HTTP 422, `text/plain`, empty body. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L248-L251` — capability-version check |

## Scenario S08-020 — Whitespace-only `x-capability-version` is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-020 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `x-capability-version: "\t"` (single tab), valid body and idempotency key. |
| Expected outcome | HTTP 422, `text/plain`, empty body. There is **no semver/format validation** at ingress — only non-empty-after-trim (see S08-024 for the accepted-garbage counterpart). |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L248-L251` — capability-version check |

## Scenario S08-021 — Present-but-empty `x-trace-id` is a bare 422

| Field | Content |
|-------|---------|
| ID | S08-021 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `x-trace-id: "   "`, valid body and both required headers. |
| Expected outcome | HTTP 422, `text/plain`, empty body. The header is optional, but if present it must be non-empty after trim. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L253-L256` — supplied-trace-id empty check |

## Scenario S08-022 — Both required headers missing (pairwise) is the same bare 422

| Field | Content |
|-------|---------|
| ID | S08-022 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability_id":"clinic.visit_summary"}`, neither `x-idempotency-key` nor `x-capability-version`; also `x-trace-id: ""` on a repeat call. |
| Expected outcome | HTTP 422, `text/plain`, empty body in both cases. The header parser fails fast on the first missing required header; the response is indistinguishable regardless of which header failed (no per-header error detail exists in code). |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L242-L268` — `parseRequiredHeaders` |

## Scenario S08-023 — Whitespace-padded valid header values are trimmed and accepted

| Field | Content |
|-------|---------|
| ID | S08-023 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `x-idempotency-key: "  5f6a7b8c-9d0e-4f1a-2b3c-4d5e6f7a8b9c  "`, `x-capability-version: "  1.0.0  "`, valid body, no `Authorization`. |
| Expected outcome | Not 422. Trimmed values are non-empty → preAccept runs → HTTP 401 `unauthenticated` taxonomy JSON. Note for Stage 9: the **trimmed** values are what reach the guard and Quota DO (`parsedHeaders` are post-trim). |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L243-L251` — trim on both required headers |

## Scenario S08-024 — No charset or format bounds: single-char key and non-semver version pass ingress

| Field | Content |
|-------|---------|
| ID | S08-024 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `x-idempotency-key: x` (one character), `x-capability-version: not-a-published-version`, body `{"capability_id":"clinic.visit_summary"}`, no `Authorization`. |
| Expected outcome | Not 422. Ingress has no length/charset/semver checks — any non-empty strings pass (§1.1). Identity fails first → HTTP 401 `unauthenticated`. (With a valid AAT this same header set would reach manifest resolution and return 404 `capability_unknown` — Stage 9 stage-5 behavior; see S08-042.) |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L242-L268` — `parseRequiredHeaders` (trim-only validation) |

## Scenario S08-025 — Very long idempotency key (512 chars) passes ingress

| Field | Content |
|-------|---------|
| ID | S08-025 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `x-idempotency-key` = 512-character string `a1b2…` (no whitespace), `x-capability-version: 1.0.0`, valid body, no `Authorization`. |
| Expected outcome | Not 422. No length cap exists at ingress → HTTP 401 `unauthenticated`. (Any downstream length constraint is Stage 9 Quota DO / journal behavior, not this stage.) |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L243-L246` — idempotency-key check |

## Scenario S08-026 — Absent `x-trace-id` yields a server-minted ULID on the error body

| Field | Content |
|-------|---------|
| ID | S08-026 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{}` (no `capability_id`), valid required headers, no `x-trace-id`. |
| Expected outcome | HTTP 500 `internal_error` taxonomy JSON whose `trace_id` is a 26-character Crockford ULID matching `^[0-7][0-9A-HJKMNP-TV-Z]{25}$`, minted by `resolveTraceId(null)` → `generateUlid()`. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L258-L263` — `resolveTraceId` call; `ai-platform/src/trace.ts:L24-L29` — `resolveTraceId`/`generateUlid` |

## Scenario S08-027 — Non-ULID supplied trace id is echoed verbatim (trimmed)

| Field | Content |
|-------|---------|
| ID | S08-027 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{}`, valid required headers, `x-trace-id: "  550e8400-e29b-41d4-a716-446655440000  "`. |
| Expected outcome | HTTP 500 `internal_error` with `trace_id` exactly `550e8400-e29b-41d4-a716-446655440000` (whitespace trimmed, value otherwise unvalidated — any non-empty string is accepted, per A2). |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L258-L263` — trim + accept; `ai-platform/src/trace.ts:L24-L29` |

## Scenario S08-028 — Client ULID trace id is echoed on taxonomy bodies and SSE events

| Field | Content |
|-------|---------|
| ID | S08-028 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{}`, valid required headers, `x-trace-id: 01ARZ3NDEKTSV4RRFFQ69G5FAV`. |
| Expected outcome | HTTP 500 `internal_error` with `trace_id: "01ARZ3NDEKTSV4RRFFQ69G5FAV"`. The same id would be stamped on every SSE event had the request been accepted (S08-049). |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/adapter.ts:L258-L263`; `ai-platform/src/adapter.ts:L453-L462` — `AdapterStreamContext.traceId` |

## Scenario S08-029 — Missing `capability_id` is `internal_error` 500, guard never runs

| Field | Content |
|-------|---------|
| ID | S08-029 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{}`, valid required headers, valid `x-trace-id: 01ARZ3NDEKTSV4RRFFQ69G5FAV`. |
| Expected outcome | HTTP 500, `content-type: application/json`, body `{"code":"internal_error","request_reference":"<Crockford XXXX-XXXX>","trace_id":"01ARZ3NDEKTSV4RRFFQ69G5FAV","retry_safe":true}`. The reference **is** minted (preAccept generates it before extraction), but `runGuard` is never called. No SSE. |
| Side effects | None — no D1/DO/R2 write; the reference exists only on the wire and in logs. |
| Code reference | `ai-platform/src/worker.ts:L1043-L1047` — `createProductionPreAccept` missing-capability branch; `ai-platform/src/worker.ts:L251-L259` — `extractCapabilityId` |

## Scenario S08-030 — Non-string `capability_id` (number) is `internal_error` 500

| Field | Content |
|-------|---------|
| ID | S08-030 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability_id":1}`, valid required headers. |
| Expected outcome | HTTP 500 `internal_error` taxonomy JSON with Crockford reference. `typeof body.capability_id === "string"` fails and no `capability` alias is present. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L251-L259` — `extractCapabilityId` type guard |

## Scenario S08-031 — Empty-string `capability_id` is `internal_error` 500

| Field | Content |
|-------|---------|
| ID | S08-031 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability_id":""}`, valid required headers. |
| Expected outcome | HTTP 500 `internal_error`. The empty string passes the `typeof` check but is falsy at the `if (!capabilityId)` gate. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1043-L1047` — falsy capability check |

## Scenario S08-032 — Alias `capability` is honored when `capability_id` is absent

| Field | Content |
|-------|---------|
| ID | S08-032 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability":"clinic.visit_summary"}`, valid required headers, no `Authorization`. |
| Expected outcome | Not 500. Extraction succeeds via the alias, so the guard runs and fails identity: HTTP 401 `unauthenticated` taxonomy JSON with Crockford reference. The 401 (not 500) is the observable proof the alias was read. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/worker.ts:L251-L259` — `extractCapabilityId` alias fall-through |

## Scenario S08-033 — Non-string `capability_id` falls through to a valid `capability` alias

| Field | Content |
|-------|---------|
| ID | S08-033 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability_id":1,"capability":"clinic.visit_summary"}`, valid required headers, no `Authorization`. |
| Expected outcome | HTTP 401 `unauthenticated` (not 500): the wrong-typed primary key does not short-circuit; the alias is consulted next and succeeds. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/worker.ts:L251-L259` — sequential `typeof` checks |

## Scenario S08-034 — `capability_id` wins over `capability` when both are present (precedence)

| Field | Content |
|-------|---------|
| ID | S08-034 |
| Journey setup | Enrolled + entitled installation (see chapter preamble); real AAT exported as `$AAT`. |
| Action | `POST /v1/requests` with `Authorization: Bearer $AAT`, valid required headers, body `{"capability_id":"clinic.not_a_capability","capability":"clinic.visit_summary","context":{"org":"c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f","branch":"b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e","visit.chief_complaint@v1":"Patient reports headache for 3 days."}}`. |
| Expected outcome | HTTP 404 `{"code":"capability_unknown",…,"retry_safe":false}` — the primary key's (unknown) value drove manifest resolution, proving `capability_id` takes precedence over the alias. Registry pairing is Stage 9 stage-5 behavior. |
| Side effects | No SSE; no Quota DO admission for the unknown capability (Stage 9 behavior). |
| Code reference | `ai-platform/src/worker.ts:L251-L254` — primary key checked first |

## Scenario S08-035 — No `Authorization` header passes ingress, fails guard identity as 401

| Field | Content |
|-------|---------|
| ID | S08-035 |
| Journey setup | None. |
| Action | `POST /v1/requests` body `{"capability_id":"clinic.visit_summary"}`, valid required headers, `x-trace-id: probe-anon-trace`, no `Authorization`. |
| Expected outcome | HTTP 401 `{"code":"unauthenticated","request_reference":"<Crockford>","trace_id":"probe-anon-trace","retry_safe":true}`, `content-type: application/json`, no SSE. The adapter deliberately does not check `Authorization`; `extractBearerToken` returns `undefined` and guard stage 2 rejects (Stage 9 behavior). |
| Side effects | No D1/DO writes (identity precedes admission). |
| Code reference | `ai-platform/src/worker.ts:L242-L249` — `extractBearerToken`; `ai-platform/src/worker.ts:L1052-L1053` — token passed into `runGuard` |

## Scenario S08-036 — Non-JWS Bearer token is 401

| Field | Content |
|-------|---------|
| ID | S08-036 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `Authorization: Bearer not-a-jws`, valid body and headers. |
| Expected outcome | HTTP 401 `unauthenticated` taxonomy JSON, no SSE. The Bearer shape parses but the token fails AAT verification (Stage 9 stage-2 behavior). |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/worker.ts:L242-L249` — `extractBearerToken` |

## Scenario S08-037 — `Basic` scheme is treated as no token → 401

| Field | Content |
|-------|---------|
| ID | S08-037 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `Authorization: Basic Zm9vOmJhcg==`, valid body and headers. |
| Expected outcome | HTTP 401 `unauthenticated`. The `/^Bearer\s+(.+)$/i` regex does not match → token `undefined`. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/worker.ts:L242-L249` — scheme regex |

## Scenario S08-038 — Bare `Bearer` with no token is 401

| Field | Content |
|-------|---------|
| ID | S08-038 |
| Journey setup | None. |
| Action | `POST /v1/requests` with `Authorization: Bearer` (no token after the scheme), valid body and headers. |
| Expected outcome | HTTP 401 `unauthenticated`. The regex requires whitespace plus a non-empty capture; `match?.[1]?.trim() || undefined` collapses empty captures to `undefined`. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/worker.ts:L242-L249` — empty-capture collapse |

## Scenario S08-039 — Operator bearer token is not an AAT on this route → 401

| Field | Content |
|-------|---------|
| ID | S08-039 |
| Journey setup | `OPERATOR_BEARER_TOKEN` configured on the Worker. |
| Action | `POST /v1/requests` with `Authorization: Bearer <operator-secret>`, valid body and headers. |
| Expected outcome | HTTP 401 `unauthenticated` taxonomy JSON. The operator secret authorizes `/control/*` only; on `/v1/requests` it is just an unverifiable AAT. |
| Side effects | No D1/DO writes. |
| Code reference | `ai-platform/src/worker.ts:L1349-L1351` — live route has no operator-auth branch; `ai-platform/src/worker.ts:L1354-L1374` — operator auth confined to control routes |

## Scenario S08-040 — preAccept failure mapping: `installation_suspended` → 403 taxonomy JSON

| Field | Content |
|-------|---------|
| ID | S08-040 |
| Journey setup | Enrolled + entitled installation; AAT minted (S08-049 journey). Operator then suspends the installation via `POST /control/installations/7f3a9c1e-2b4d-4e6a-9c8f-0d1e2f3a4b5c/suspend` (Stage 3/9 behavior). |
| Action | `POST /v1/requests` with `Authorization: Bearer $AAT`, fresh `x-idempotency-key: 6a7b8c9d-0e1f-4a2b-3c4d-5e6f7a8b9c0d`, `x-capability-version: 1.0.0`, valid visit-summary body. |
| Expected outcome | HTTP 403 `{"code":"installation_suspended","request_reference":"<Crockford>","trace_id":"<echoed>","retry_safe":false}`, JSON, no SSE, no `retry_after`. Exercises `preAcceptFailureResponse` status mapping via `liveHttpStatusForCode`. |
| Side effects | No SSE; no admission call (Stage 9 identity/scope behavior). |
| Code reference | `ai-platform/src/adapter.ts:L213-L229` — `preAcceptFailureResponse`; `ai-platform/src/errors.ts:L163-L168` — `liveHttpStatusForCode` |

## Scenario S08-041 — preAccept failure mapping: `forbidden_capability` → 403

| Field | Content |
|-------|---------|
| ID | S08-041 |
| Journey setup | Enrolled installation whose entitlement is pending / `ai_disabled` (never entitled, or entitled without the visit-summary grant); valid AAT. |
| Action | `POST /v1/requests` with `Authorization: Bearer $AAT`, fresh idempotency key, valid visit-summary body. |
| Expected outcome | HTTP 403 `{"code":"forbidden_capability",…,"retry_safe":false}` with Crockford reference and echoed trace id. Identity already passed (not `unauthenticated`) — proof the request cleared ingress and preAccept started the guard. Guard entitlement logic is Stage 9 behavior. |
| Side effects | No SSE; no D1 journal row (Stage 9 behavior). |
| Code reference | `ai-platform/src/adapter.ts:L213-L229` — `preAcceptFailureResponse` |

## Scenario S08-042 — preAccept failure mapping: unpublished `x-capability-version` → 404 `capability_unknown`

| Field | Content |
|-------|---------|
| ID | S08-042 |
| Journey setup | Enrolled + entitled installation; valid AAT. |
| Action | `POST /v1/requests` with `x-capability-version: not-a-published-version` (non-empty, so ingress accepts it), valid visit-summary body with matching org/branch. |
| Expected outcome | HTTP 404 `{"code":"capability_unknown",…,"retry_safe":false}`. Ingress validated only non-emptiness; the registry key `{capability_id}@{version}` missed (Stage 9 stage-5 behavior). |
| Side effects | No SSE. |
| Code reference | `ai-platform/src/adapter.ts:L248-L251` (ingress accepts); `ai-platform/src/adapter.ts:L213-L229` (mapping) |

## Scenario S08-043 — preAccept failure mapping: unknown `capability_id` → 404 `capability_unknown`

| Field | Content |
|-------|---------|
| ID | S08-043 |
| Journey setup | Enrolled + entitled installation; valid AAT. |
| Action | `POST /v1/requests` body `{"capability_id":"clinic.not_a_capability","context":{"org":"c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f","branch":"b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e","visit.chief_complaint@v1":"Patient reports headache for 3 days."}}`, `x-capability-version: 1.0.0`. |
| Expected outcome | HTTP 404 `capability_unknown` taxonomy JSON. Distinct from S08-029: a non-empty unknown string reaches the guard; only missing/non-string/empty capability fails at preAccept with 500. |
| Side effects | No SSE. |
| Code reference | `ai-platform/src/worker.ts:L1043-L1047` (extraction succeeds); `ai-platform/src/adapter.ts:L213-L229` (mapping) |

## Scenario S08-044 — preAccept failure mapping: `rate_limited` → 429 with `retry_after` (the only code that carries it)

| Field | Content |
|-------|---------|
| ID | S08-044 |
| Journey setup | Enrolled + entitled installation; valid AAT. Test harness configures `RATE_LIMITER_INSTALLATION` as a real rate-limit binding with a tiny simple limit (e.g. 2 requests per 60 s). Two prior `POST /v1/requests` with fresh idempotency keys inside the window consumed the limit. |
| Action | Third `POST /v1/requests` inside the same window with `x-idempotency-key: 7b8c9d0e-1f2a-4b3c-4d5e-6f7a8b9c0d1e`, valid visit-summary body. |
| Expected outcome | HTTP 429 `{"code":"rate_limited","request_reference":"<Crockford>","trace_id":"<echoed>","retry_safe":true,"retry_after":60}` — `retry_after` is present **only** for `rate_limited` (`supplementaryFieldsForCode`); when neither the binding nor admission supplies a positive hint, the value defaults to 60 s (`DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS`). No SSE. Rate-limit dimensions and admission hints are Stage 9 behavior. |
| Side effects | No SSE; rejection counters flush is scheduled-cron behavior (FR-011), not this stage. |
| Code reference | `ai-platform/src/adapter.ts:L213-L229` — `preAcceptFailureResponse`; `ai-platform/src/errors.ts:L186-L201` — `supplementaryFieldsForCode`; `ai-platform/src/errors.ts:L176-L184` — `retryAfterSecondsForRateLimited` |

## Scenario S08-045 — preAccept failure mapping: `quota_exhausted` → 429 without `retry_after`

| Field | Content |
|-------|---------|
| ID | S08-045 |
| Journey setup | Enrolled installation entitled with `request_quota: 1` for the current period; one visit-summary request already driven to a terminal state (S08-049 journey, Stage 10 completion), consuming the quota. Valid AAT. |
| Action | `POST /v1/requests` with a fresh idempotency key, valid visit-summary body. |
| Expected outcome | HTTP 429 `{"code":"quota_exhausted","request_reference":"<Crockford>","trace_id":"<echoed>","retry_safe":true}` — **no** `retry_after` field, and no `period_reset` either: `createProductionPreAccept` forwards only `retryAfter` to the adapter, and `supplementaryFieldsForCode("quota_exhausted", {retryAfter})` omits an undefined/empty `periodReset`. No SSE. Admission arithmetic is Stage 9 behavior. |
| Side effects | No SSE; no additional quota debit (Stage 9 behavior). |
| Code reference | `ai-platform/src/worker.ts:L1087-L1096` — only `retryAfter` forwarded; `ai-platform/src/errors.ts:L193-L199` — `period_reset` omission rule |

## Scenario S08-046 — Guard taxonomy 422 (`context_required`) is JSON, unlike the adapter's bare 422

| Field | Content |
|-------|---------|
| ID | S08-046 |
| Journey setup | Enrolled + entitled installation; valid AAT. |
| Action | `POST /v1/requests` body `{"capability_id":"clinic.visit_summary","context":{"org":"c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f","branch":"b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e"}}` (required key `visit.chief_complaint@v1` omitted), valid headers. |
| Expected outcome | HTTP 422 but with `content-type: application/json` and body `{"code":"context_required","request_reference":"<Crockford>","trace_id":"<echoed>","retry_safe":true}`. Same status class as S08-010–015, completely different wire shape — the two 422 families must be asserted separately. Manifest context rules are Stage 9 stage-6 behavior. |
| Side effects | No SSE. |
| Code reference | `ai-platform/src/adapter.ts:L205-L211` (bare 422) vs `ai-platform/src/adapter.ts:L213-L229` (taxonomy 422) |

## Scenario S08-047 — preAccept failure mapping: tenant mismatch → 422 `context_invalid`

| Field | Content |
|-------|---------|
| ID | S08-047 |
| Journey setup | Enrolled + entitled installation; valid AAT whose `org` is `c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f`. |
| Action | `POST /v1/requests` body with `"context":{"org":"00000000-0000-4000-8000-0000000000aa","branch":"b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e","visit.chief_complaint@v1":"Patient reports headache for 3 days."}`, valid headers. |
| Expected outcome | HTTP 422 `{"code":"context_invalid",…,"retry_safe":false}` taxonomy JSON, no SSE. Tenant binding (`context.org`/`context.branch` vs AAT claims) is Stage 9 stage-6 behavior. |
| Side effects | No SSE. |
| Code reference | `ai-platform/src/adapter.ts:L213-L229` — mapping; `ai-platform/src/worker.ts:L1065` — `suppliedContext` handed to guard |

## Scenario S08-048 — Chief complaint over the 4096-byte manifest cap is 422 `context_invalid`, not 413

| Field | Content |
|-------|---------|
| ID | S08-048 |
| Journey setup | Enrolled + entitled installation; valid AAT. |
| Action | `POST /v1/requests` body with `"visit.chief_complaint@v1"` = 5,000-character string (`x` repeated), matching org/branch; total body well under 1 MiB; valid headers. |
| Expected outcome | HTTP 422 `context_invalid` taxonomy JSON — the manifest `maxSize` (4096 bytes) is a guard-stage-6 check; the adapter's 1 MiB gate correctly does not fire. Boundary note: exactly 4096 bytes passes this check (Stage 9 territory). |
| Side effects | No SSE. |
| Code reference | `ai-platform/src/adapter.ts:L373-L399` (ingress passes); `ai-platform/src/adapter.ts:L213-L229` (mapping) |

## Scenario S08-049 — Happy path: real AAT + entitled installation → 200 SSE with `accepted` first event

| Field | Content |
|-------|---------|
| ID | S08-049 |
| Journey setup | Enrolled + entitled installation (preamble). AAT minted via Stage 6 `issue_ai_token()`; claims decoded to confirm `org`/`branch`. Context value obtained the realistic way — S08-061's RPC happy path supplied the complaint string. |
| Action | `POST /v1/requests` with `Authorization: Bearer $AAT`, `Content-Type: application/json`, `x-idempotency-key: 8c9d0e1f-2a3b-4c5d-6e7f-8a9b0c1d2e3f`, `x-capability-version: 1.0.0`, `x-trace-id: 01ARZ3NDEKTSV4RRFFQ69G5FAV`, body `{"capability_id":"clinic.visit_summary","user_intent":"Summarize today's visit for the chart.","context":{"org":"c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f","branch":"b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e","visit.chief_complaint@v1":"Patient reports headache for 3 days."}}`. |
| Expected outcome | HTTP 200 with headers exactly `content-type: text/event-stream`, `cache-control: no-cache`, `connection: keep-alive`. First bytes on the stream: `event: accepted\ndata: {"request_reference":"<Crockford XXXX-XXXX>","trace_id":"01ARZ3NDEKTSV4RRFFQ69G5FAV"}\n\n` — no `degraded_notice` key (fresh entitlement is not degraded). Everything after `accepted` (heartbeat, text_delta, terminal) is Stage 10 behavior. |
| Side effects | preAccept stored an `AcceptContext{kind:"fresh"}` in the request-scoped map and the event source consumed it (Stage 9/10 behavior: `ai_request` INSERT on fresh admission, Quota DO admission hold). No R2 write at this stage. |
| Code reference | `ai-platform/src/adapter.ts:L560-L568` — SSE response; `ai-platform/src/adapter.ts:L510-L525` — `accepted` enqueue; `ai-platform/src/adapter.ts:L96-L112` — `buildAcceptedSseEvent` |

## Scenario S08-050 — Routing-injection body keys are silently ignored on the full journey to `accepted`

| Field | Content |
|-------|---------|
| ID | S08-050 |
| Journey setup | Same as S08-049 (enrolled + entitled, non-degraded). |
| Action | `POST /v1/requests` as S08-049 but body adds `"routing_tier":"degraded","degraded":true,"degraded_notice":true` and uses the `capability` alias instead of `capability_id`; fresh idempotency key `9d0e1f2a-3b4c-4d5e-6f7a-8b9c0d1e2f3a`. |
| Expected outcome | HTTP 200 SSE; `accepted` data contains `request_reference` and `trace_id` and **no** `degraded_notice`. `ADAPTER_ROUTING_BODY_FIELDS = []` — nothing on the production request path reads those keys; routing tier and degraded state come from Quota DO admission only (`routingTierFromAdmission` / `degradedNoticeFromAdmission`). Alias extraction also proven on an authenticated journey. |
| Side effects | Same as S08-049; no client-planted routing state reaches D1/DO. |
| Code reference | `ai-platform/src/adapter.ts:L274-L279` — `ADAPTER_ROUTING_BODY_FIELDS`; `ai-platform/src/worker.ts:L1107-L1114` — degraded notice sourced from admission |

## Scenario S08-051 — Degraded admission surfaces as `degraded_notice: true` on `accepted`

| Field | Content |
|-------|---------|
| ID | S08-051 |
| Journey setup | Enrolled installation entitled with a small `token_budget` and `soft_threshold: 0.8`; prior requests (S08-049 journeys) drove usage past the soft threshold so admission now returns degraded (Stage 9 soft-threshold behavior). Valid AAT. |
| Action | `POST /v1/requests` as S08-049 with fresh idempotency key `0e1f2a3b-4c5d-4e6f-7a8b-9c0d1e2f3a4b`. |
| Expected outcome | HTTP 200 SSE; first event `event: accepted` with data `{"request_reference":"<Crockford>","trace_id":"<echoed>","degraded_notice":true}`. The flag appears only when `preAccept` returns `degradedNotice: true` — never from the request body (contrast S08-050). |
| Side effects | Same class as S08-049 (Stage 9 admission behavior). |
| Code reference | `ai-platform/src/adapter.ts:L100-L106` — conditional `degraded_notice`; `ai-platform/src/worker.ts:L1107-L1114` — `degradedNoticeFromAdmission` wiring |

## Scenario S08-052 — Request reference format and per-request uniqueness

| Field | Content |
|-------|---------|
| ID | S08-052 |
| Journey setup | Same as S08-049. |
| Action | Two `POST /v1/requests` as S08-049 with distinct fresh idempotency keys. |
| Expected outcome | Both `accepted` events carry references matching `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` (Crockford base32; alphabet excludes `I`, `L`, `O`, `U`) and the two references differ. The same format appears on all preAccept failure bodies (S08-029…S08-048) and is the handle for `GET /v1/requests/{ref}` (Stage 11 behavior). |
| Side effects | Two independent fresh admissions (Stage 9 behavior). |
| Code reference | `ai-platform/src/reference.ts:L1-L18` — alphabet + `generateRequestReference`; `ai-platform/src/adapter.ts:L419` — minted before the gate runs |

## Scenario S08-053 — Idempotent replay: same idempotency key replays the prior terminal outcome after `accepted`

| Field | Content |
|-------|---------|
| ID | S08-053 |
| Journey setup | S08-049's request driven to a terminal `completed` state (Stage 10 behavior) under idempotency key `8c9d0e1f-2a3b-4c5d-6e7f-8a9b0c1d2e3f`. |
| Action | Repeat the exact S08-049 POST with the **same** idempotency key and same body. |
| Expected outcome | HTTP 200 SSE. First event is a **new** `accepted` (fresh reference, echoed trace id); the stream then immediately replays the prior terminal: `event: completed` with `data.result.finalContent.text = "Prior request completed."` and `authoritative: true`. Admission's idempotent outcome and journal skip are Stage 9 behavior; the adapter-side observation is `accepted` followed by a terminal event and stream close. |
| Side effects | No second Quota DO debit, no second `ai_request` row (Stage 9 behavior — asserted there, referenced here). |
| Code reference | `ai-platform/src/worker.ts:L1098-L1104` — idempotent accept context; `ai-platform/src/worker.ts:L607-L640` — `replayIdempotentTerminal` |

## Scenario S08-054 — `user_intent` / `intent` alias and precedence (incl. wrong-type fall-through)

| Field | Content |
|-------|---------|
| ID | S08-054 |
| Journey setup | Same as S08-049. |
| Action | Three `POST /v1/requests` variants with fresh keys: (a) both `user_intent: "Summarize for the chart."` and `intent: "IGNORED"`; (b) only `intent: "Summarize today."`; (c) `user_intent: 123` (wrong type) with `intent: "Summarize today."`. |
| Expected outcome | All three pass ingress and reach `accepted` (entitled) — neither field is ingress-required and wrong types are never a 422 (§1.3). Precedence handed to Stage 9 compose by behavior reference: (a) `user_intent` wins; (b) alias used; (c) **the alias is used** — `extractUserIntent` falls through to `intent` when `user_intent` is non-string. |
| Side effects | Same class as S08-049. |
| Code reference | `ai-platform/src/worker.ts:L261-L269` — `extractUserIntent` fall-through |

## Scenario S08-055 — Non-object `context` is not an ingress error; extractors fall back to `{}`

| Field | Content |
|-------|---------|
| ID | S08-055 |
| Journey setup | Same as S08-049. |
| Action | `POST /v1/requests` body `{"capability_id":"clinic.visit_summary","context":[]}` (array), valid AAT and headers. Repeat with `"context":"chief complaint text"` and `"context":null`. |
| Expected outcome | Never an adapter 422 (the root body is still a plain object). `extractSuppliedContext` returns `{}` for any non-plain-object `context`, so the entitled journey fails later with HTTP 422 `context_required` (missing chief-complaint key) — not `context_invalid` from the array type alone. Stage 9 stage-6 behavior for the requirement check. |
| Side effects | No SSE. |
| Code reference | `ai-platform/src/worker.ts:L271-L278` — `extractSuppliedContext`; `ai-platform/src/worker.ts:L237-L240` — `isPlainObject` |

## Scenario S08-056 — Client disconnect after `accepted` closes the stream without a `cancelled` event on the wire

| Field | Content |
|-------|---------|
| ID | S08-056 |
| Journey setup | S08-049 journey in flight (accepted, provider stream pending — Stage 10 behavior). |
| Action | Abort the client connection (cancel the `response.body` reader) after the `accepted` event arrives. |
| Expected outcome | The stream closes; **no** `cancelled` SSE event is enqueued to a disconnected client (contract §4 — nobody left to receive it). The adapter fires `notifyDisconnect("client_close")` exactly once, aborts the connection-scoped signal, and calls the event source handle's `disconnect("client_close")` so the broker can abort the in-flight provider fetch (Stage 10 behavior; terminal settlement as `cancelled` is Stage 9/10 journaling behavior). |
| Side effects | No further SSE frames; eventual `Cancelled` terminal journal state is Stage 10 behavior referenced here. |
| Code reference | `ai-platform/src/adapter.ts:L538-L544` — stream `cancel()`; `ai-platform/src/adapter.ts:L476-L488` — `notifyDisconnect`; `ai-platform/src/adapter.ts:L547-L559` — request abort listener |

## Scenario S08-057 — Request aborted before the stream starts still emits `accepted`, then closes

| Field | Content |
|-------|---------|
| ID | S08-057 |
| Journey setup | None (adapter-level edge: construct the `Request` with an already-aborted `AbortSignal`). |
| Action | `POST /v1/requests` equivalent through the real adapter with `request.signal` aborted at entry, valid body/headers, entitled wiring as S08-049. |
| Expected outcome | The `accepted` event is enqueued (it is unconditional in `start()`), then the stream is immediately closed without invoking the event source factory's fresh path beyond handle capture; `notifyDisconnect("client_close")` fires once. No terminal event is enqueued. |
| Side effects | None beyond the S08-049 class; the abort listener is not double-registered (`abortedAtEntry` guard). |
| Code reference | `ai-platform/src/adapter.ts:L470` — `abortedAtEntry`; `ai-platform/src/adapter.ts:L526-L532` — aborted-at-entry branch; `ai-platform/src/adapter.ts:L547-L559` — listener registration guard |

## Scenario S08-058 — Missing event source fails fast with 503 (adapter contract; unreachable via worker wiring)

| Field | Content |
|-------|---------|
| ID | S08-058 |
| Journey setup | None. **Note:** `handleLivePostRequest` always wires `eventSource`, so this branch is not reachable through `SELF.fetch`; the scenario drives the real adapter entry `handleAdapterRequest` directly with `preAccept` set and `eventSource` omitted. |
| Action | Valid `POST /v1/requests` shape (plain-object body, both required headers) through `handleAdapterRequest(request, { preAccept: async () => ({ ok: true }) })`. |
| Expected outcome | HTTP 503, `content-type: text/plain`, body `event source required`. The check runs **after** a successful preAccept, so a request reference was minted but is not surfaced on the wire. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L444-L448` — event-source gate; `ai-platform/src/adapter.ts:L230-L236` — `eventSourceRequiredResponse` |

## Scenario S08-059 — Body stream read error is a bare 422, not a 500

| Field | Content |
|-------|---------|
| ID | S08-059 |
| Journey setup | None. Construct the request body as a `ReadableStream` whose reader throws mid-read (e.g. `new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode('{"a":')); c.error(new Error("boom")); } })`). |
| Action | `POST /v1/requests` with that erroring body, valid required headers. |
| Expected outcome | HTTP 422, `text/plain`, empty body (`read_error` maps to `adapterParseFailureResponse`, same wire shape as a parse failure). Logged as `ingress_body_read_error`. |
| Side effects | None. |
| Code reference | `ai-platform/src/adapter.ts:L354-L356` — read-error catch; `ai-platform/src/adapter.ts:L386-L388` — mapping to bare 422 |

## Scenario S08-060 — Adapter without a preAccept gate accepts directly (reference minted after the event-source check)

| Field | Content |
|-------|---------|
| ID | S08-060 |
| Journey setup | None. Adapter-contract scenario (production always wires `preAccept`): drive `handleAdapterRequest` with an `eventSource` stub and **no** `preAccept`. |
| Action | Valid `POST /v1/requests` shape through `handleAdapterRequest(request, { eventSource: (sink, ctx) => { sink.push({ type: "completed", data: { result: {}, trace_id: ctx.traceId }, trace_id: ctx.traceId }); } })`. |
| Expected outcome | HTTP 200 SSE; `accepted` event carries a Crockford `request_reference` minted at `requestReference ??= generateRequestReference()` and the echoed/generated trace id; no `degraded_notice` (undefined without a gate). The stub's `completed` event follows and the stream closes (terminal-event close semantics). |
| Side effects | None (no D1/DO in this harness). |
| Code reference | `ai-platform/src/adapter.ts:L450` — post-check minting; `ai-platform/src/adapter.ts:L490-L508` — sink terminal close |

## Scenario S08-061 — Context provider RPC happy path supplies `visit.chief_complaint@v1`, full journey to `accepted`

| Field | Content |
|-------|---------|
| ID | S08-061 |
| Journey setup | Clinic Supabase with migration `20260802120000_context_provider_chief_complaint.sql` applied. Clinician session (visit clinical read permission) in branch `b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e`. Visit `5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b` exists in that branch with a non-deleted `visit_clinical_notes` row `complaint = 'Patient reports headache for 3 days.'`, `created_at = 2026-09-05T08:15:00.000Z`. |
| Action | `SELECT public.get_visit_chief_complaint('5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b'::uuid);` (equivalently PostgREST `POST /rest/v1/rpc/get_visit_chief_complaint` with `{"p_visit_id":"5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b"}`). Then place `data.complaint` into the ingress body and POST as S08-049 with fresh key `1f2a3b4c-5d6e-4f7a-8b9c-0d1e2f3a4b5c`. |
| Expected outcome | RPC: `success = true`, `data = {"visit_id":"5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b","complaint":"Patient reports headache for 3 days.","recorded_at":"2026-09-05T08:15:00.000Z"}` (`recorded_at` is UTC with `Z`, millisecond precision). Ingress POST: not `context_required`; HTTP 200 SSE `accepted` as S08-049. This is the realistic client assembly path for `context` — the gateway never calls clinic Postgres. |
| Side effects | RPC: none (read-only, SECURITY DEFINER internal function behind a SECURITY INVOKER wrapper). Ingress: S08-049 class. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L30-L53` — note lookup + payload build; `ai-platform/src/worker.ts:L1065` — `suppliedContext` into guard |

## Scenario S08-062 — RPC with no clinical note row succeeds with `visit_id` only; client omits the key and gets `context_required`

| Field | Content |
|-------|---------|
| ID | S08-062 |
| Journey setup | As S08-061, but the visit has **no** `visit_clinical_notes` row. |
| Action | Call the RPC; observe success without `complaint`; client omits `visit.chief_complaint@v1` from `context` and POSTs as S08-046. |
| Expected outcome | RPC: `success = true`, `data = {"visit_id":"5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b"}` only (`FOUND` false → no `complaint`, no `recorded_at`). Ingress POST: HTTP 422 `context_required` taxonomy JSON (manifest marks the key required — Stage 9 stage-6 behavior). |
| Side effects | None from the RPC; no SSE from ingress. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L30-L52` — `IF FOUND` gate |

## Scenario S08-063 — RPC with a note whose `complaint` is NULL omits only the complaint key

| Field | Content |
|-------|---------|
| ID | S08-063 |
| Journey setup | As S08-061, but the note row has `complaint = NULL`, `created_at = 2026-09-05T09:00:00.000Z`. |
| Action | Call the RPC. |
| Expected outcome | `success = true`, `data = {"visit_id":"…","recorded_at":"2026-09-05T09:00:00.000Z"}` — `recorded_at` present (note row exists), `complaint` absent (NULL guard). The two payload fields are gated independently. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L39-L50` — independent `IF … IS NOT NULL` gates |

## Scenario S08-064 — RPC ignores soft-deleted notes

| Field | Content |
|-------|---------|
| ID | S08-064 |
| Journey setup | As S08-061, but the only note row for the visit has `is_deleted = true`. |
| Action | Call the RPC. |
| Expected outcome | `success = true`, `data = {"visit_id":"…"}` only — the `is_deleted = false` predicate excludes the row, so the result is identical to the no-note case (S08-062). |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L30-L36` — `is_deleted` predicate |

## Scenario S08-065 — RPC with an unknown visit UUID returns `NOT_FOUND`

| Field | Content |
|-------|---------|
| ID | S08-065 |
| Journey setup | Clinician session as S08-061. |
| Action | `SELECT public.get_visit_chief_complaint('00000000-0000-4000-8000-000000000099'::uuid);` |
| Expected outcome | `success = false`, `error_code = 'NOT_FOUND'`, `error_message = 'Visit was not found.'` — `assert_visit_branch_scope` raises `NOT_FOUND`, caught and mapped; all other exceptions re-raise. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L13-L22` — scope exception mapping |

## Scenario S08-066 — RPC for a visit outside the caller's branch scope returns `NOT_FOUND` (not `FORBIDDEN`)

| Field | Content |
|-------|---------|
| ID | S08-066 |
| Journey setup | Clinician session in branch `b2c3d4e5-…`; target visit exists but belongs to a different branch of the same clinic. |
| Action | Call the RPC with that visit's UUID. |
| Expected outcome | `success = false`, `error_code = 'NOT_FOUND'` — branch-scope failure is indistinguishable from a missing visit (no existence leak across branches). |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L13-L22` — `assert_visit_branch_scope` failure path |

## Scenario S08-067 — RPC without visit clinical read permission returns `FORBIDDEN`

| Field | Content |
|-------|---------|
| ID | S08-067 |
| Journey setup | Authenticated staff session **without** clinical read (role blocked by `staff_has_visit_clinical_access()`); visit `5a1f9c2e-…` is in the caller's branch scope. |
| Action | Call the RPC with the in-scope visit UUID. |
| Expected outcome | `success = false`, `error_code = 'FORBIDDEN'`, `error_message = 'You do not have permission to view this visit clinical data.'` The client must not place a `visit.chief_complaint@v1` value; a subsequent ingress POST without the key yields `context_required` (S08-046 journey). |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L24-L29` — permission gate |

## Scenario S08-068 — RPC check order: out-of-scope visit + no clinical permission yields `NOT_FOUND` (scope precedes permission)

| Field | Content |
|-------|---------|
| ID | S08-068 |
| Journey setup | Staff session without clinical read (as S08-067); target visit is outside the caller's branch scope (as S08-066). |
| Action | Call the RPC with the out-of-scope visit UUID. |
| Expected outcome | `success = false`, `error_code = 'NOT_FOUND'` — `assert_visit_branch_scope` runs before `staff_has_visit_clinical_access()`, so the scope error wins. Pairwise ordering of the two failure gates. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L13-L29` — sequential gates |

## Scenario S08-069 — RPC is not callable by anonymous clients

| Field | Content |
|-------|---------|
| ID | S08-069 |
| Journey setup | PostgREST request with the `anon` key (no authenticated staff session). |
| Action | `POST /rest/v1/rpc/get_visit_chief_complaint` with `{"p_visit_id":"5a1f9c2e-7b3d-4e8f-9a0b-1c2d3e4f5a6b"}` as `anon`. |
| Expected outcome | Permission denied (PostgreSQL `42501` `permission denied for function get_visit_chief_complaint`, surfaced by PostgREST as HTTP 401/403 depending on configuration) — `REVOKE EXECUTE … FROM PUBLIC, anon` plus `GRANT EXECUTE … TO authenticated` only. The context provider path requires an authenticated staff session before any AI ingress call is assembled. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:L56-L65` — wrapper + grant to authenticated; `backend/supabase/migrations/20260905120500_revoke_get_visit_chief_complaint_public_anon.sql` — REVOKE FROM PUBLIC/anon |

## Doc-drift observations

1. **No Content-Type check exists — fixed (D-23).** §1.2 documents that `handleAdapterRequest` has no content-type branch; any parseable plain-object body passes ingress (S08-016).
2. **No header length/charset/format bounds — fixed (D-23).** §1.1 documents trim-only validation in `parseRequiredHeaders` (`adapter.ts:L258-L284`); S08-024/S08-025 pin the behavior.
3. **Doc probe 8.3.9 `user_intent` fall-through — fixed (D-23).** §1.3 documents that a non-string `user_intent` falls through to the `intent` alias (S08-054 case c); orientation doc probe §8.3.9 still needs a separate edit.
4. **Unreachable branch: second parse check.** `adapter.ts:409-413` re-parses the body after `adapter.ts:390-393` already proved it parses; the `parsedBody === null` branch at L410-413 is dead code. Not a scenario (unreachable); flagged for cleanup.
5. **`quota_exhausted` never carries `period_reset` from the live ingress path.** `createProductionPreAccept` forwards only `retryAfter` (`worker.ts:1087-1096`), and `supplementaryFieldsForCode` omits undefined/empty `periodReset` (`errors.ts:193-199`). The `errors.ts` comment says concurrency-mapped refusals "must populate periodReset from the entitlement snapshot (F4)" — the live POST path cannot. Neither the orientation doc nor this chapter's scenarios can observe `period_reset` on `POST /v1/requests`; flagged for the Stage 9 chapter.
6. **`cancelled` would map to HTTP 500 at preAccept.** `liveHttpStatusForCode("cancelled")` returns `null` and `preAcceptFailureResponse` falls back to 500 (`adapter.ts:224`). The guard never returns `cancelled` from preAccept in production, so this is a latent, unreachable mapping — recorded, not scenarized.
7. **`context_requested` / `AwaitingContext` are not reachable at Stage 8.** `validateContextRequest` (`context/context-request.ts`) runs only inside `pushTerminalEvent` for conversational terminal emission (Stage 10 behavior); nothing at ingress produces or validates a context request. The orientation doc correctly scopes conversational fields to later stages.
8. **Doc §8.2 unprobeable list vs. this catalog.** The doc lists "guard stage-1 size re-check as a second 413" as unprobeable; agreed — the adapter never forwards an oversize body, so only one 413 exists on the live path. S08-003…S08-008 cover the adapter gate exhaustively.
9. **Doc §3.5 note "The guard re-checks UTF-8 byte length at stage 1"** — consistent with code (guard stage 1 is Stage 9 behavior); no drift, recorded for cross-chapter completeness.

## Non-automatable notes

1. **Content-Length header control under `@cloudflare/vitest-pool-workers`.** Workerd may normalize or strip a user-supplied `Content-Length` on constructed `Request` objects. S08-003, S08-005, and S08-009 depend on controlling that header; if the runtime forbids it, drive these through a raw TCP/HTTP client against `wrangler dev` (or an undici request with explicit headers) instead of `SELF.fetch`, and rely on the stream-path scenarios (S08-004, S08-006, S08-007) for in-pool coverage.
2. **Context-provider RPC scenarios (S08-061…S08-069) run against Supabase/PostgreSQL, not the workers pool.** They need a pgTAP suite or a PostgREST harness with role/claims impersonation (`request.jwt.claims`) to exercise `assert_visit_branch_scope` and `staff_has_visit_clinical_access()`. They are cataloged here because they are the realistic way clients assemble `context`; their automation belongs to the backend test stack.
3. **Rate-limit binding semantics (S08-044).** Tripping `rate_limited` realistically requires a functional `RATE_LIMITER_*` binding in the test environment. If the pool's rate-limit binding is a no-op, substitute an admission-driven `retryAfter` hint (Stage 9 behavior) and keep the assertion on the wire shape: `retry_after` present only for `rate_limited`, defaulting to 60.
4. **Disconnect timing (S08-056, S08-057).** Client-abort races are timing-sensitive; assert the steady-state outcomes (stream closed, no `cancelled` frame enqueued, single `disconnect("client_close")` notification, eventual `Cancelled` journal state per Stage 10) rather than exact interleavings.
5. **Adapter-contract scenarios (S08-058, S08-060).** Unreachable through the worker's production wiring (`handleLivePostRequest` always supplies both `preAccept` and `eventSource`); they are automated by invoking the real adapter entry `handleAdapterRequest` directly, not via `SELF.fetch`. No internal functions are called.
6. **SSE `connection: keep-alive` header (S08-049).** Some runtimes/proxies strip hop-by-hop headers on constructed responses; if unobservable in-pool, assert `content-type: text/event-stream` and `cache-control: no-cache` and verify `connection` against `wrangler dev`.
