# AI Platform Data Journey — Stage 12 — Lookup and support

## Table of Contents

1. [`GET /v1/requests/{request_reference}`](#1-get-v1requestsrequest_reference)
2. [`POST /control/support/lookup`](#2-post-controlsupportlookup)
3. [Journal retention vs lookup and reconciliation](#3-journal-retention-vs-lookup-and-reconciliation)

---

## 1. `GET /v1/requests/{request_reference}`


| Item  | Value                                  |
| ----- | -------------------------------------- |
| Auth  | Bearer AAT — `authenticateGetRequest` uses the isolate-scoped `ConfigCache` (same instance as `POST /v1/requests`) |

| Scope | Must match installation on journal row |


**D1 read:** `ai_request` by `request_reference`.

**If** `state === Completed` **and** `payload_pointer` **set:** R2 fetch envelope → return `result` from envelope.

## 2. `POST /control/support/lookup`

`OPERATOR_BEARER_TOKEN` required (`requireOperator`). Looks up by `request_reference` across
installations (`control/support-lookup.ts`). Same single shared bearer + `OPERATOR_ID` as every
other `/control/*` route: the audit trail cannot distinguish operators.

## 3. Journal retention vs lookup and reconciliation

After the journal horizon, `runRetentionPurge` nulls `usage_event.request_id` and deletes the
`ai_request` row. Support lookup by `request_reference` then finds nothing: the ticket is gone.
The usage money row remains, but it cannot be joined back to a request. `runReconciliation`'s
`LEFT JOIN usage_event u ON u.request_id = r.request_id` likewise cannot match those aged rows,
so reconciliation coverage shrinks with age. See [§9 in Alternative journeys](15-alternative-and-failure-journeys.md#9-journal-retention-and-aged-usage-joinability).

---
