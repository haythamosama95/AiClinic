# Contract: First context provider RPC (E3)

**Frozen by:** Slice E3 — Context Resolver registry, first context RPC, and client contract test  
**Implements:** §4.2 Context provider RPCs, §5.2 Shape / Authorization of
`docs/architecture/17-ai-platform.md`  
**Status:** Frozen. Later slices may add further ordinary context provider RPCs for additional
published keys; they must not rewrite this RPC’s return shape, RLS posture, or “no AI knowledge”
boundary.

**Source of truth in code (this slice):**
`backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql`
(`auth_internal` + `public` ordinary read for `visit.chief_complaint@v1`).

**Binds to (Consumes, not rewritten):** A5 first-key shape —
`specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md` /
`ai-platform/src/context/index.ts` (`VISIT_CHIEF_COMPLAINT_V1`, `VISIT_CHIEF_COMPLAINT_V1_SHAPE`).

**Traces to:** spec **Freezes** (first context provider RPC); FR-008–FR-010.

---

## 1. Overview

The first context provider is an **ordinary clinic read RPC**. It returns the platform-published
shape for `visit.chief_complaint@v1` under the caller’s own Supabase permissions and RLS. It has
no AI-specific knowledge and takes no AI-specific parameter — an RPC returning chief-complaint
domain data is not “an AI RPC” (§4.2 Boundary note).

---

## 2. Key and return shape

**Context key:** `visit.chief_complaint@v1`

**Return payload** (JSON object) — must pass A5 `validatePayload("visit.chief_complaint@v1", …)`:

| Field | Type | Cardinality | Units |
| --- | --- | --- | --- |
| `visit_id` | `string` | `required` | `uuid` |
| `complaint` | `string` | `{ maxLength: 10000 }` | `null` |
| `recorded_at` | `string` | `optional` | `iso8601` |

### 2.1 Conforming example

```json
{
  "visit_id": "550e8400-e29b-41d4-a716-446655440000",
  "complaint": "Persistent headache for three days.",
  "recorded_at": "2026-07-31T12:00:00.000Z"
}
```

`complaint` and `recorded_at` may be omitted when absent in clinic data; when `complaint` is
present its length MUST NOT exceed 10 000 characters (existing `visit_clinical_notes` check).

---

## 3. Authorization

| Rule | Source |
| --- | --- |
| Resolution under the caller’s own session, permissions, and RLS | §5.2 Authorization; §4.2 |
| Out-of-scope rows denied — no privileged bypass | §4.1 Must not; §4.2 Must not / Notes |
| Prefer reuse of existing clinic storage (`visit_clinical_notes`) and visit RLS | §4.2; FR-009 |

---

## 4. Signature constraints (no AI knowledge)

The RPC MUST NOT:

| Forbidden | Examples |
| --- | --- |
| AI-specific parameters | capability id, prompt id, provider/model, quota, AI request reference as an input that changes read semantics |
| Encode AI platform knowledge | prompts, providers, quotas, AI request state in the function body or return |

Clinic identity parameters that ordinary visit reads already use (e.g. `p_visit_id uuid`) are
allowed. The public surface follows the established `public` INVOKER → `auth_internal` SECURITY
DEFINER pattern.

---

## 5. Naming

| Layer | Role |
| --- | --- |
| `public.get_visit_chief_complaint(p_visit_id uuid)` | INVOKER wrapper callable by the authenticated client |
| `auth_internal.get_visit_chief_complaint(p_visit_id uuid)` | SECURITY DEFINER implementation under caller RLS |

The RPC name is clinic-side implementation; the **context key** remains `visit.chief_complaint@v1`
(meaning, not storage — §5.2). The Flutter registration map binds that key to this RPC via the
clinic-read port.

---

## 6. Resolver binding

The Context Resolver’s closed registration map registers
`visit.chief_complaint@v1` → a resolver function that invokes this RPC and returns the payload
above. The Resolver MUST NOT reshape field names away from the A5 published shape.
