# Data Model: Complimentary grants, ceilings, term adjustments and suspension

**Unit**: P3.6 · **Requirements**: FR-003, FR-007, FR-008, FR-011

## 1. `ceiling_policy`

New platform D1 table. One row per version. The greatest `version` is the policy in force.

### 1.1 Columns

| Column | Type | Value |
| --- | --- | --- |
| `version` | integer primary key | 1 for the migration seed, then one greater for each `setCeilingPolicy` insert |
| `per_grant_max_days` | integer | Launch 31 |
| `per_grant_max_allowance_months` | integer | Launch 1 |
| `window_days` | integer | Launch 90 |
| `window_max_days` | integer | Launch 62 |
| `window_max_allowance_months` | integer | Launch 2 |
| `max_paid_grace_days` | integer | Launch 7 |
| `paid_cap_rule` | text | Launch `proportional` |
| `set_by` | text | Access email on a `setCeilingPolicy` insert. The seed stores `''` |
| `assertion_sha256` | text | Assertion challenge hash on a `setCeilingPolicy` insert. The seed stores `''` |

The seed row is version 1. `setCeilingPolicy` does not update it. A repeated assertion challenge returns the row that already stores that hash and does not insert.

### 1.2 Day and allowance figures

A complimentary `duration` of `day` contributes `count` days. A `month` contributes `count × 31` days. Both figures apply to the per-grant day ceiling and to the window day ceiling. `ends_at` is still `addDuration` and is not the ceiling figure.

Allowance is counted in months of that grant's published plan `max_allowance_per_month`. The integer check is `allowance_credits ≤ per_grant_max_allowance_months × max_allowance_per_month` for one grant. In the window, complimentary `allowance_credits` plus `term_adjustment.add_allowance` must be `≤ window_max_allowance_months ×` the plan max used for the grant being checked.

Paid `grace.days` must be `≤ max_paid_grace_days` and `grace.cap_rule` must equal `paid_cap_rule`. That check is the existing paid grant path. It does not apply to complimentary grace.

## 2. Window rows

The window is anchored at the grant being checked. Its `applied_at` is the time of the check. The span is `window_days × 24` hours ending at that instant. A DO `grant` row for that clinic counts when its `applied_at` is greater than this instant minus the span and less than or equal to this instant.

The row that is being inserted is included in the sum even though it is not stored yet. Earlier rows come from the DO `grant` table:

| `kind` / `source_kind` | Days added | Allowance credits added |
| --- | --- | --- |
| `term` / `complimentary` | `count`, or `count × 31` when the unit is `month` | `allowance_credits` |
| `term_adjustment` / `complimentary` | `adjustment.extend_days` when it is a positive integer, otherwise 0 | `adjustment.add_allowance` when it is a positive integer, otherwise 0 |

Paid `term` rows are not in the sum. `grant_ledger` is not the input. It does not store duration or `extend_days`.

## 3. Complimentary term

A passing complimentary `term` grant inserts one DO `term` and one DO `grant`. `grant.kind` is `term`. `grant.source_kind` is `complimentary`. The envelope and evidence are stored on the grant row. Placement follows the existing rule: `active` when no active, grace, or unheld queued term exists, otherwise `queued`. A queued row stores the duration and leaves `calendar_start`, `starts_at`, and `ends_at` null. An active `day` term sets `ends_at` with `addDuration` of exact 24-hour steps.

## 4. `term_adjustment`

`grant.kind` is `term_adjustment` and `grant.source_kind` is `complimentary`. The grant does not insert a term. It updates the active term only.

| Field | Write |
| --- | --- |
| `extend_days` > 0 | `ends_at = addDuration(ends_at, "day", extend_days, scale)` |
| `extend_days` that would move `ends_at` earlier | no write |
| `add_allowance` | added to `term.allowance` |
| `plan` | `plan_snapshot` replaced from the published `plan_version`, including `capabilities` |

Queued terms are not updated. The following `grant_applied` outbox event ships the coverage mirror. `coverage_mirror.term_snapshot` is the snapshot `term` object, whose `capabilities` come from `plan_snapshot`. `GET /v1/capabilities` already reads that column.

## 5. Suspension flag

`hot.suspended` is the existing integer. `suspend` sets it to 1. `resume` sets it to 0. No new column. The snapshot `suspended` boolean is already derived from this flag. Admission already returns `suspended` before later refusal codes, and the boundary loop already runs before that check, so a term can enter grace while the flag is set.
