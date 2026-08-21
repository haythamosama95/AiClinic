# AI Platform Data Journey — Stage 12 — Lookup and support

## Table of Contents

1. [`GET /v1/requests/{request_reference}`](#1-get-v1requestsrequest_reference)
2. [`POST /control/support/lookup`](#2-post-controlsupportlookup)

---

## 1. `GET /v1/requests/{request_reference}`


| Item  | Value                                  |
| ----- | -------------------------------------- |
| Auth  | Bearer AAT                             |
| Scope | Must match installation on journal row |


**D1 read:** `ai_request` by `request_reference`.

**If** `state === Completed` **and** `payload_pointer` **set:** R2 fetch envelope → return `result` from envelope.

## 2. `POST /control/support/lookup`

`OPERATOR_BEARER_TOKEN` required (`requireOperator`). Looks up by `request_reference` across
installations (`control/support-lookup.ts`).

---
