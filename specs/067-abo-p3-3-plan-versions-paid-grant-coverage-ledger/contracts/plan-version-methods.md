# Contract: Plan-version methods

**Unit**: P3.3 · **Requirements**: FR-006, FR-015

Later units bind to this file for `publishPlanVersion` and `retirePlanVersion`. The result is the envelope `{contract_version, result, code, detail}` with no extra key. These methods do not record a grant or a reversal. `receipt` is absent. They do not return `applied` or `already_applied`. They do not raise an alert.

Both methods are class HP and use the existing Access JWT and WebAuthn assertion checks. `contract_version` is checked first, before authentication and before any write.

## 1. `publishPlanVersion` (HP)

Input beyond `contract_version`, `access_jwt`, and `assertion`: `plan_id`, `version`, `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, `max_allowance_per_month`.

`capabilities` is a JSON array of capability id strings. Inserted `status` is `published`. `published_by` is the Access email. `assertion_sha256` is the assertion challenge hash. Content fields are immutable once published.

| `result` | `code` | `detail` | When |
| --- | --- | --- | --- |
| `ok` | `""` | JSON text of the `plan_version` row | Insert, or the same `(plan_id, version)` already stored with the same content fields. A same-content replay does not insert another row and does not change `status` or those fields. |
| `conflict` | `plan_version_mismatch` | `""` | That pair is stored with a different value in any content field. The stored row is unchanged. |

Content fields compared on replay: `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, `max_allowance_per_month`.

Row JSON keys, in this order: `plan_id`, `version`, `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, `max_allowance_per_month`, `status`, `published_by`, `assertion_sha256`. `capabilities` in that JSON is the array, not a stringified string inside a string.

## 2. `retirePlanVersion` (HP)

Input beyond `contract_version`, `access_jwt`, and `assertion`: `plan_id`, `version`. This is the only writer of `retired`.

| `result` | `code` | `detail` | When |
| --- | --- | --- | --- |
| `ok` | `""` | JSON text of the `plan_version` row | `status` moves from `published` to `retired`, or it is already `retired`. Content fields stay as published. |
| `rejected` | `plan_version_not_found` | `""` | No row for `(plan_id, version)`. |

A later paid grant that names a `retired` version is `plan_not_published` (`contracts/grant-paid.md`). The term already placed keeps the `plan_snapshot` it stored.
