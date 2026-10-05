# Contract: Coverage events, ledger ship, and grant alerts

**Unit**: P3.3 · **Requirements**: FR-011, FR-012, FR-013

Later units bind to this file for the paid-grant outbox and the alarm ship. The event object stays the P2.2 feed-event contract. `kind` values for a paid grant are the ones below.

## 1. Outbox written on apply

For one new paid grant, in this order, skipping any event the placement does not emit:

| Order | Outbox `kind` | Payload |
| --- | --- | --- |
| 1 | `coverage_event` | The `term_ended` event, when placement ends the grace term |
| 2 | `coverage_event` | The `term_activated` event, when the new term is `active` |
| 3 | `coverage_event` | The `grant_applied` event |
| 4 | `grant_ledger` | The ledger row, including the receipt |
| 5 | `alert` | AL-11 |
| 6 | `alert` | AL-17, only when the velocity condition holds |

A grant that only queues writes `grant_applied` and no `term_activated` or `term_ended`.

Each event's `clinic_seq` is the next `hot.clinic_seq`. `event_id` is `coverageEventId(installation_id, clinic_seq)`. `at` is the grant's UTC ISO-8601 time. `snapshot` is the post-grant snapshot, and that snapshot's `clinic_seq` equals the event's `clinic_seq`. `binding_epoch` is `hot.binding_epoch`.

`ledger_seq` on the receipt is the `clinic_seq` of the `grant_applied` event. The platform assigns those `clinic_seq` values in the event order above, signs the receipt with the `grant_applied` value, then inserts the outbox rows.

## 2. Alarm ship

For each outbox row, in `seq` order:

| `kind` | D1 or R2 |
| --- | --- |
| `coverage_event` | `INSERT OR IGNORE` into `coverage_event` on `event_id`. Then replace `coverage_mirror` only when `(binding_epoch, clinic_seq)` is higher than the stored pair, or the mirror row is absent. |
| `grant_ledger` | `INSERT OR IGNORE` on `grant_id`. Then write R2 `grant-ledger/<grant_id>.ndjson` only when that key is absent. |
| `alert` | Raise the alert in section 3. |

Then delete the shipped outbox rows. This unit does not insert `usage_adjustment` or a void row.

## 3. Alerts

Email is the body handed to `send_email`. `subject` is the code.

### 3.1 AL-11

Alert key `AL-11:<grant_id>`. Raised once per grant. Body:

`{"code":"AL-11","org_id":"<org_id>","operation":{"op":"grant","params":"<envelope>"}}`

`operation.params` is the grant envelope object, not a string. `org_id` is the envelope's `org_id`. A resend does not enqueue a second AL-11 row. Unsent retry sends the same body. A sent row is not sent again.

### 3.2 AL-17

The grant is still `applied`.

| Condition | Alert key | Body |
| --- | --- | --- |
| The DO has more than 3 `source_kind` `paid` grants for this clinic with `applied_at` in the last 24 hours of the platform clock. The fourth grant is that condition. | `AL-17:clinic:<org_id>` | `{"code":"AL-17","org_id":"<org_id>"}` |
| `grant_ledger` has more than 20 `source_kind` `paid` rows with `applied_at` in the last hour, counting the rows this alarm is inserting. | `AL-17:global` | `{"code":"AL-17"}` |

`next_send_at` is one hour after the send. `runFiveMinuteCron` loads a due AL-17 whose `resolved_at` is null. If the same condition still holds, it sends the same body and moves `next_send_at` forward one hour. If the condition is gone, it sets `resolved_at` and does not send. The AL-20 query and body stay as they are.
