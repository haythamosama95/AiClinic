# Contract: Control-plane support lookup (F3)

**Frozen by:** Slice F3 — Support lookup, retention purges, usage rollups, and journal dashboards
**Implements:** §4.5, §8.9, §7.6, A13 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this surface; they may not **rewrite** the I/O
budget, operator-auth boundary, reference input contract, or reconstructable-trace field set
(delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/support/index.ts`; control-plane dispatch in
`ai-platform/src/control/index.ts` / `ai-platform/src/worker.ts`.

**Traces to:** spec **Freezes** (control-plane support lookup; request-reference input contract);
FR-001–FR-006, FR-019.

**Consumes (unchanged):** C3 R2 envelope + journal rows + `getRequest` (distinct client path);
A2/C3 `normalizeRequestReference` (`ai-platform/src/reference.ts`); B2 `OperatorAuth`.

---

## 1. Overview

Support lookup is the operator-only control-plane function that resolves a user-visible request
reference to the full reconstructable journal trace and, when still within diagnostic retention,
the R2 payload envelope. It is separately authenticated with **operator identity**, not clinic
identity (§4.5). It is distinct from C3 `GET /v1/requests/{reference}` (terminal state + validated
result only).

---

## 2. Request-reference input contract

| Property | Value |
| --- | --- |
| **Format** | `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` (eight Crockford base32 symbols, two hyphen-separated groups of four), e.g. `7QK4-2B9F` (§8.9; A13) |
| **Normalisation before lookup** | Trim whitespace on the control-plane handler, then case-fold up; `I`/`L` → `1`; `O` → `0` — via existing `normalizeRequestReference` (A2/C3). Do not fork a second normaliser. |
| **Lookup key** | Unique index `idx_ai_request_request_reference` on `ai_request.request_reference` (A5) |
| **Blank / missing** | Missing query param or whitespace-only → control-plane **400** `missing_reference` |
| **Malformed after normalisation** | Fails the format above → control-plane **400** `invalid_reference` (not a new §5.4 taxonomy code) |
| **Unknown but format-valid** | Control-plane **404** `not_found` without inventing a taxonomy code |

---

## 3. Authentication

| Caller | Outcome |
| --- | --- |
| Authenticated **operator** (`OperatorAuth` resolves) | Lookup proceeds |
| Clinic / non-operator credentials | **Denied** — control-plane auth boundary; no new §5.4 taxonomy code |

Reuses B2 `OperatorAuth` / `requireOperator`. Does not invent a new identity system.

---

## 4. I/O budget

| Step | Budget | Notes |
| --- | --- | --- |
| D1 | **Exactly one** indexed round trip on `request_reference` | Must return the request row **and** attempt detail as the full trace in that one lookup (JOIN / single statement). A second D1 round trip for the same lookup violates Done when / §3.11.6 (spy). |
| R2 | **At most one** `GetObject` on `request/{id}/envelope` (or `payload_pointer`) | Performed only when the envelope is still within diagnostic retention and a pointer/key exists. Expired / missing envelope → no second fetch attempt; metadata still returned. |

Support lookup is off the inference path and must not introduce a second Quota DO round trip or
second R2 object *per inference request* (delivery plan §6.4).

---

## 5. Reconstructable trace (D1)

The single indexed lookup MUST surface (§8.9):

**Request row:** installation, actor, branch, capability@version, prompt artifact hash, state and
milestone timestamps (`created_at` / `updated_at` / `completed_at`), terminal error code, trace id,
request id, request reference, payload pointer.

**Attempt detail (per `ai_attempt` row):** provider, model, latency, tokens, provider request ids,
error codes (and attempt ordinal / outcome as already stored by C3).

---

## 6. Envelope (R2)

When the diagnostic envelope is **within** retention:

- One `GetObject` returns the C3 envelope JSON (`context`, `prompt`, `attempts[]`, `result`).
- Reconstruction includes prompt, context, raw responses, and result (§8.9).

When **outside** diagnostic retention (or object absent):

- Journal metadata (trace) still resolves.
- Envelope body is absent from the response (§8.9; §7.7 `diagnostic`).

Retention horizon evaluation for “within diagnostic retention” follows
`contracts/retention-purge.md` (per-capability `retentionClass`).

---

## 7. Response shape (operator-facing)

```typescript
type SupportLookupResult =
  | { found: false }
  | {
      found: true;
      request: SupportLookupRequestTrace;
      attempts: SupportLookupAttemptTrace[];
      envelope: Envelope | null; // null when outside diagnostic retention or missing
    };
```

`Envelope` is the C3 frozen type (`specs/027-journal-writer-get-request/contracts/journal.md` §2).
Field names on the wire match journal column semantics; F3 does not invent parallel clinic-DB
mirrors.

Support lookup is a **read** — it does not write `control_audit` (FR-018).

---

## 8. Route

Control-plane path (exact path chosen at implement time under `/control/…`), operator-authenticated,
e.g. lookup by reference query/path segment. Must not reuse or alter `GET /v1/requests/{reference}`.
