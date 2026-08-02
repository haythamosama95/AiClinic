# Contract: AI acceptance recording (F2)

**Frozen by:** Slice F2 — Acceptance recording RPC and client accept path  
**Implements:** §4.2, §4.2.2, §4.1, A5 of `docs/architecture/17-ai-platform.md`  
**Status:** Frozen. Later slices (capability manifests declaring `human_accept_required`, Open
Decision 14 conversational acceptance) **consume** this artifact; they may add registry rows and
call this exact RPC, and must not rewrite the RPC signature, registry shape, `ai_accepted_output`
columns, audit action, or invent a second acceptance path (delivery plan §2.3; Open Decision 14).

**Source of truth in code (this slice):**
`backend/supabase/migrations/` acceptance recording migration(s) and the Flutter clinical accept
path under `frontend/lib/features/ai/acceptance/`.

**Traces to:** spec **Freezes**; FR-001–FR-019; T1–T10.

---

## 1. Overview

Clinical AI content enters a clinic record only through an explicit human accept that stores the AI
request reference alongside the domain write (A5). The mechanism is a single shared clinic RPC that
delegates the clinical write to an allow-listed existing domain RPC and records provenance in the
same transaction (§4.2.2). The gateway is not involved: acceptance is clinic-side only; D1 is not
written; the clinic stores the handle (`ai_request_reference` text), not the request (§4.2 boundary
note).

This contract freezes five wire/table shapes later **Consumes** bind to:

1. **`public.record_ai_acceptance` RPC** — signature, success `data`, failure pass-through.
2. **`ai_internal.acceptance_targets` registry** — allow-list of `target_key` → domain function.
3. **`public.ai_accepted_output` table** — columns, uniqueness, indexes, deliberately absent fields.
4. **Atomic acceptance audit** — `audit_log.action = 'ai.acceptance_record'` and bidirectional join.
5. **Demonstration target** — `visit_clinical_notes` → `public.save_visit_documentation`.

---

## 2. RPC: `public.record_ai_acceptance`

### 2.1 Signature

```sql
public.record_ai_acceptance(
  p_request_reference text,   -- §8.9 format; the only AI-shaped input
  p_target_key        text,   -- allow-listed acceptance target
  p_target_args       jsonb   -- named arguments for that target's domain RPC
) RETURNS public.rpc_result
```

Pattern: `public` INVOKER wrapper → `auth_internal.record_ai_acceptance` `SECURITY DEFINER` (F4).
The definer half writes `ai_accepted_output` and the append-only `audit_log`; the clinical write is
delegated to the allow-listed domain RPC and keeps that RPC's own authorization (§4.2.2).

### 2.2 Success `rpc_result.data`

On success, `data` MUST carry at least:

```json
{
  "acceptance_id": "<uuid>",
  "table_name": "<text>",
  "record_id": "<uuid>",
  "audit_log_id": "<uuid>"
}
```

merged with the delegated domain RPC's own `data` object (keys from the delegated success payload
are preserved alongside the four acceptance keys) (§4.2.2; FR-005).

### 2.3 Failure

- **Delegated domain RPC failure:** return that RPC's `error_code` and `error_message` unchanged;
  write nothing (no domain change beyond what the delegated call itself rolled back, no
  `ai_accepted_output`, no `ai.acceptance_record` audit). Acceptance adds **no new error
  vocabulary** — neither clinic-side nor platform taxonomy (§4.2.2; FR-005; T9).
- **Unregistered `p_target_key`:** reject **before** any write using an existing clinic
  `public.rpc_error` code (no new acceptance-specific code; no platform taxonomy entry)
  (§4.2.2; FR-004; T5).
- **Malformed `p_request_reference`:** reject before any write when the value fails the
  §4.2.2 / §8.9 CHECK shape (same clinic reject posture; no new vocabulary).

### 2.4 Forbidden

- Client-supplied function names — only `p_target_key` is accepted; the registry alone maps key →
  domain function (§4.2.2).
- A second acceptance RPC or chat-specific path (Open Decision 14; FR-019).
- Journaling acceptance into D1 or teaching the gateway clinic schema (§4.2 boundary note).

---

## 3. Registry: `ai_internal.acceptance_targets`

| Column | Type | Notes |
| --- | --- | --- |
| `target_key` | `text` PK | Client-supplied allow-list key (e.g. `visit_clinical_notes`) |
| `domain_function` | `text` NOT NULL | Existing `public` domain RPC name (e.g. `save_visit_documentation`) |
| `table_name` | `text` NOT NULL | Domain table written — same vocabulary as `audit_log.table_name` |

- The only source of which domain RPC acceptance may invoke (§4.2.2; FR-003).
- Registering a target is a **migration**; it is never a runtime client action.
- An unregistered `p_target_key` is rejected before anything is written (FR-004).
- Schema lives under restricted `ai_internal` (existing B1 schema); not granted for direct
  `authenticated` mutation.

---

## 4. Table: `public.ai_accepted_output`

| Column | Type | Purpose |
| --- | --- | --- |
| `id` | `uuid` PK | Acceptance id returned to the caller |
| `organization_id` | `uuid` NOT NULL → `public.organizations` | Tenant scope for RLS |
| `branch_id` | `uuid` NULL → `public.branches` | Branch scope where the target row has one |
| `table_name` | `text` NOT NULL | Domain table written — same vocabulary as `audit_log.table_name` |
| `record_id` | `uuid` NOT NULL | Same vocabulary as `audit_log.record_id` for that domain write |
| `ai_request_reference` | `text` NOT NULL, CHECK `~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$'` | Join key to the platform journal (§8.9 / A13) |
| `accepted_by` | `uuid` NOT NULL → `auth.users` | Human who accepted (A5) |
| `accepted_at` | `timestamptz` NOT NULL DEFAULT `now()` | When |
| `audit_log_id` | `uuid` NOT NULL → `public.audit_log` | The `ai.acceptance_record` entry |

Constraints / indexes (§4.2.2; FR-006):

- UNIQUE `(table_name, record_id, ai_request_reference)`
- INDEX on `ai_request_reference`
- INDEX on `(table_name, record_id)`

**Deliberately absent** (FR-007; §4.2 boundary note): capability id, model, provider, prompt, token
counts, cost, and request state. The reference is `text`, not a foreign key to D1.

RLS: tenant/branch isolation consistent with other domain tables; acceptance grants no privilege the
clinician did not already have — the delegated domain RPC still asserts its own permissions
(§4.2.2).

---

## 5. Atomic acceptance audit

In the **same transaction** as the delegated domain write and the `ai_accepted_output` insert, the
RPC writes one `audit_log` row:

| Field | Value |
| --- | --- |
| `action` | `'ai.acceptance_record'` |
| `table_name` | Domain table just written (registry `table_name`) |
| `record_id` | Domain record id just written (same vocabulary as that domain's `audit_log.record_id`) |
| `new_data_json` | `{"ai_request_reference": …, "acceptance_id": …}` |

`ai_accepted_output.audit_log_id` points at that row. Provenance resolves both ways (FR-008–FR-010;
T2):

- Field → reference: `audit_log` by `(table_name, record_id)` with `action = 'ai.acceptance_record'`.
- Reference → field: `ai_accepted_output` by `ai_request_reference` → `(table_name, record_id)` and
  `audit_log_id`.

Together-or-not-at-all is a property of the RPC transaction (FR-009; T1).

---

## 6. Demonstration target

| Field | Value |
| --- | --- |
| `target_key` | `visit_clinical_notes` |
| `domain_function` | `save_visit_documentation` (invoked as `public.save_visit_documentation`) |
| `table_name` | `visit_clinical_notes` |

- Existing domain RPC: `public.save_visit_documentation` → `auth_internal.save_visit_documentation`
  (`SECURITY DEFINER`), asserts `visits.edit_soap`, enforces branch scope and optimistic concurrency,
  writes `public.visit_clinical_notes` (§4.2.2; FR-011).
- `p_target_args` carries that RPC's named arguments (`p_visit_id`, section texts,
  `p_expected_updated_at`, …) as a JSON object; acceptance never accepts a raw function name.
- For this target, `record_id` follows the existing domain audit vocabulary for
  `visit_clinical_notes` (the visit id used by `save_visit_documentation`'s own
  `audit_log.record_id`).
- **Proof only:** registering this row promotes **no** product capability to
  `human_accept_required` writing (Open Decision 1; FR-011; T10). E4
  `advisory_display` accept remains non-writing (FR-018; T8).

**Out of registry:** `visit_plan_details` / `save_visit_plan_details` MUST NOT be registered or
tested as the demonstration target (spec Out of Scope).

---

## 7. Client clinical accept path (behavioural bind)

AI Feature Surfaces expose explicit accept/discard for the clinical accept path (§4.1; FR-013):

- **Accept** (clinical-content / demonstration harness path) invokes
  `public.record_ai_acceptance` with the terminal request reference, a registered `p_target_key`,
  and `p_target_args`.
- **Discard** writes nothing — no domain change, no `ai_accepted_output`, no acceptance audit
  (FR-013; T3).
- Unaccepted / provisional content is never persisted as a clinical write (FR-014; T4).
- No auto-commit of AI output (A5; FR-012; T7).
- First-capability `advisory_display` accept from E4 remains non-writing (FR-018; T8).
- Flutter clinical accept path embeds no prompt text, model names, provider names, or AI business
  rules (§4.1; FR-017).

Wire shapes above are the frozen clinic contracts; the Flutter modules under
`frontend/lib/features/ai/` are the behavioural bind points (same posture as E4 Feature Surfaces
Freezes).

---

## 8. Invariants checklist

| Invariant | Source |
| --- | --- |
| One shared RPC for every capability; enabling a target adds a registry row, never a second RPC | §4.2.2; Open Decision 14; FR-019 |
| Domain change + `ai_accepted_output` + `ai.acceptance_record` audit are one transaction | §4.2.2; FR-009 |
| Clinic stores the request reference handle only — no AI request state | §4.2 boundary note; FR-007, FR-016 |
| Demonstration target proves the mechanism without promoting product writing | §4.2.2; Open Decision 1; FR-011 |
| No platform taxonomy codes and no new clinic acceptance error vocabulary | §4.2.2; FR-005 |
| No D1 journal of acceptance; gateway has no write path into Supabase | §4.2; §14 |
