# Data Model: Term boundaries, grace and renewal

**Unit**: P3.5 · **Requirements**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-010

No new table and no new column. The rows below are the existing per-clinic DO tables `term` and `hot`, plus the existing D1 table `coverage_mirror`.

## 1. Term boundary

The active term's `ends_at` is the next boundary. After grace starts, `grace_ends_at` is the next boundary. `hot.grace_base_used` and the grace allowance sit on that same term.

### 1.1 Columns this unit writes

| Column | When | Value |
| --- | --- | --- |
| `term.state` | End with a successor, grace end, or grace cap used | `ended` |
| `term.state` | `ends_at` due and no `queued` term | `grace` |
| `term.end_reason` | End with a successor, or `grace_ends_at` due | `expired` |
| `term.end_reason` | Grace allowance used | `grace_exhausted` |
| `term.end_reason` | Grant during grace | `renewed` |
| `term.starts_at`, `term.calendar_start` | Queued successor activates | The predecessor's `ends_at` |
| `term.ends_at` | Successor activates, or a grace grant opens the new term | `addDuration(calendar_start, duration_unit, duration_count, scale)` |
| `term.grace_ends_at` | Grace starts | `addDuration(ends_at, "day", grace_days, scale)` |
| `term.used_final` | Grace term ends `renewed` | `hot.used` at that moment, which includes grace usage |
| `hot.grace_base_used` | Grace starts | `hot.used` |
| `hot.grace_base_used` | Grace term ends | `0` |
| `hot.used` | Successor activates, or a grace grant opens the new term | `0` |
| `hot.active_term_id` | Successor or grace grant | The new term. Cleared when grace ends `expired` or `grace_exhausted` |
| `hot.next_alarm_at` | After every boundary and after the outbox ship | The earliest of the next `ends_at`, the next `grace_ends_at`, and the current instant when the outbox is non-empty |

`term.grace_cap` stays the text `proportional`. It is the cap rule stored at grant time. The numeric ceiling is not written there.

### 1.2 Grace allowance

Computed once when grace starts, in unscaled units.

- Term length in days is the UTC day count from `calendar_start` to `addDuration(calendar_start, duration_unit, duration_count)` with no scale. A monthly term from 1 Mar 10:00 to 1 Apr 10:00 is 31 days.
- `grace_cap` = ⌈`allowance` × `grace_days` ÷ term length in days⌉.
- Grace allowance = min(`allowance` − `grace_base_used`, `grace_cap`).
- Later admissions compare `hot.used + hot.reserved − grace_base_used` with that fixed allowance. They do not recompute the ceiling against the growing `used`.

`grace_days` is the integer already stored on the term. `coverClinic()` grants `7`. There is no second default.

The staging scale is applied only by `addDuration` when `durationScale` is `staging`. The credit ceiling stays a credit count. Production passes no scale.

### 1.3 Transitions

The loop applies the first matching row, then repeats until none match. Comparison uses `clockNowIso`. A `queued` term is the unheld successor. An `exhausted` term is not an active term and does not enter grace.

| Now | Term | Next |
| --- | --- | --- |
| `now >= ends_at` and a `queued` term exists | Active ends `expired` | Successor becomes `active` with a full allowance from the old `ends_at` |
| `now >= ends_at` and no `queued` term | Active becomes `grace` | `grace_ends_at`, `grace_base_used`, and the grace allowance are set |
| `now >= grace_ends_at` | Grace ends `expired` | Clinic snapshot is `lapsed`, reason `expired` |
| Reservation takes the last grace credit | Grace ends `grace_exhausted` | Clinic snapshot is `lapsed`, reason `grace_exhausted`. This is admission step 6, not the clock loop |

A grant while a grace term exists follows the existing `applyGrantRPC` branch: the new term is `active` immediately, its `calendar_start` is the grace term's `ends_at`, and the grace term ends `renewed`. A grant when nothing is active, in grace, or queued starts at `nowIso`, which is the payment time after lapse.

## 2. Clinic coverage snapshot

`buildCoverageSnapshot` already returns the frozen snapshot keys. This unit sets `state` and `reason` on that object. It does not add keys.

| Situation | `state` | `reason` | `term` |
| --- | --- | --- | --- |
| An active term exists | `active` | `none` | That active term |
| A grace term exists | `grace` | `none` | That grace term, including `grace_ends_at` |
| The last term ended `expired` or `grace_exhausted` and nothing is queued | `lapsed` | `expired` or `grace_exhausted` | `null` |

`validateCoverageSnapshot` already accepts `reason` `expired` and `grace_exhausted`. This unit does not change the package.

Each boundary event carries this snapshot after the change. `clinic_seq` increases by one per event. Kinds already defined for these changes are `term_activated`, `term_ended`, and `grace_started`. A successor end emits `term_ended` then `term_activated`. A grace start emits `grace_started`. A grace end emits `term_ended`.

## 3. `coverage_mirror.hard_stop_at`

The column already exists. The ship replaces a mirror row only when the new `(binding_epoch, clinic_seq)` is higher.

| Snapshot `state` | `hard_stop_at` |
| --- | --- |
| `active` | The active term's `ends_at` |
| `grace` | That term's `grace_ends_at` |
| `lapsed` | The value already stored on that installation's mirror row |

Fallback admission that reads this column is P3.9. This unit only writes it.
