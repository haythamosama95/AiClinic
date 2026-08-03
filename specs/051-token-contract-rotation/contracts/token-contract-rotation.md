# Contract: Token contract rotation with overlapping acceptance (J4)

**Frozen by:** Slice J4 — Token contract rotation with overlapping acceptance
**Implements:** §5.7, §5.6, §4.5, §7.3 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this contract; they may not **rewrite** it
(Delivery Plan §2.3).

**Source of truth in code:**
- D1: `ai-platform/migrations/20260803120000_token_contract.sql`
- Identity: `ai-platform/src/identity/index.ts` (`EnrolledKeyVerifier` accepted-`ver` check)
- Control: `ai-platform/src/control/index.ts` (begin-rotation / retire handlers)
- Config cache kind: `ai-platform/src/config-cache/index.ts` (`"token_contracts"`)
- Clinic mint setting: `ai_internal.app_settings` key `ai.aat.ver` (B1; issuer already reads it)

**Traces to:** spec FR-001–FR-017; Freezes in `spec.md` Slice Contract.

**Entity binding:** [`../data-model.md`](../data-model.md)

---

## 1. Overview

`ver` is a **platform-global** Token contract version with two sides (§5.6):

| Side | Owner | Rule |
| --- | --- | --- |
| **Accepting** | Platform identity stage | Accept every `ver` in the D1 `token_contract` accepted set |
| **Minting** | Clinic issuer RPC | Mint **exactly one** `ver` per token from `ai.aat.ver` |

Rotation is additive like key rotation: both contract versions are accepted during the window,
`iss` and `kid` are untouched, and **no clinic re-enrolls** (§5.6; Done when).

---

## 2. Accepted-`ver` set (D1 `token_contract`)

### 2.1 Shape

One row per `ver`:

| Field | Meaning |
| --- | --- |
| `ver` | Accepted Token contract version (PK) |
| `added_at` | When the row was added |
| `retired_at` | Null while accepted; stamped on retire |
| `changed_by` | Operator who last changed the row |

**Forbidden:** `retire_after` column, any TTL, any auto-retire on a clock (§5.7; §7.3).

### 2.2 Set membership

- **Accepted set** = rows with `retired_at IS NULL`.
- **Stable:** exactly one accepted `ver`.
- **Mid-rotation:** at most two accepted `ver` values.
- Initial migration seeds `ver = '1'` (aligned with B1 default `ai.aat.ver`).

### 2.3 Config-cache kind

Kind `"token_contracts"` (forward-only extension of A5 `ConfigEntityKind`). Identity loads:

```text
loadConfig(cache, reader, "token_contracts", payload.ver)
```

- Hit with `retired_at == null` → `ver` is accepted.
- Miss, or row with `retired_at` set → treat as not accepted.
- Cold isolate reconstructs from D1 like every other volatile flag; rotation takes effect within
  one cache TTL without a deploy (§5.6; §7.3).

A5's frozen `contracts/config-cache.md` is **not** rewritten; this kind is frozen here.

---

## 3. Control-plane writers

The **only** writers of `token_contract` are two operator-authenticated control-plane mutations
(§4.5). The request path never writes this record.

| Transition | HTTP (POST only) | D1 effect | `control_audit.action` |
| --- | --- | --- | --- |
| Begin rotation | `/control/token-contract/begin-rotation` | Insert row for the new `ver` (`retired_at` null); prior accepted `ver` kept | `token_contract_begin_rotation` |
| Retire | `/control/token-contract/retire` | Stamp `retired_at` on the named `ver`; accepted set returns to one | `token_contract_retire` |

Both reuse B2 `OperatorAuth` and the existing `control_audit` row shape (operator, action, target,
before/after pointer, at). B2's contract file is not edited; the `action` vocabulary is extended
the same way J1/J3 extended it.

**Operator payload (conceptual):** begin-rotation supplies the new `ver` string; retire supplies
the `ver` to retire. Writers enforce FR-002 (refuse begin-rotation when two are already accepted;
retire returns the set to one). No new §5.4 taxonomy code is introduced for operator mistakes —
control-plane HTTP error responses stay on the B2 control surface.

---

## 4. Identity acceptance and refusal

After B3's existing checks (compact JWS, `alg: EdDSA`, `iss`+`kid` key selection, audience, expiry,
skew, suspended installation), the identity stage checks `payload.ver` against the accepted set.

| Condition | `VerifyResult` |
| --- | --- |
| `ver` in accepted set | `{ ok: true, principal }` (unchanged principal shape; includes `ver`) |
| `ver` retired (no longer in set) | `{ ok: false, code: "unauthenticated" }` |
| `ver` never accepted | `{ ok: false, code: "unauthenticated" }` |

**No new taxonomy code** is added for a retired or unknown contract version (§5.6 accepting side;
§5.4). A contract the verifier no longer accepts is not a distinct error class.

B3's frozen port shape (`TokenVerifier` / `VerifyResult`) is **extended in behaviour only** — the
discriminated union gains no new `code` member. `specs/023-guard-stages/contracts/token-verifier.md`
is not edited.

---

## 5. Minting side (`ai.aat.ver`)

| Rule | Statement |
| --- | --- |
| Source | Issuer reads `ver` from `ai_internal.app_settings` key `ai.aat.ver` (alongside `ai.aat.lifetime_minutes`) |
| Cardinality | Exactly **one** `ver` per minted token — no dual-mint |
| Advancement | Operator action on the **clinic deployment**; the platform never reads or writes this setting (§1.3.1) |
| Claim completeness | A token under the new contract carries every §5.6 claim: `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver` |
| `scopes` | Remain server-derived from RBAC; never client-supplied |
| Header | Compact JWS with `alg: EdDSA` and signing `kid`; `alg` is not negotiable because of a `ver` rotation |
| Omissions | Still no patient identifiers, quota state, or provider/model hints |
| Re-enrollment | Not required; `iss`+`kid` continue to select the enrolled public key |

B1's frozen `contracts/aat-token.md` is not rewritten; J4 binds to it and advances the minting
`ver` through the existing settings row.

---

## 6. Transition model (set membership)

| Step | Effect on accepted set | Effect on issuers |
| --- | --- | --- |
| Begin rotation | New `ver` added; prior kept (overlap open) | None yet — clinics keep minting the prior `ver` until they advance `ai.aat.ver` |
| During | Unchanged — both accepted | Each clinic flips `ai.aat.ver` on its own, one value at a time |
| Retire | Retired `ver` removed; set returns to one (overlap closed) | None — clinics are already on the new `ver` before this is safe |

---

## 7. Explicit non-goals (frozen absences)

- No new §5.4 code for retired/unknown `ver`.
- No `retire_after` / TTL / auto-retire.
- No dual-mint.
- No re-enrollment as part of contract rotation.
- No rewrite of B1 keystore/issuer/signature contract or B3 signature/audience/expiry/skew checks.
- No second Quota Durable Object round trip and no second R2 object per request for `ver` checking.
- No per-request server-side rotation session state.
- No mechanism from §9.14.
