# Contract: Feed event

**Unit**: P2.2 · **Requirements**: FR-006

Later units bind to this file. The defining sentence is: each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`.

## 1. Module

`packages/vendor-contracts/src/feed-event.ts`, re-exported from `src/index.ts`.

```ts
export function validateFeedEvent(
  value: unknown,
): { ok: true } | { ok: false }
```

## 2. Fields

| Field | Rule |
| --- | --- |
| `event_id` | String. Tests set it with the consumed `coverageEventId(installationId, clinicSeq)` |
| `feed_seq` | Integer |
| `org_id` | String, UUID `8-4-4-4-12` lowercase hex |
| `installation_id` | String, UUID `8-4-4-4-12` lowercase hex |
| `binding_epoch` | Integer |
| `clinic_seq` | Integer |
| `kind` | String. The defining sentence does not enumerate values, and this contract adds none |
| `at` | String |
| `snapshot` | Passes `validateCoverageSnapshot` |

## 3. Vector

`packages/vendor-contracts/vectors/feed-event.json` holds one event whose `snapshot` is the coverage-snapshot vector and whose `kind` is the string `sample`. That value is one accepted string, not a closed set. E2E-P2.2-05 validates the event in Node and in workerd, and also validates the same validator with `kind` set to a second string.
