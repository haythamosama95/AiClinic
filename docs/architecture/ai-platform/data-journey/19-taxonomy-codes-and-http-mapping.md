# AI Platform Data Journey — Taxonomy codes and HTTP mapping


| Code                            | HTTP     | Retry safe         | Consumes quota | Typical triggering data                           |
| ------------------------------- | -------- | ------------------ | -------------- | ------------------------------------------------- |
| `unauthenticated`               | 401      | After re-mint      | No             | Bad AAT, expired `exp`, JTI replay, retired `ver` |
| `installation_suspended`        | 403      | No                 | No             | `installation.status=suspended`                   |
| `forbidden_capability`          | 403      | No                 | No             | `entitlement.status`, plan, grants, missing `requiredCapabilityScope` in `principal.scopes`, `principal.role` not in non-empty `Access.allowedStaffRoles` |
| `rate_limited`                  | 429      | Yes                | No             | Rate limit bindings, or grace-admission cap while the Quota DO is down |
| `quota_exhausted`               | 429      | After period reset | No             | Quota DO counters vs entitlement (not the grace cap) |
| `request_too_large`             | 413      | No                 | No             | Body size, token estimate including prompt-artifact bytes |
| `context_required`              | 422      | Yes                | No             | Missing manifest context keys                     |
| `context_invalid`               | 422      | No                 | No             | `org`/`branch` mismatch, bad shapes               |
| `conversation_budget_exhausted` | 409      | No                 | No             | Transcript limits                                 |
| `capability_unknown`            | 404      | No                 | No             | Bad `capability_id`                               |
| `capability_retired`            | 404      | No                 | No             | Lifecycle retired                                 |
| `capability_disabled`           | 503      | Later              | No             | `Access.killSwitchFlag === true`, or D1 `kill_switch` (global / capability / installation). A `provider:<id>` kill switch is routing exclusion, not this code |
| `provider_unavailable`          | 503      | Yes                | Partially      | Empty routing chain                               |
| `provider_rejected`             | 422      | No                 | Yes            | Provider 401/403, content filter                  |
| `validation_failed`             | 422      | Yes                | Yes            | Prose guards (length, stop, leak, refusal prefix, injection-echo), truncation |
| `cancelled`                     | SSE only | —                  | Partially      | Client disconnect                                 |
| `timeout`                       | 504      | Yes                | Partially      | Provider timeout                                  |
| `internal_error`                | 500      | Yes                | No             | D1/compose/routing miss                           |


**Error body shape (HTTP and SSE** `failed`**):**

```json
{
  "code": "<taxonomy>",
  "request_reference": "<XXXX-XXXX>",
  "trace_id": "<ulid>",
  "retry_safe": <boolean>
}
```

Supplementary fields when applicable: `retry_after`, `period_reset`, `missing_keys`.
Live pre-SSE `rate_limited` (429) includes `retry_after`: the Rate Limit
binding's `retryAfter` hint when `limit()` supplies a positive number, otherwise
the 60s simple-limiter window. The field is attached by
`preAcceptFailureResponse` via `supplementaryFieldsForCode` (same error-body
shape as SSE `failed`).

---

