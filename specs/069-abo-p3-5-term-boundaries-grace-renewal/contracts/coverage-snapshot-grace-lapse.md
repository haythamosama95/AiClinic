# Contract: Grace and lapse in the coverage snapshot

**Unit**: P3.5 · **Requirements**: FR-003, FR-004, FR-005, FR-010

Later units read `state` and `reason` from this slice. The admission answer and the clinic denial codes stay the P3.4 contracts. This file does not add snapshot keys. `packages/vendor-contracts` `validateCoverageSnapshot` already allows `reason` `expired` and `grace_exhausted`.

## 1. States

| `state` | Meaning |
| --- | --- |
| `grace` | The last term passed `ends_at` and grace is running. `reason` is `none`. `term` is that grace term. |
| `lapsed` | Grace ended at `grace_ends_at`, or the grace allowance was used, and nothing is queued. `term` is null. |

`active` is unchanged: an active term is present and `reason` is `none`.

## 2. Reasons

On a `lapsed` snapshot, `reason` is one of:

| `reason` | `term.end_reason` that produced it |
| --- | --- |
| `expired` | `grace_ends_at` was reached |
| `grace_exhausted` | A reservation took the last of the grace allowance |

The matching clinic denial is the existing `coverage_lapsed` body with the same `coverage_reason`. No new HTTP code is defined here.

## 3. Term object during grace

`term` uses the existing term keys. While `state` is `grace`, `grace_ends_at` is the instant grace ends and `ends_at` remains the term's original end. `used` is the hot-row usage, including credits taken during grace.

## 4. Mirror `hard_stop_at`

When the alarm ships a snapshot, `coverage_mirror.hard_stop_at` is `term.ends_at` if `state` is `active`, and `term.grace_ends_at` if `state` is `grace`. A higher `(binding_epoch, clinic_seq)` is the only replace. A `lapsed` snapshot does not clear a `hard_stop_at` already stored for that installation.
