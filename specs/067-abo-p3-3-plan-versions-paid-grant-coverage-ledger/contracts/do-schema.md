# Contract: DO schema and Worker to DO version

**Unit**: P3.3 · **Requirements**: FR-001, FR-002, FR-003

Later units bind to this file for the per-clinic tables and for the `platformDo` version check. Column lists are in [data-model.md](../data-model.md).

## 1. Version check

`GatewayObject.fetch` reads `contract_version` from the JSON body. It calls `negotiate(CHANNEL_VERSIONS.platformDo, requested)` before any storage read or write, including `CREATE TABLE`.

`CHANNEL_VERSIONS.platformDo` is 1. Accepted versions are `[0, 1]`.

| Call | Answer |
| --- | --- |
| `contract_version` 1, or 0 | The existing kind runs. The JSON answer includes `contract_version` set to the version the call sent. |
| Missing, or any other integer, including 2 | HTTP 200 JSON `{contract_version: 1, result: "rejected", code: "contract_version_unsupported", accepted_versions: [0, 1]}`. No blob write and no SQL. |

`contract_version` on a refusal is the current channel version, 1. An accepted call echoes the version it sent.

Existing kinds `admission`, `credit`, `release`, and `inspect` keep their current JSON fields and gain `contract_version`. Their outcomes stay as they are.

## 2. Tables

After the check succeeds, `CREATE TABLE IF NOT EXISTS` creates `hot`, `term`, `grant`, and `outbox` inside `blockConcurrencyWhile`. The blob key `state` is not deleted and is not rewritten by that migration.

## 3. Kinds this unit adds

| `kind` | Who calls it | Effect |
| --- | --- | --- |
| `apply_grant` | `VendorEntrypoint.grant` after the paid checks and the binding resolve | Places the term or returns the idempotent result. See [grant-paid.md](./grant-paid.md). |
| `read_coverage` | `VendorEntrypoint.getCoverage` | Reads `hot` and `term`. See [get-coverage.md](./get-coverage.md). |

Both bodies include `contract_version`.

## 4. Alarm

`GatewayObject.alarm` ships due outbox rows. `setAlarm` is called only when the new alarm time differs from `hot.next_alarm_at`. The time is the earlier of the pending-outbox instant (the platform clock now) and the next `ends_at` or `grace_ends_at` on an `active` or `grace` term. `hot.next_alarm_at` stores that time.
