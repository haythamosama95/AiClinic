# AI Billing Orchestration — Clinic Changes

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** `../01-proposal.md` (agreed decisions, verification findings, attack model),
`../../ai-platform/01-ai-platform.md` (§8.1, §12.5, A15, A16),
`../../ai-platform/03-ai-platform-delivery-plan.md`.
**Index:** [`00-index.md`](00-index.md) (master table of contents).

## Table of Contents

- [9. Clinic-side changes](#9-clinic-side-changes)
  - [9.1 Order-signing RPC — `public.create_ai_order(p_plan text)`](#91-order-signing-rpc-public-create_ai_order-p_plan-text)
  - [9.2 `set_ai_availability` — replaced, not supplemented](#92-set_ai_availability-replaced-not-supplemented)
  - [9.3 Platform receipt key seed — `public.add_platform_receipt_key(p_kid text, p_public_key text)`](#93-platform-receipt-key-seed-public-add_platform_receipt_key-p_kid-text-p_public_key-text)
  - [9.4 Key wrapping](#94-key-wrapping)
  - [9.5 What is deliberately not stored in the clinic](#95-what-is-deliberately-not-stored-in-the-clinic)

---

## 9. Clinic-side changes

All in one forward-only backend migration family, reusing the B1 patterns
(`20260801120000_ai_keystore_schema.sql`, `20260801120200_ai_token_issuer_rpc.sql`):
SECURITY DEFINER functions in `auth_internal`, thin `public` wrappers, `GRANT EXECUTE … TO authenticated`, deny-all RLS untouched.

### 9.1 Order-signing RPC — `public.create_ai_order(p_plan text)`

Owner/admin-gated (`auth_internal.assert_owner_or_administrator()` first, exactly as the
keystore RPCs). Selects the active installation key (same ordering as the issuer:
`valid_from DESC, kid DESC`, `revoked_at IS NULL`), builds the §5.2 payload with
`jsonb_build_object`, signs with `pgsodium.crypto_sign_detached` over the exact payload text
(the `issue_ai_token` pattern), and returns
`{ order_payload, signature, installation_id, kid, public_key }`. Errors: `FORBIDDEN`,
`INSTALLATION_NOT_ENROLLED`, `INVALID_INPUT` (blank plan). The RPC **records nothing** — order
state lives in the AI Billing Orchestrator; the clinic database stays ignorant of money, preserving the A15
boundary in the other direction.

### 9.2 `set_ai_availability` — replaced, not supplemented

The existing `public.set_ai_availability(boolean, text)` and its `auth_internal` twin
(`20260905120100_set_ai_availability_rpc.sql`) are **dropped** in the same migration that
creates the receipt-verifying variant — leaving both would keep a permanent bypass of the
activation ceremony (proposal §5.2, finding 3).

New signature: `public.set_ai_availability(p_receipt text)`.

- `p_receipt NULL` → deactivate: writes `{ enrolled: false, platform_base_url: null, valid_until: null }`. Always allowed for owner/admin — turning AI off needs no proof.
- Non-null → full §5.8 verification against `ai.platform_receipt_keys`; on success writes
`{ enrolled: true, platform_base_url, valid_until }` from the receipt claims.
- Errors: `FORBIDDEN`, `INVALID_RECEIPT` (any verification failure — one code, no oracle),
`RECEIPT_EXPIRED`.

`public.get_ai_availability()` keeps its signature and plain-`jsonb` shape, gains a
`valid_until` field, and becomes **self-expiring**: when `valid_until` is in the past it
returns `enrolled: false` (the stored row is left untouched; the next successful activation
overwrites it). Flutter's rule is unchanged — it reads this flag and never probes the platform
to discover enrollment.

### 9.3 Platform receipt key seed — `public.add_platform_receipt_key(p_kid text, p_public_key text)`

Owner/admin-gated. Validates `p_public_key` is base64url of exactly 32 bytes, then upserts the
`{ kid, public_key, added_at, revoked_at: null }` entry into the `ai.platform_receipt_keys`
app-settings array. `public.revoke_platform_receipt_key(p_kid text)` stamps `revoked_at` and
refuses the last unrevoked key (`CANNOT_REVOKE_LAST_PLATFORM_KEY`), mirroring the installation
keystore rule. Initial seed: Flutter fetches `GET /v1/platform-keys` during first activation
and calls the add RPC (§3.5); a clinic that has never activated has no keys and
`set_ai_availability(receipt)` fails closed with `INVALID_RECEIPT`.

### 9.4 Key wrapping

The `secret_key` wrapping migration of §3.6 ships with that hardening work. No RPC contract changes.

### 9.5 What is deliberately not stored in the clinic

No vendor credentials, no orchestrator identity, no order state, no provider anything. The
clinic's only new possessions are public keys and its own signed order payloads. There is no
credential honeypot to defend (proposal §5.3).

