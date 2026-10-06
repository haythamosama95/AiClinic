# Data Model: Fallback admission, coverage feed and administrator coverage read

**Unit**: P3.9 · **Requirements**: FR-001, FR-003, FR-005, FR-007

D1 only. The clinic DO tables are unchanged. `coverage_mirror` is read and not written by this unit's admission path.

## 1. `fallback_admission`

Replaces `grace_admission_queue`. The migration drops that table after creating this one. There is no data to copy.

### 1.1 Columns

| Column | Type | Rule |
| --- | --- | --- |
| `installation_id` | TEXT NOT NULL | Clinic whose DO was unreachable. References `installation`. |
| `idempotency_key` | TEXT NOT NULL | The request's idempotency key. |
| `term_id` | TEXT NOT NULL | `term_snapshot.ref` from the mirror row read for this admission. |
| `request_id` | TEXT NOT NULL | Allocated before the DO call. The DO reservation uses this id when the body carries it. |
| `weight` | INTEGER NOT NULL | This request's quota weight `w`. |
| `admitted_at` | TEXT NOT NULL | `clockNowIso` at insert. |
| `state` | TEXT NOT NULL | `pending` or `settled`. |

Primary key is (`installation_id`, `idempotency_key`). A second insert for the same pair does not add a row.

`CREATE INDEX` on `state`. `CREATE UNIQUE INDEX` on `request_id`.

`state` stays `pending` until the drain charges the row. A row the DO still holds is left `pending`. A charged row becomes `settled`.

## 2. `feed_consumer`

One row per consumer. This unit writes the consumer `backend-feed`.

| Column | Type | Rule |
| --- | --- | --- |
| `consumer` | TEXT PRIMARY KEY | `backend-feed`. |
| `last_pull_at` | TEXT | UTC ISO-8601 from `clockNowIso` on a successful feed pull. Null before the first pull. |
| `last_cursor` | INTEGER | `next_after` from that pull. Null before the first pull. |

A refused version and a refused token do not insert or update the row. `feedConsumerHealth` reads these two values and does not write.

## 3. `coverage_mirror` (read)

Existing table. Primary key `installation_id`. This unit's admission path reads one row and does not use the config cache.

| Column | Use |
| --- | --- |
| `state` | Must be `active` or `grace`. Any other value, including `lapsed`, refuses. |
| `suspended` | Integer. `0` is not suspended. Any other value refuses. |
| `hard_stop_at` | Admit only when `clockNowIso` is strictly before this text. Null or a clock at or after it refuses. |
| `term_snapshot` | JSON term object. `ref` is `term_id`. `capabilities` is the string array the request capability must belong to. |

The snapshot fields `state` `grace` and `lapsed`, and reasons `expired` and `grace_exhausted`, stay the values `buildCoverageSnapshot` already stores. This unit does not write them.
