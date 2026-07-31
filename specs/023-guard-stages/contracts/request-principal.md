# Contract: Immutable Request Principal (B3)

**Frozen by:** Slice B3 — Guard stages: identity, rate limiting, entitlement and kill switches
**Implements:** §4.3.2 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Every pipeline stage after identity **consumes** this artifact; the no-rework
rule applies (Delivery Plan §2.3). A later slice may **extend** (add a derived field) but may not
**rewrite** the field set, the types, or the immutability guarantee.

**Source of truth in code:** `ai-platform/src/identity/index.ts` (`Principal` type and its
constructor).

**Traces to:** spec FR-004; §4.3.2; the B1 AAT contract (`specs/021-…/contracts/aat-token.md`).

---

## 1. Overview

A request that passes identity (§6.1 stage 2) produces an immutable **request principal** — the
installation, organization, branch, actor, role, and capability scopes the rest of the pipeline
operates on. Every later stage reads it; none may mutate it (§4.3.2). The
`principal_immutable_to_later_stage` test pins the invariant.

The principal is constructed from the **verified** AAT payload claims. `scopes` come from the token
(B1 derives them server-side from RBAC; B3 does not re-derive them and never accepts a caller-supplied
`scopes` value — §5.6).

---

## 2. Field set

Every field is a §5.6 claim carried verbatim from the verified token. B3 adds no derived field and
renames nothing (the consumed B1 contract is authoritative).

| Field | Type | Source claim | Used by |
| --- | --- | --- | --- |
| `installationId` | `string` | `iss` | All later stages; the installation tenant scope; the rate-limit composite keys |
| `organizationId` | `string` | `org` | Tenant cross-check (context validator, C2) |
| `branchId` | `string` | `branch` | Branch-scoped operations |
| `actorId` | `string` | `sub` | Attribution; the `installation+actor` rate-limit key |
| `role` | `string` | `role` | Capability gating and audit |
| `scopes` | `readonly string[]` | `scopes` | Permitted AI capability scopes; the entitlement/kill-switch evaluation |
| `jti` | `string` | `jti` | Replay rejection at admission (B4) — carried on the principal so the admission stage needs no second token parse |
| `iat` | `number` | `iat` | Token-age diagnostics |
| `exp` | `number` | `exp` | Token-expiry diagnostics |
| `ver` | `string` | `ver` | Token-contract version — J4 overlap acceptance consumes this |

`aud` is **not** on the principal: it is checked once at verification and dropped, because every
downstream stage has already been admitted by the same audience. Carrying it would invite a later
stage to re-check it and diverge.

---

## 3. Immutability

The `Principal` is constructed once by the verifier and exported as a frozen object: every field is
`readonly` and `scopes` is a `readonly` array copied (not aliased) from the parsed payload. A later
stage that attempts to mutate any field, or to push/pop on `scopes`, has no observable effect on what
subsequent stages read — the `principal_immutable_to_later_stage` test asserts both that the attempt
throws or no-ops under TypeScript `readonly` and that a downstream reader sees the original values.

No `setPrincipal`, `withScope`, or other mutator is exported (R-20). A stage that needs a derived
value computes it locally; it does not write it back onto the principal.

---

## 4. Relationship to the rate-limit composite keys

§4.3.3 names three composite rate-limit keys. B3 derives them from the principal (no new token
parse, no D1 read):

| Key | Composition (from the principal) |
| --- | --- |
| `installation` | `installationId` |
| `installation+actor` | `installationId` + `actorId` |
| `installation+capability` | `installationId` + the capability id (supplied on the request, not the token — §4.3.3) |

A fourth key is not added (spec Assumption: the Rate Limiting binding's composite-key interface is
fixed; B3 uses the three named keys and adds no fourth).

---

## 5. Consumers

| Stage / slice | What it reads |
| --- | --- |
| **Entitlement (B3, this slice)** | `installationId`, `role`, `scopes` — evaluates AI-enablement, plan tier, capability grant, kill switches |
| **Rate limit (B3, this slice)** | `installationId`, `actorId` — the composite keys |
| **Admission (B4)** | `installationId`, `jti` — the Quota DO round trip |
| **Capability resolver (C1)** | `installationId`, `scopes` — plan-level allowances |
| **Context validator (C2)** | `organizationId`, `branchId` — tenant cross-check against supplied context |
| **Journal writer (C3)** | `installationId`, `actorId`, `branchId` — the `ai_request` row |

---

## 6. Out of scope for this contract

| Behaviour | Owner | Reason |
| --- | --- | --- |
| Quota / concurrency / cost-ceiling fields | B4 / C2 | §4.3.3 / §6.1 stages 7–8 — not on the principal; queried from the Quota DO |
| Capability id | The request, not the token | Supplied on the submit request; joined onto the principal's *context*, not the principal itself |
| Patient identifiers | None (§5.6 deliberate omission) | A token is not a resource grant |
| Provider / model hints | None (§5.6 deliberate omission) | The client has no say in routing |