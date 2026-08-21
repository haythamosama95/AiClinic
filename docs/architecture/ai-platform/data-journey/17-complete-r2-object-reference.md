# AI Platform Data Journey — Complete R2 Object Reference

## Table of Contents

1. [Routing policy document](#1-routing-policy-document)
2. [Request diagnostic envelope](#2-request-diagnostic-envelope)

---

## 1. Routing policy document


| Property     | Value                                               |
| ------------ | --------------------------------------------------- |
| Key pattern  | `control/routing-policy/{policy_id}/{version}.json` |
| Content-Type | `application/json`                                  |
| D1 link      | `routing_policy.content_pointer`                    |
| Written by   | `control/routing-policy.ts` publish                 |
| Read by      | `config-cache` → router                             |


Full field list: [07-stage-5-routing-policy.md §4](07-stage-5-routing-policy.md#4-r2-document-every-field).

## 2. Request diagnostic envelope


| Property    | Value                                          |
| ----------- | ---------------------------------------------- |
| Key pattern | `request/{request_id}/envelope`                |
| D1 link     | `ai_request.payload_pointer`                   |
| Written by  | `journal/index.ts` on every terminal settlement (`Completed`, `Failed`, `Cancelled`) — one object per request |
| Read by     | `getRequest`, support lookup                   |
| Deleted by  | Retention purge (90d diagnostic horizon)       |


Full field list: [13-stage-11-terminal-settlement.md §7](13-stage-11-terminal-settlement.md#7-r2-envelope-every-field).

---

