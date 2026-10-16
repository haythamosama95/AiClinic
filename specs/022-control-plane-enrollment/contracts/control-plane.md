# Contract: Control-plane installation lifecycle (B2)

**Frozen by:** Slice B2 — Control-plane enrollment and installation lifecycle
**Implements:** §4.5, §8.1 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices **B3** (guard), **J3** (control_audit activations), and **F3**
(installation purge by lifecycle status) **consume** this contract; the no-rework rule applies
(Delivery Plan §2.3). A later slice may **extend** (e.g. J3 adds further `control_audit.action`
values for routing-policy activations) but may not **rewrite** anything below.

**Source of truth in code:** sibling modules under `ai-platform/src/control/` with barrel
`index.ts` — `types`, `http`, `auth` (`createSecretOperatorAuth`), `audit` (`writeAudit` for
non-batched token-contract), `lifecycle` (five handlers; audit inlined in D1 batch),
`capability-lifecycle`, `cohort`, `routing-policy`, `token-contract`, `support-purge`, and
`dispatchControlRequest` / `isControlRoute` on the barrel; `ai-platform/src/worker.ts`
(`/control` route dispatch wires Env → `createSecretOperatorAuth`).

---

## 1. Overview

The control plane is a small internal HTTP surface on the AI gateway Worker, separate from the
client-facing API (`POST /v1/requests`, `/health`). It is authenticated by **operator identity,
not clinic identity** (§4.5). Every mutation writes a `control_audit` row carrying the operator
identity (§4.5; §8.1).

B2 freezes the `/control` route shape, the five lifecycle `control_audit.action` values, the
operator-auth requirement, the `pending` enroll entitlement initial snapshot (§8.1 amendment), the
entitlement status enum (§7.3 amendment), and the key-rotation overlap invariant (§8.1).

---

## 2. HTTP surface

All routes are `POST` only. The Worker dispatches matching paths to `dispatchControlRequest` in
`src/control/`; all other paths on the Worker are unchanged.

| Route | Handler | D1 writes |
| --- | --- | --- |
| `POST /control/installations/{installation_id}/enroll` | `handleEnroll` | `installation`, `installation_key`, `entitlement`, `control_audit` |
| `POST /control/installations/{installation_id}/rotate` | `handleRotate` | `installation_key` (new row), `control_audit` |
| `POST /control/installations/{installation_id}/suspend` | `handleSuspend` | `installation` (status), `control_audit` |
| `POST /control/installations/{installation_id}/resume` | `handleResume` | `installation` (status), `control_audit` |
| `POST /control/installations/{installation_id}/delete` | `handleDelete` | `installation` (status), `control_audit` |

`{installation_id}` is the platform-assigned installation identifier supplied in the URL path.

### 2.1 Enroll request body

| Field | Required | Purpose |
| --- | --- | --- |
| `installation_id` | yes (path) | Canonical UUID — same value as clinic `installation_id` / AAT `iss` |
| `org_id` | yes | Canonical UUID — clinic `organizations.id` |
| `display_name` | yes | Human-readable installation label |
| `region` | yes | Deployment region |
| `plan` | yes | Closed tier: `starter`, `standard`, `professional`, or `enterprise` |
| `public_key` | yes | Base64url encoding of a 32-byte Ed25519 public key (Stage 2 `public_jwk.x`) |
| `algorithm` | yes | Must be `EdDSA` |
| `kid` | yes | Canonical UUID — Stage 2 `kid` → `installation_key.key_id` |

### 2.2 Enroll success response

HTTP `200` with JSON body:

```json
{ "platform_base_url": "<gateway origin>" }
```

`platform_base_url` is the Worker's own origin, derived from the request URL (§8.1 "enrollment
confirmed + platform base URL"). The same Worker serves `/control` and `/v1/requests`.

### 2.3 Rotate request body

| Field | Required | Purpose |
| --- | --- | --- |
| `kid` | yes | New key identifier |
| `public_key` | yes | New clinic public key |
| `algorithm` | yes | Key algorithm — must be `EdDSA` |

Suspend, resume, and delete accept an empty JSON object `{}`.

### 2.4 Rejection responses (non-§5.4)

The control plane does **not** emit §5.4 taxonomy codes (spec Edge Cases). Rejections use simple
JSON `{"error": "<reason>"}` with a terminal HTTP status:

| Condition | Status | `error` value |
| --- | --- | --- |
| Missing or invalid operator credentials | `401` | `unauthorized` |
| Malformed JSON body | `400` | `invalid_json` |
| Required enroll/rotate field missing or empty, unknown `plan`, unsupported `algorithm`, non-UUID `installation_id`/`org_id`/`kid`, or invalid `public_key` | `400` | `invalid_payload` |
| Route does not match expected pattern | `400` | `invalid_route` |
| Duplicate enroll (existing `installation_id` or `org_id`) | `409` | `already_enrolled` |
| Illegal lifecycle transition (e.g. mutate `deleted`, resume non-`suspended`, re-suspend) | `409` | `illegal_lifecycle_transition` |
| Rotate/`kid` already present (or UNIQUE on `installation_key`) | `409` | `duplicate_kid` |
| Installation not found (lifecycle mutations) | `404` | `installation_not_found` |
| Non-UNIQUE D1 / storage failure | `500` | `storage_error` |

---

## 3. Operator authentication requirement

Every lifecycle mutation **MUST** consult an `OperatorAuth` port before any D1 write (FR-001,
FR-009). The port resolves an operator principal from the incoming `Request` or returns `null`:

```typescript
type OperatorAuth = {
  resolve(request: Request): OperatorPrincipal | null;
};

type OperatorPrincipal = {
  operatorId: string;
};
```

When `resolve` returns `null`, the handler **MUST** return a terminal rejection (`401
unauthorized`) and **MUST NOT** write any D1 row.

Production auth is `createSecretOperatorAuth({ bearerToken, operatorId })` (`src/control/auth.ts`):
timing-safe compare of `Authorization: Bearer <token>` against the configured secret; on match,
return the configured stable `operatorId` — **never** the bearer credential. Fail-closed: empty
`bearerToken` or empty `operatorId` → `resolve` returns `null`.

The Worker wires this from Env bindings: `OPERATOR_BEARER_TOKEN` (secret) and `OPERATOR_ID` (var).
Audit rows journal `OPERATOR_ID`, never the bearer. `dispatchControlRequest` requires an explicit
`operatorAuth` argument (no default). Tests inject a fake `OperatorAuth`; end-to-end coverage uses
`SELF.fetch` with Miniflare bindings for the secret scheme.

Operator identity is **not** clinic identity. Clinic AATs and installation-scoped tokens are not
accepted on `/control`.

---

## 4. `control_audit.action` vocabulary

Every control-plane mutation writes exactly one `control_audit` row. The `action` column carries one
of the five lifecycle values frozen by B2:

| `action` | Mutation | `target` column |
| --- | --- | --- |
| `enroll` | First-time installation enrollment | `installation_id` |
| `rotate` | Add a new installation key | `installation_id` |
| `suspend` | Suspend an installation | `installation_id` |
| `resume` | Resume a suspended installation | `installation_id` |
| `delete` | Mark installation lifecycle-terminal | `installation_id` |

Each row also carries:

- `audit_id` — unique identifier (UUID)
- `operator_id` — the resolved operator principal's id
- `before_pointer` — `NULL` in B2
- `after_pointer` — `NULL` in B2
- `recorded_at` — ISO-8601 timestamp of the mutation

Later slices (J3, F3) may add further `action` values for routing-policy activations, kill switches,
and purge operations. They **may extend, never rewrite** these five lifecycle values (Delivery Plan
§2.3).

---

## 5. Enroll entitlement initial values (§8.1 amendment)

On enroll, the handler creates one `entitlement` row with the following **frozen initial snapshot**.
Every column is non-null; `pending` is expressed as zeroed budgets and an empty capability set, not
absent values.

| Column | Initial value |
| --- | --- |
| `status` | `pending` |
| `plan` | Plan name from the enroll payload |
| `request_quota` | `0` |
| `token_budget` | `0` |
| `cost_budget` | `0` |
| `allowed_capabilities` | `[]` (empty JSON array) |
| `soft_threshold` | `0` |
| `period_start` | Enrollment instant (ISO-8601) |
| `period_end` | Same as `period_start` (closed, empty period — never an open period) |

The row grants **nothing** until an Entitlement management mutation (out of scope for B2) moves it
to `active` with real economics (§4.5 "The line between the first two rows"; §8.1).

---

## 6. Entitlement status enum (§7.3 amendment)

The `entitlement.status` column accepts exactly three values:

| Status | Written by | Semantics |
| --- | --- | --- |
| `pending` | B2 enroll | Zeroed economics; no capability allowed. The guard (B3) reads `pending` as **no capability allowed → quota-exhaustion path**. |
| `active` | Entitlement management (out of scope) | Real plan economics; capabilities and budgets enforced by the guard. |
| `suspended` | Entitlement management or installation suspend side-effects (out of scope for B2 entitlement writes) | Economics frozen; guard rejects or degrades per §4.3.3. |

B2 writes `pending` on enroll only. Suspend/resume in B2 toggle `installation.status`, not
`entitlement.status`.

### 6.1 Installation lifecycle status (companion field)

`installation.status` is separate from `entitlement.status`. B2 writes:

| Mutation | `installation.status` after |
| --- | --- |
| enroll | `active` |
| suspend | `suspended` (only from non-`deleted`, non-`suspended`) |
| resume | `active` (only from `suspended`) |
| delete | `deleted` (lifecycle-terminal; row purge is F3) |

**Terminal / transition rules:**

- `deleted` is terminal: suspend, rotate, or delete on `deleted` → `409 illegal_lifecycle_transition`.
- Resume is allowed only from `suspended`; resume on `active` (or any non-`suspended`) → `409
  illegal_lifecycle_transition`.
- Suspend when already `suspended` → `409 illegal_lifecycle_transition`.
- Journal a `control_audit` row only for transitions that actually change state.
- Delete pins `installation.status === "deleted"` (not merely “not active”).

---

## 7. Rotation overlap invariant (§8.1)

Key rotation **MUST** add a new `installation_key` row with a new `kid` **without** removing,
revoking, or updating the previous row. After rotation, **both** key rows remain present so the
platform accepts both keys during the overlap window (§8.1 "the platform accepts both keys during
the overlap").

| Invariant | Rule |
| --- | --- |
| New row | `INSERT` a new `installation_key` with the supplied `kid`, `public_key`, and `algorithm` |
| Previous row | **MUST remain** — no `DELETE`, no `revoked_at` update, no in-place `key_id` change |
| Overlap acceptance | Verifying that both keys authenticate requests is the **guard's concern (B3)**, not B2's |

---

## 8. One-time enrollment invariant (§8.1)

Enrollment is one-time per clinic installation. A second enroll for an existing `installation_id`
**or** `org_id` **MUST** produce `409 already_enrolled` with **no** additional D1 rows (FR-004,
FR-010).

Handlers reject known duplicates via SELECT, then map D1 `UNIQUE` failures from `DB.batch`:
`installation` → `409 already_enrolled`; `installation_key` → `409 duplicate_kid`; other storage
failures → `500 storage_error`. **Known follow-up (A5):** `installation` has no `UNIQUE(org_id)`
today — concurrent same-`org_id` / different-`installation_id` enrolls are not DB-backed; do not
amend the A5 migration in B2; add `UNIQUE(org_id)` in a later A5 amendment.

---

## 9. Consumers

| Slice | What it binds from this contract |
| --- | --- |
| **B3** (guard) | Entitlement status enum (`pending` → no capability allowed); rotation overlap (both `installation_key` rows present); `installation.status` for suspended-installation rejection |
| **J3** (staged rollout) | `control_audit` row shape and operator-identity rule; may add new `action` values, never rewrite the five lifecycle values |
| **F3** (retention purges) | `installation.status = deleted` as the lifecycle-terminal signal for installation-by-id purge; may add purge `action` values |
