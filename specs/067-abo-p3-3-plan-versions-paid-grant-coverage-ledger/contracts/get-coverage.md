# Contract: getCoverage

**Unit**: P3.3 · **Requirements**: FR-014

Later units bind to this file for `getCoverage`. The snapshot field rules stay `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/coverage-snapshot.md`.

## 1. Call

Class M. Argument `{contract_version, org_id}`. `contract_version` is checked first. No Access JWT and no assertion. `receipt` is absent on `ok`.

The worker resolves the active binding for `org_id` and calls DO kind `read_coverage`. It does not read `coverage_mirror` for this method.

## 2. Success

`result` is `ok`, `code` is `""`, `receipt` is absent. `detail` is the JSON text of `{snapshot, queued_terms, recent_terms}`.

`snapshot` carries `contract_version`, `state`, `reason`, `suspended`, `term`, `queued_count`, `held_count`, `coverage_through`, `binding_epoch`, and `clinic_seq`. It has no prices, payment references, or provider ids.

For a clinic this unit has placed:

| Field | Value |
| --- | --- |
| `state` | `active` when an active term exists |
| `reason` | `none` |
| `suspended` | false |
| `term` | Null when no active term. Otherwise `{ref, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, band}` with `ref` = `term_id`, `band` `ok`, and `used` = `hot.used` when the term is `hot.active_term_id`, else `used_final` |
| `queued_count` | Count of unheld terms in `queued` |
| `held_count` | 0 |
| `coverage_through` | Projected end from [data-model.md](../data-model.md) section 5 |
| `binding_epoch`, `clinic_seq` | The `hot` row |

`queued_terms` are unheld `queued` terms in ascending `position`. Each is `{plan_id, plan_version, plan_display_name, duration_unit, duration_count}` and has no dates.

`recent_terms` are at most the last 12 terms whose state is `active`, `grace`, or `ended`, highest `position` first. Fewer than 12 returns those that exist. Each is `{term_id, state, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used}`.

A second paid grant leaves `queued_count` 1 and a `coverage_through` later than the active term's `ends_at`.
