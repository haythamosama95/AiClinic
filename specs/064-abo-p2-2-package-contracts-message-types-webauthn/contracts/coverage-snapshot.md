# Contract: Coverage snapshot

**Unit**: P2.2 · **Requirements**: FR-005

Later units bind to this file. The snapshot carries no prices, payment references, or provider ids.

## 1. Module

`packages/vendor-contracts/src/coverage-snapshot.ts`, re-exported from `src/index.ts`.

```ts
export function validateCoverageSnapshot(
  value: unknown,
): { ok: true } | { ok: false }
```

## 2. Fields

| Field | Rule |
| --- | --- |
| `contract_version` | Integer. Shape version of this snapshot |
| `state` | String. FR-005 cites 03 §5.7. This unit's Read list does not include that section, so this contract lists no state names |
| `reason` | Absent, or one of `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, `transfer_pending` |
| `suspended` | Boolean |
| `term` | `null`, or the object in section 3 |
| `queued_count` | Integer |
| `held_count` | Integer |
| `coverage_through` | String |
| `binding_epoch` | Integer |
| `clinic_seq` | Integer |

## 3. Term

`ref`, `plan_display_name`, `starts_at`, `ends_at`, and `grace_ends_at` are strings. `allowance` and `used` are integers. `band` is the string `ok`, `75`, `90`, or `exhausted`.

## 4. Vector

`packages/vendor-contracts/vectors/coverage-snapshot.json` holds one snapshot with a non-null `term`. E2E-P2.2-05 validates it in Node and in workerd, and uses that object as the feed event's `snapshot`.
