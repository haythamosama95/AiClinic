# AI Billing Orchestration — Trust and Keys

**Status:** Architecture — decided

**Date:** 2026-09-11

**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.

**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.

**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [3. Trust model and key management](#3-trust-model-and-key-management)
  - [3.1 The three signing keys](#31-the-three-signing-keys)
  - [3.2 Key identifiers](#32-key-identifiers)
  - [3.3 Rotation — purchase proof signing key](#33-rotation-purchase-proof-signing-key)
  - [3.4 Rotation — orchestrator CAT key (and human operator keys)](#34-rotation-orchestrator-cat-key-and-human-operator-keys)
  - [3.5 Rotation — platform receipt key](#35-rotation-platform-receipt-key)
  - [3.6 Clinic installation private-key wrapping (proposal §9 finding 4)](#36-clinic-installation-private-key-wrapping-proposal-9-finding-4)
  - [3.7 Rotation runbook and boot-time self-check](#37-rotation-runbook-and-boot-time-self-check)

---

## 3. Trust model and key management



### 3.1 The three signing keys


| Key                            | Held by                                      | Signs                                             | Verified by                           | Storage                                                                                                          |
| ------------------------------ | -------------------------------------------- | ------------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Purchase proof signing key** | AI Billing Orchestrator, purchase module     | Purchase Proof (§5.7)                             | ai-platform control plane             | Worker secret `BILLING_PURCHASE_PROOF_PRIVATE_KEY` (PKCS#8, base64)                                              |
| **Orchestrator CAT key**       | AI Billing Orchestrator, orchestrator module | Control Action Token per `/control/v1/`* call (§5.6) | ai-platform control plane             | Worker secret `ORCHESTRATOR_CAT_PRIVATE_KEY` (PKCS#8, base64)                                                    |
| **Platform receipt key**       | ai-platform Worker                           | Provisioning Receipt (§5.8)                       | clinic Supabase `set_ai_availability` | Worker secret `PLATFORM_RECEIPT_PRIVATE_KEY` (PKCS#8, base64); public half in var `PLATFORM_RECEIPT_PUBLIC_KEYS` |


- **Purchase proof signing key** — proves a clinic actually paid (or received a comp order). The purchase module signs a short-lived token after money moves; the platform checks it before granting or renewing an entitlement.
- **Orchestrator CAT key** — proves the orchestrator is allowed to call platform control APIs. Every `/control/v1/`* request carries a token signed with this key so the platform knows the caller is the billing orchestrator, not a random client.
- **Platform receipt key** — proves the platform has an active entitlement for a clinic installation. The platform signs a receipt the Flutter app delivers to the clinic database, which accepts it as the only way to turn AI on locally.

Private key = signs. Public key = verifies. Each artifact's JWS header carries a `kid` so the
verifier picks the right public key from its store.

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│  KEY 1 — Purchase proof (payment → platform grant)                                         │
├────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                            │
│  ABO purchase module                         ai-platform Worker                            │
│  ┌────────────────────────────┐              ┌─────────────────────────────────────────┐   │
│  │ PRIVATE (secret)           │   signs      │ PUBLIC (Worker var)                     │   │
│  │ BILLING_PURCHASE_PROOF_    │ ──────────▶  │ BILLING_PURCHASE_PROOF_PUBLIC_KEYS      │   │
│  │   PRIVATE_KEY              │  Purchase    │   [{ kid: "bill-1", public_key, … },    │   │
│  │ kid: bill-1 (active)       │    Proof     │    { kid: "bill-2", … }]  (key set)     │   │
│  └────────────────────────────┘              └──────────────────▲──────────────────────┘   │
│           │ only purchase module                                │ verify on enroll /       │
│           │ can sign                                            │ entitle / renew /        │
│           │                                                     │ override (§5.7)          │
│  Key set in Worker var; rotation overlap up to 72 h (§3.3).                                │
└───────────┼─────────────────────────────────────────────────────┼──────────────────────────┘
            │                                                     │
┌───────────┼─────────────────────────────────────────────────────┼──────────────────────────┐
│  KEY 2 — Orchestrator CAT (who may call /control/v1/*)          │                          │
├───────────┼─────────────────────────────────────────────────────┼──────────────────────────┤
│           │                                                     │                          │
│  ABO orchestrator module                     ai-platform Worker                            │
│  ┌────────────────────────────┐              ┌───────────────────────────────────────────┐ │
│  │ PRIVATE (secret)           │   signs      │ PUBLIC (D1 table — many rows, not one key)│ |
│  │ ORCHESTRATOR_CAT_          │ ──────────▶  │ control_operator                          │ │
│  │   PRIVATE_KEY              │  CAT per     │   one row per key: { key_id,              │ │
│  │ kid: UUID = key_id         │ /control/v1/*│     operator_id, public_key,              │ │
│  │ (one active private secret │              │     allowed_actions, revoked_at }         │ │
│  │  on ABO at a time)         │              │   rotation: INSERT new row, revoke old    │ │
│  └────────────────────────────┘              └──────────────────▲────────────────────────┘ │
│           │ only orchestrator module                            │ verify before any        │
│           │ can sign with orchestrator key                      │ control handler (§5.6)   │
│           │                                                     │                          │
│  Human operators (incident response / ops) same table ──────────┘                          │
│  ┌────────────────────────────┐   signs CAT  each operator: own row, own allowed_actions;  │
│  │ PRIVATE on operator's      │ ──────────▶   private key never on server (§4.2)           │
│  │   laptop only              │                                                            │
│  └────────────────────────────┘                                                            │
│  Rotation overlap ≈ 2 min (CAT max lifetime 120 s, §5.6) — see §3.4.                       │
└────────────────────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────────────────────┐
│  KEY 3 — Provisioning receipt (platform → clinic AI flag)                                  │
├────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                            │
│  ai-platform Worker                          clinic Supabase                               │
│  ┌────────────────────────────┐              ┌─────────────────────────────────────────┐   │
│  │ PRIVATE (secret)           │   signs      │ PUBLIC (app_settings JSON array)        │   │
│  │ PLATFORM_RECEIPT_          │ ──────────▶  │ ai.platform_receipt_keys                │   │
│  │   PRIVATE_KEY              │  Provisioning│   [{ kid: "rcpt-1", public_key, … }]    │   │
│  │ kid: rcpt-1 (active)       │    Receipt   │ seeded via GET /v1/platform-keys (§3.5) │   │
│  └────────────────────────────┘              └──────────────────▲──────────────────────┘   │
│           │ minted in GET /v1/installation/status               │ verify in                │
│           │                                                     │ set_ai_availability      │
│           │ Public keys also in Worker var                      │ (§5.8, §9.2)             │
│           │ PLATFORM_RECEIPT_PUBLIC_KEYS (for Flutter fetch)    │                          │
│           │                                                     │                          │
│           └──── receipt carried by Flutter (short-lived; ───────┘                          │
│                 not a stored clinic credential)                                            │
└────────────────────────────────────────────────────────────────────────────────────────────┘

Grant path (two signatures on the platform):  Purchase Proof ──┐
                                                               ├──▶ ai-platform /control/v1/*
Orchestrator CAT ──────────────────────────────────────────────┘
Clinic activation (separate step):  Provisioning Receipt ──▶ clinic DB
```

**Why KEY 1 and KEY 2 store public keys differently:** both allow multiple public keys during
rotation. Purchase proof uses a Worker var key set because there is one billing issuer and proofs
live up to 72 h. CAT uses a `control_operator` table because many callers (orchestrator +
humans) each have their own key, scopes, and fast revocation — and CATs expire in 120 s, so
rotation overlap is minutes, not days (§3.3 vs §3.4).

All three are Ed25519. Signing uses `crypto.subtle.sign`/`verify` with `Ed25519` — the same
primitive `EnrolledKeyVerifier` already uses in production (`ai-platform/src/identity/index.ts`).
Private keys are imported from PKCS#8 (`crypto.subtle.importKey("pkcs8", …, "Ed25519", …)`);
public keys travel as base64url raw 32-byte strings or JWK `{kty:"OKP", crv:"Ed25519", x}`,
matching the existing clinic-key conventions.

Human operators hold **personal** Ed25519 keypairs (generated locally, private key never leaves
their machine) and sign CATs with them; their public keys are registered in `control_operator`
(§4.2). The shared `OPERATOR_BEARER_TOKEN` is **removed entirely** (§8.1, §13 item 3) — a
shared, unattributed credential is the exact anti-pattern per-operator keys exist to
eliminate.

### 3.2 Key identifiers

Every signed object carries a `kid` in its JWS header. Key ids are namespaced so a `kid` from one
trust domain can never be resolved in another:


| Domain                           | `kid` format                           | Example  |
| -------------------------------- | -------------------------------------- | -------- |
| Clinic installation keys         | UUID (existing convention)             | `8f3c…`  |
| Purchase proof signing keys      | `bill-<n>`                             | `bill-1` |
| Orchestrator / operator CAT keys | UUID per key row in `control_operator` | `7a21…`  |
| Platform receipt keys            | `rcpt-<n>`                             | `rcpt-1` |




### 3.3 Rotation — purchase proof signing key

The platform verifies purchase proofs against a **key set**, not a single key:
`BILLING_PURCHASE_PROOF_PUBLIC_KEYS` is a Worker var holding a JSON array
`[{ "kid": "bill-1", "public_key": "<base64url>", "not_before": "…", "not_after": "…" }]`.
Verification selects the entry by header `kid` and rejects outside its validity window — the same
shape as `isKeyWithinValidityWindow` in `EnrolledKeyVerifier`.

Rotation procedure (zero-downtime, four steps) — executed by the single rotation
script/runbook of §3.7, which performs the platform-side and AI Billing Orchestrator-side steps
in one operation:

1. Generate `bill-(n+1)`; add its public half to `BILLING_PURCHASE_PROOF_PUBLIC_KEYS` alongside
  `bill-n` (platform now accepts both).
2. Set the AI Billing Orchestrator's `BILLING_PURCHASE_PROOF_PRIVATE_KEY` secret to the new key and its
  active `kid` var to `bill-(n+1)`.
3. Wait one maximum purchase proof lifetime (72 h, §5.7) so every in-flight purchase proof signed by
  `bill-n` has expired or been consumed.
4. Remove `bill-n` from the platform key set (or stamp its `not_after`).

Emergency revocation is step 4 alone: at most 72 h of already-minted purchase proofs become
unusable, and every one of them is single-use anyway (§5.7 replay rule), so the real exposure
window is the set of *unconsumed* purchase proofs, which the orchestrator retries make small.

### 3.4 Rotation — orchestrator CAT key (and human operator keys)

CAT verification is backed by the `control_operator` **table** (§4.2), so rotation is data, not
deployment:

1. Insert a new row `(operator_id = "orchestrator", key_id = <new uuid>, public_key = …)`.
2. Update the AI Billing Orchestrator's `ORCHESTRATOR_CAT_PRIVATE_KEY` secret and key-id var.
3. Stamp `revoked_at` on the old key row.

CATs live at most 120 s (§5.6), so the overlap window is two minutes, not days. Human operator
rotation is identical. Revocation of a compromised operator is one `UPDATE` — this is the
mechanism behind the proposal's "orchestrator DoS is revocable" residual-risk mitigation.

### 3.5 Rotation — platform receipt key

The hard case (proposal §9 finding 5): the verifying party is **every clinic database**, so the
key set must be distributable and stored clinic-side.

- **Clinic storage:** `ai_internal.app_settings` key `ai.platform_receipt_keys` holds a JSON
array `[{ "kid": "rcpt-1", "public_key": "<base64url>", "added_at": "…", "revoked_at": null }]`.
The existing deny-all RLS policy on `app_settings` is unchanged; only SECURITY DEFINER RPCs
touch it (§9.3, §9.4).
- **Distribution:** the platform serves its own public keys at `GET /v1/platform-keys`
(unauthenticated — public keys are not secrets; §5.9). Flutter fetches this during activation
and seeds the clinic via `add_platform_receipt_key`. Trust anchor is the vendor's TLS origin —
the same anchor the clinic already trusts for `platform_base_url`.
- **Rotation procedure:**
  1. Generate `rcpt-(n+1)`; add to `PLATFORM_RECEIPT_PUBLIC_KEYS` (platform now *serves* both)
    and set the signing secret to the new key.
  2. Clinics pick up the new key on their next activation/status poll (Flutter re-fetches
    `GET /v1/platform-keys` whenever receipt verification fails with `unknown kid`, then retries
     once — self-healing, no operator action).
  3. After every clinic's stored receipts would have expired (receipts live 15 minutes;
    `valid_until` is a *consumption* bound, not a signature-validity bound), the old key can be
     retired from the served set. Clinics revoke it locally via `revoke_platform_receipt_key`
     (which refuses to revoke the last key, mirroring `CANNOT_REVOKE_LAST_ACTIVE_KEY`).
- **Emergency revocation:** remove the key from `PLATFORM_RECEIPT_PUBLIC_KEYS` and stop signing
with it. Clinics that still trust it accept receipts for at most 15 minutes (receipt `exp`),
and the guard re-checks entitlement on every request regardless — a forged or stale receipt
flips a UI flag, it does not grant service (§12).



### 3.6 Clinic installation private-key wrapping (proposal §9 finding 4)

Today `ai_internal.installation_keys.secret_key` is raw `bytea`. This design makes that key
**purchase-authorizing** (it signs order payloads, §5.2), so the architecture schedules hardening
in the implementation schedule rather than deferring it:

- A new migration adds `secret_key_wrapped bytea` and `wrap_key_id uuid`, populates them with
`pgsodium.crypto_aead_det_encrypt(secret_key, kid::bytea, key_id)` where `key_id` references a
pgsodium-managed key created via `pgsodium.create_key(name := 'ai_installation_key_wrap')`,
then drops the plaintext column. The key id is stored in `app_settings`
(`ai.key_wrap_id`); it is not itself secret.
- `issue_ai_token` and the new order-signing RPC decrypt with
`pgsodium.crypto_aead_det_decrypt` at point of use. No RPC signature changes.
- **Honest boundary:** this protects the key against SQL-level exfiltration (a dumped table or a
stolen backup without the pgsodium root key is not a signing key). It does not protect against
an attacker with live `postgres` access, who can call the decrypt function. The pgsodium root
key's custody is a Supabase environment property; clinics self-hosting PostgreSQL must set
`pgsodium.root_key` outside the database for the boundary to hold. This is documented in the
slice, not hand-waved.

Until the migration ships, the residual is exactly today's status quo; the order-signing RPC is
designed so wrapping is an internal change to two functions.

### 3.7 Rotation runbook and boot-time self-check

Every rotation above spans two deployables — a platform-side half and an AI Billing
Orchestrator-side half that must land together or the trust chain breaks half-rotated. Two
operability controls keep that from being a hand-coordinated dance:

- **One rotation script/runbook per key domain.** A single script (or runbook, while the
  operator count is one) performs **both sides** of a rotation in one operation: for the
  purchase-proof key, the §3.3 four-step procedure (platform key-set update, ABO secret + active
  `kid` var, overlap wait, old-key retirement); for the orchestrator CAT key, the §3.4
  table-backed procedure (`control_operator` insert, ABO secret + key-id var, old-row
  revocation); for the receipt key, the §3.5 procedure (platform secret + served key set,
  clinic-side self-healing refetch, old-key retirement). The script enforces the overlap waits
  between phases rather than relying on the operator's calendar.
- **ABO boot-time self-check.** At isolate init (cached for the isolate's lifetime), the AI
  Billing Orchestrator verifies its active purchase-proof `kid` and issuer
  (`BILLING_ISSUER`) against an **authenticated platform read** (orchestrator-scoped CAT,
  §5.6) and **fails fast** on mismatch — the Worker refuses to mint proofs or run the outbox
  processor and emits a structured alert. A misconfigured or half-rotated deploy surfaces at
  boot, not as a stream of failed `enroll` calls against paid orders.

