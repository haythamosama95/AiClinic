# Data Model: P3.8 Transfer, deletion with coverage left, and ledger retention

Entities from spec §3.2. Column lists are the amended 03 §3.2 rows this unit's Read line cites. No new entity.

## 1. `tenant_binding`

Existing D1 table (`ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql`). This unit does not add a column. The partial unique index `tenant_binding_one_live_org` already allows at most one row per `org_id` with `status` `active` or `held_for_transfer`.

| Column | Use in this unit |
| --- | --- |
| `org_id` | Transfer and delete are for this org only |
| `installation_id` | Source binding on `beginTransfer`; held or retired binding on `deleteInstallation` |
| `epoch` | First binding of an org is 1. Each re-creation is one greater. After a retire of epoch 1 the next token creates epoch 2 |
| `status` | `active`, `held_for_transfer`, or `retired` |
| `retired_at` | Set when this unit sets `retired` |
| `reason` | The call's `reason` when this unit retires the row |
| `created_at` | Insert time of a new binding. Unchanged on retire |

`beginTransfer` sets the source row to `retired` and inserts the next epoch as `active` on a new `installation_id`. `deleteInstallation` with an active, grace, queued, or held term sets the live row to `held_for_transfer`. `deleteInstallation` with no such term, and the last `voidGrant` that leaves a held binding with no not-ended term, set `retired`.

## 2. `installation`

Existing table. `status` already accepts `deleted`. This unit sets `deleted` from `deleteInstallation` and from `purgeByInstallationId`. The row is not removed.

## 3. `transfer`

New D1 table.

| Column | Notes |
| --- | --- |
| `transfer_id` | ULID (03 §7). Primary key. Returned inside the `beginTransfer` `detail` JSON |
| `org_id` | The call's `org_id` |
| `from_installation_id` | The source binding's installation |
| `to_installation_id` | The new binding created by `beginTransfer`. Set on insert |
| `reason` | The call's `reason` |
| `assertion_sha256` | The HP assertion challenge. A second `beginTransfer` with the same challenge returns this row and inserts nothing |
| `package` | JSON. Null until `transferOut`. Then a JSON array ordered by `position` |
| `created_at` | Insert time |

Package element, one per term that had not ended at `transferOut`:

`{origin_grant_id, position, state, plan_snapshot, allowance, duration_unit, duration_count, grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at}`

- `queued` or `held`: every field is the stored term.
- `active`: the stored term, except `allowance` is that term's `allowance` minus `hot.used`.
- `grace`: the stored term, except `allowance` is min(`allowance` − `grace_base_used`, `grace_cap`) − (`hot.used` − `grace_base_used`).
- Remaining days are the unelapsed time until the stored `ends_at` (`active`) or `grace_ends_at` (`grace`). Those timestamps stay the stored values. There is no extra field.

## 4. `transfer_step`

New D1 table.

| Column | Notes |
| --- | --- |
| `transfer_id` | The authorised row |
| `step` | `transfer_out` or `transfer_in` |
| `receipt` | The §1.6 transfer receipt JSON |
| `applied_at` | The time that step first returned `applied` |

Unique on (`transfer_id`, `step`). A row is inserted only when that step returns `applied`. A retry reads this row and returns `already_applied` with that receipt.

## 5. Transfer receipt

The §1.6 object. `transferOut` and `transferIn` include it when `result` is `applied` or `already_applied`. `beginTransfer` and `deleteInstallation` do not.

| Member | Transfer step |
| --- | --- |
| `transfer_id` | The id member. Not `grant_id` or `reversal_id` |
| `installation_id` | The installation that step wrote |
| `org_id` | The transfer's org |
| `result` | `applied` |
| `term_ids` | Terms that step ended (`transferOut`) or created (`transferIn`) |
| `applied_at` | That step's time |
| `ledger_seq` | `clinic_seq` of the `coverage_event` with `kind` `transfer` that step wrote |
| `envelope_sha256` | SHA-256 of the RFC 8785 canonical package |
| `kid`, `signature` | Platform key, same compact JWS as a grant receipt |

## 6. DO flags and terms

Existing `hot` columns. This unit writes them.

| Flag | Who sets it |
| --- | --- |
| `awaiting_transfer` | `beginTransfer` on the new DO. Cleared when `transferIn` returns `applied` |
| `transfer_pending` | `deleteInstallation` when coverage is left |
| `transferred_out_to` | `transferOut`, the new installation id |
| `binding_epoch` | The new DO starts at the new binding's epoch |

`transferOut` sets every not-ended `term` to `ended` with `end_reason` `transferred`. `transferIn` inserts terms on the new DO with the package's `origin_grant_id`, `state`, and `allowance`. New `term_id` values are new. `grant_id` for each inserted term is SHA-256 over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n, where n is that element's index in position order. The outbox ships a `grant_ledger` row for each, `source_kind` `transfer`, `origin_grant_id` from the package, `installation_id` the new installation. `grant_ledger` stays append-only.

## 7. Rows purge keeps

`purgeByInstallationId` marks `installation.status` `deleted` and does not delete the row. It does not delete `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, `transfer_step`, `tenant_binding`, or `entitlement`. It does not delete or update DO `term` or `grant` rows. It may delete `usage_event` rows except those whose `term_id` is a term that has not ended.
