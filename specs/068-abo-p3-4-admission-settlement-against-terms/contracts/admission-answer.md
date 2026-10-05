# Contract: Admission answer

**Unit**: P3.4 · **Requirements**: FR-002, FR-004, FR-006, FR-009

Later units bind to this file for the DO admission result and for settlement by reservation id. Clinic HTTP denial bodies are [clinic-denial-codes.md](./clinic-denial-codes.md).

## 1. Admitted

`admissionRPC` returns this JSON when steps 5–7 admit. `GatewayObject.fetch` adds `contract_version` as it does today.

| Field | Value |
| --- | --- |
| `kind` | `admission` |
| `outcome` | `admitted` |
| `reservation_id` | The request id. Settlement and `usage_event.request_id` use this string. |
| `term_id` | The term the reservation is attributed to, including after that term has ended. |
| `snapshot` | `{capabilities, max_cost_class}` from `term.plan_snapshot`. `capabilities` is the JSON array of capability id strings. |
| `band` | `ok`, `75`, `90`, or `exhausted`. |

`term_id`, `reservation_id`, and `snapshot` stay inside the worker. They are not added to the clinic success body.

The pipeline passes `reservation_id` and `term_id` to `creditUsage`. A charge adds the reservation weight `w` to `hot.used`. A settlement that consumed nothing deletes the reservation and leaves `used` unchanged.

## 2. Replay

Step 1, for a `jti` or idempotency key that already has a stored answer, returns that answer and does not write. The stored answer is this admitted object, or one of the refusal outcomes below.

## 3. Refusals from the DO

| `outcome` | When | Clinic code |
| --- | --- | --- |
| `suspended` | `hot.suspended` is set | `suspended` |
| `allowance_exhausted` | No active or grace term, and the last term ended `exhausted` | `allowance_exhausted` |
| `coverage_lapsed` | No active or grace term for any other reason. Field `coverage_reason`: `none`, `expired`, `grace_exhausted`, `reversed`, `transferred`, or `transfer_pending` | `coverage_lapsed` |
| `forbidden_capability` | Capability not in the snapshot | `forbidden_capability` |
| `concurrency_limited` | In-flight reservations are at the snapshot `concurrency_limit`. Field `retry_after` is a positive integer | `concurrency_limited` |

Refusal order is the table order. A refusal does not write unless step 2 changed state.

## 4. Version rejection

When the DO JSON is `{result: "rejected", code: "contract_version_unsupported"}`, the clinic client receives `coverage_unknown`. Production admission still sends `contract_version` 1. This mapping is the only new handling of that existing refusal.

## 5. Settlement

`credit` takes `reservation_id`. If that id was already charged by step 2, the credit response is success and `hot` is unchanged. Step 2's outbox payload is `usage_adjustment` in [data-model.md](../data-model.md).
