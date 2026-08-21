# AI Platform Data Journey — Taxonomy codes and HTTP mapping


| Code                            | HTTP     | Retry safe         | Consumes quota | Typical triggering data                           |
| ------------------------------- | -------- | ------------------ | -------------- | ------------------------------------------------- |
| `unauthenticated`               | 401      | After re-mint      | No             | Bad AAT, expired `exp`, JTI replay, retired `ver` |
| `installation_suspended`        | 403      | No                 | No             | `installation.status=suspended`                   |
| `forbidden_capability`          | 403      | No                 | No             | `entitlement.status`, plan, grants                |
| `rate_limited`                  | 429      | Yes                | No             | Rate limit bindings                               |
| `quota_exhausted`               | 429      | After period reset | No             | Quota DO counters vs entitlement                  |
| `request_too_large`             | 413      | No                 | No             | Body size, token estimate                         |
| `context_required`              | 422      | Yes                | No             | Missing manifest context keys                     |
| `context_invalid`               | 422      | No                 | No             | `org`/`branch` mismatch, bad shapes               |
| `conversation_budget_exhausted` | 409      | No                 | No             | Transcript limits                                 |
| `capability_unknown`            | 404      | No                 | No             | Bad `capability_id`                               |
| `capability_retired`            | 404      | No                 | No             | Lifecycle retired                                 |
| `capability_disabled`           | 503      | Later              | No             | Kill switches                                     |
| `provider_unavailable`          | 503      | Yes                | Partially      | Empty routing chain                               |
| `provider_rejected`             | 422      | No                 | Yes            | Provider 401/403, content filter                  |
| `validation_failed`             | 422      | Yes                | Yes            | Prose guards, truncation                          |
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

---

