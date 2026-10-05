# Data Model: Admission and settlement against terms

**Unit**: P3.4 · **Spec**: [spec.md](./spec.md)

The DO tables `hot`, `term`, `grant`, and `outbox` already exist. This unit does not add a table. It writes the admission fields on `hot` and appends `outbox` rows.

## 1. `hot`

One row per clinic. Admission and settlement update it inside `blockConcurrencyWhile`.

| Field | Use on this path |
| --- | --- |
| `suspended` | Read at step 4. This unit does not set it. |
| `transferred_out_to`, `awaiting_transfer`, `transfer_pending` | Present on the row. Transfer behaviour stays later. |
| `active_term_id` | The term step 5 reserves against. Step 6 moves it to the successor or clears it. |
| `used` | Increases by `w` when settlement charges. Unchanged when a reservation is released. |
| `reserved` | Sum of open reservation weights. |
| `grace_base_used` | Left as stored. Grace transitions are P3.5. |
| `reservations` | JSON array, at most 16 objects `{id, weight, term_id, capability, admitted_at}`. `id` is the request id. `admitted_at` is milliseconds from `clockNowMs`. |
| `replay` | JSON object keyed by `jti`. Values are stored admission answers. Swept on each write. Kept at least `EPHEMERAL_HORIZON_MS` (2 hours). |
| `idempotency` | JSON object keyed by idempotency key. Same sweep and horizon as `replay`. |
| `band_emitted` | JSON object. Keys `75` and `90` are present once that band has emitted. |
| `binding_epoch`, `clinic_seq`, `next_alarm_at` | Unchanged by admission except when a new outbox row needs the existing alarm. |

The JSON blob key `state` is removed. `maybeResetPeriod` and `isQuotaExhausted` are removed.

## 2. Admission answer

Returned by step 7 and stored for replay. Field list: [contracts/admission-answer.md](./contracts/admission-answer.md).

`reservation_id` is the request id. `term_id` is the term the reservation is charged to. `snapshot` is `{capabilities, max_cost_class}` copied from `term.plan_snapshot`. `band` is `ok`, `75`, `90`, or `exhausted`.

## 3. `usage_event`

D1 journal. Migration `ai-platform/migrations/20261006120000_usage_term.sql` rebuilds the table. Existing rows copy `period` into `term_id`. `request_id` stays nullable so retention can clear it. A unique index on `request_id` makes non-null ids insert-or-ignore.

| Column | Notes |
| --- | --- |
| `usage_event_id` | TEXT primary key |
| `installation_id` | TEXT NOT NULL, foreign key to `installation` |
| `term_id` | TEXT NOT NULL. Replaces `period`. |
| `request_id` | TEXT, unique. Foreign key to `ai_request` ON DELETE SET NULL, as in `20260805120000_f3_retention_indexes.sql`. |
| `quota_weight` | INTEGER NOT NULL |
| `tokens` | INTEGER NOT NULL |
| `cost` | REAL NOT NULL |
| `recorded_at` | TEXT NOT NULL |

Keep `idx_usage_event_installation_id`. The unique index replaces the non-unique `idx_usage_event_request_id`. Keep the `ai_attempt` and `ai_request` indexes from that migration file.

The journal insert is `INSERT OR IGNORE`.

## 4. `usage_rollup`

Dimensions JSON is `{installation_id, term_id}`. The migration deletes existing rollup rows and replaces `idx_usage_rollup_period` with an index on `json_extract(dimensions, '$.term_id')`. `quota_weight` stays.

## 5. `usage_adjustment`

Outbox row. `kind` is `usage_adjustment`. `payload` is `{request_id, installation_id, term_id, quota_weight, tokens, cost, recorded_at}`. Step 2 sets `tokens` and `cost` to 0 because the provider has not reported usage. The existing alarm inserts that payload into `usage_event` with `INSERT OR IGNORE` on `request_id`, then deletes the outbox row.

## 6. Band event

Outbox `kind` `coverage_event`, payload `kind` `band_crossed`. The snapshot is the existing coverage snapshot. `term.band` is `75` or `90`. `buildCoverageSnapshot` sets `band` from `used / allowance`: `ok` below 0.75, `75` from 0.75 and below 0.90, `90` at or above 0.90, `exhausted` when the active term has ended `exhausted`. A fresh grant with `used` 0 stays `ok`.
