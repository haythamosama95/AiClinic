# P4.3 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Notify body cap, rate limit, and work-row lease

**Question:** `POST /notify/paymob` must apply a body-size cap and a rate limit (unit Implements; 02 §2 TB-1). No cited section states the cap size, the rate (count, window, or key), or the HTTP response when either trips. The work-row lease length on `lease_until` is also unset (03 §2.9, 03 §5.6).

**Assumption:** `POST /notify/paymob` accepts a body of at most 1_048_576 bytes (1 MiB). A larger body answers HTTP 413 with an empty body. The same route allows 60 requests per 60 seconds per `CF-Connecting-IP`; a missing header uses the single key `unknown`. The request that exceeds that limit answers HTTP 429 with an empty body. Either refusal stores nothing and enqueues nothing. A work-row take sets `lease_until` 60 seconds ahead and succeeds only when `lease_until` is null or already past.

**Why:** The platform ingress gate already refuses a body over 1_048_576 bytes with HTTP 413, and the ABO clinic API already refuses an excess of requests with HTTP 429. The count 60 is the clinic API's per-token request limit, and 60 seconds is the period on every platform rate limiter. The notify caller has no tenant and no token (TB-1, AD-1), so the key is the connecting IP. The notify channel is provider-controlled, so the refusal is an empty body rather than a clinic-API error. The work runner's cron and its first backoff step are both one minute, so the lease is 60 seconds and a crashed runner is eligible on the next minute.

**Amended:** `docs/architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md` (§2 TB-1); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P4.3 Implements); `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§2.9, §5.6).
