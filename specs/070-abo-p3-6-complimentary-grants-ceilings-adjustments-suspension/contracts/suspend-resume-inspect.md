# Contract: Suspend, resume, and inspectCoverage

**Unit**: P3.6 · **Requirements**: FR-008, FR-010

Later units call these three class-H methods. Each takes `access_jwt`. A missing Access JWT is `rejected` with code `unauthenticated`. `code` is empty and `receipt` is absent on `ok`.

## 1. `suspend` and `resume`

Input beyond `contract_version` and `access_jwt` is `org_id` and `reason`. `result` is `ok`. `detail` is the JSON text of the coverage snapshot `buildCoverageSnapshot` already returns, including `suspended`.

`suspend` sets the clinic DO flag. `resume` clears it. A second call that finds the flag already in the target state is `ok` and does not raise another alert. The snapshot states `grace` and `lapsed`, and the reasons `expired` and `grace_exhausted`, stay the P3.5 contract.

While the flag is set, `POST /v1/requests` is 403 with body code `suspended`, before any later refusal. The term calendar still runs: a due `ends_at` can enter grace, and that POST remains 403 `suspended`. After `resume`, a clinic that still has coverage is admitted (HTTP 200).

## 2. Alerts

The first suspend raises one AL-19. The first resume raises one AL-19. The captured body is `{ code: "AL-19", org_id, operation: { op, params: { org_id, reason } } }` with `op` `suspend` or `resume`. Kill-switch changes stay with P3.10.

## 3. `inspectCoverage`

Input beyond `contract_version` and `access_jwt` is `org_id`. `detail` is the JSON text of `{ terms, grants, reservations }`.

| Key | Rows |
| --- | --- |
| `terms` | DO `term` rows for that clinic |
| `grants` | DO `grant` rows for that clinic |
| `reservations` | Parsed `hot.reservations` |

The existing DO quota inspect stays a different call. This method does not return the D1 mirror.
