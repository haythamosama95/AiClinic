# Contract: Typed Error Envelope (all endpoints)

Every Gateway failure — and, for correlation, every success — is associated with a `request_id`.
Failures return a uniform JSON body (FR-020, §10.4). Implemented as framework-level exception handlers
so behavior is identical across endpoints.

## Envelope

```json
{
  "error": {
    "code": "string (stable, machine-readable)",
    "message": "string (human-readable, non-sensitive)",
    "request_id": "string"
  }
}
```

- `code` is stable and safe to switch on by clients.
- `message` MUST NOT contain PHI or secrets.
- `request_id` MUST match the value logged for the request (traceability).

## Code ↔ HTTP status map (Phase 1)

| `code` | HTTP | Trigger (this phase) | Client guidance |
| --- | --- | --- | --- |
| `bad_request` | 400 | Malformed JSON / oversized body / invalid params. | Fix request; do not retry blindly. |
| `unauthenticated` | 401 | Missing, malformed, expired, not-yet-valid, or bad-signature token. | Re-login (Supabase session). |
| `forbidden` | 403 | Valid token, role lacks `ai.access`. | Hide/disable AI UI for this role. |
| `not_implemented` | 501 | `POST /v1/ai/generate` stub. | Treat generation as unavailable this phase. |
| `rate_limited` | 429 | Per-caller rate exceeded (if enabled). | Backoff + retry later. |
| `ai_no_capacity` | 503 | No healthy runner (also surfaced by `/ready`). | "AI temporarily unavailable." |
| `ai_timeout` | 504 | Reserved (Phase 2 inference timeouts). | Offer retry / manual. |

## Cross-cutting rules

- **`/health` and `/metrics`** are unauthenticated; all other endpoints require a valid JWT and emit
  `401`/`403` via this envelope on auth failure.
- **Auth precedence**: authentication (`401`) is checked before authorization (`403`); a missing token
  never yields `403`.
- **Isolation**: no error path performs a Supabase or database call; errors are computed purely from
  request + in-memory state.
- **Determinism for tests**: the auth matrix (valid / tampered / expired / nbf-future / missing /
  role-without-access) maps 1:1 to `200`/`401`/`403` and is asserted under both JWT validation modes
  (SC-004, SC-010).
