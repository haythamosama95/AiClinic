# Contract: Ceiling policy

**Unit**: P3.6 · **Requirements**: FR-003, FR-004, FR-005, FR-011

Later units read the greatest `ceiling_policy.version` and call `setCeilingPolicy`. Launch numbers are the seed row. A 30-day `day` grant is inside the per-grant day ceiling. A 365-day grant is not.

## 1. `setCeilingPolicy`

Class HP. Input beyond `contract_version` and the Access JWT is `per_grant_max_days`, `per_grant_max_allowance_months`, `window_days`, `window_max_days`, `window_max_allowance_months`, `max_paid_grace_days`, and `paid_cap_rule`.

On `ok`, the method inserts the next `version`, sets `set_by` to the Access email, sets `assertion_sha256` to the assertion challenge hash, and stores those seven fields. `detail` is the JSON text of that row. `detail.version` is the policy version. `code` is empty. `receipt` is absent. `result` is `ok`.

The same assertion challenge returns `ok` with the existing row and does not insert another row.

## 2. Checks

The policy in force is the greatest `version`.

| Check | Pass |
| --- | --- |
| Per complimentary grant, days | `day` count, or `month` count × 31, ≤ `per_grant_max_days` |
| Per complimentary grant, allowance | `allowance_credits` ≤ `per_grant_max_allowance_months` × the plan's `max_allowance_per_month` |
| Per clinic, days in the window | Sum of those day figures and of `extend_days` ≤ `window_max_days` |
| Per clinic, allowance in the window | Sum of complimentary `allowance_credits` and `add_allowance` ≤ `window_max_allowance_months` × the plan max used for the grant being checked |
| Paid grace | `grace.days` ≤ `max_paid_grace_days` and `grace.cap_rule` = `paid_cap_rule`, otherwise the existing `exceeds_plan_bound` |

The window ends at this grant's `applied_at` and lasts `window_days` × 24 hours. Failure of a complimentary check is `rejected` with code `exceeds_ceiling`, unless a valid `ceiling_override` is attached.

Launch figures are 31, 1, 90, 62, 2, 7, and `proportional`. Two grants of 31 days fit the day window. One more day does not.
