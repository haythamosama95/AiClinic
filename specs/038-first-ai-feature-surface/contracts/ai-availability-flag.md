# Contract: AI availability flag (E4)

**Frozen by:** Slice E4 — First AI feature surface and degraded mode  
**Implements:** §4.2 AI availability flag of `docs/architecture/ai-platform/01-ai-platform.md`; Open Decision 8
recommended default  
**Status:** Frozen. Later slices may extend how enrollment is written (control-plane / operator
paths) but must not rewrite the clinic-readable shape `{ enrolled, platform_base_url }` or the
rule that non-enrolled clients hide AI affordances without probing the AI platform.

**Source of truth in code (this slice):**
`backend/supabase/migrations/` AI availability migration (keys on `ai_internal.app_settings` +
`auth_internal` / `public` read RPC) and the Flutter reader under
`frontend/lib/features/ai/availability/`.

**Traces to:** spec **Freezes** (AI availability flag clinic-side store); FR-008, FR-009, FR-012;
T8, T10, T21.

---

## 1. Overview

The clinic database stores whether this installation is AI-enrolled and the platform base URL so
the Flutter client can hide AI affordances entirely for non-AI clinics **without probing the AI
platform network** (§4.2; Open Decision 8). This is **not** mirrored quota state. The clinic DB
gains no prompts, providers, quotas, or AI request state (§4.2 Boundary note).

---

## 2. Storage identifiers (plan-time)

Reuses the B1 installation-scoped settings table — no new clinic table:

| Identifier | Value |
| --- | --- |
| Table | `ai_internal.app_settings` |
| Settings key | `ai.availability` |
| `value_json` shape | object (below) |

### 2.1 Stored JSON shape

```json
{
  "enrolled": false,
  "platform_base_url": null
}
```

| Field | Type | Cardinality | Notes |
| --- | --- | --- | --- |
| `enrolled` | `boolean` | required | `false` = not AI-enrolled (default) |
| `platform_base_url` | `string` \| `null` | required key; value may be null | Gateway origin from enrollment (`{platform_base_url}` per B2 enroll response). Null when not enrolled or not yet written. |

Default seed (migration): `{ "enrolled": false, "platform_base_url": null }` via
`ON CONFLICT (key) DO NOTHING` so re-running migrations is a no-op.

---

## 3. Clinic-readable RPC

Follows the established additive pattern: `public` wrapper → `auth_internal` `SECURITY DEFINER`
(§4.2).

| Item | Value |
| --- | --- |
| Internal function | `auth_internal.get_ai_availability()` |
| Public wrapper | `public.get_ai_availability()` |
| Execute grant | `authenticated` only (`anon` / `PUBLIC` revoked) |
| AI-specific parameters | **None** — installation-scoped read only |

### 3.1 Return payload

JSON object (same fields as storage):

```json
{
  "enrolled": true,
  "platform_base_url": "https://ai-gateway.example.workers.dev"
}
```

| Field | Type | When |
| --- | --- | --- |
| `enrolled` | `boolean` | Always present |
| `platform_base_url` | `string` \| `null` | Always present; null when not enrolled / unset |

Missing settings row MUST behave as non-enrolled (`enrolled: false`, `platform_base_url: null`) —
fail closed for affordances, never probe the platform to discover enrollment.

---

## 4. Client binding rules

| Rule | Source |
| --- | --- |
| Read enrollment and base URL **only** from this clinic-side flag / RPC (or an injectable test double of that shape) | FR-008, FR-009; T21 |
| When `enrolled` is `false`, hide all AI affordances and make **zero** AI-platform network calls | FR-009; T8 |
| When `enrolled` is `true` and the platform is reachable, show AI affordances | FR-012; T10 |
| Reachability probes (e.g. A1 `GET {platform_base_url}/health`) are allowed **only** when `enrolled` is `true` | FR-009; R-5; A1 `/health` |
| Do not mirror or store quota state in this flag | Open Decision 8; §4.2 |

---

## 5. What this contract does not freeze

- Control-plane enrollment mutation that **writes** `enrolled` / `platform_base_url` (B2 / operator
  ops may populate the row; E4 freezes the clinic-readable store and read shape).
- Quota, entitlement, kill-switch, or capability-grant state (platform D1 / Entitlement — not
  Supabase).
- AI Feature Surface UI rules (provisional draft, accept/discard, degraded UX) — behavioural
  Freezes of E4 without a separate wire artifact.
