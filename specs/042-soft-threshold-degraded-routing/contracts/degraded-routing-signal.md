# Contract: Gateway `routing_tier` and `degraded_notice` (F4)

**Frozen by:** Slice F4 — Soft-threshold degraded routing  
**Implements:** §4.3.7, §8.8 of `docs/architecture/17-ai-platform.md`  
**Consumes (unchanged):** D2 routing-policy-as-data (`specs/029-provider-port-routing/contracts/routing-decision.md`);
C3 request-row writer (`specs/027-journal-writer-get-request/contracts/journal.md`);
A5 `ai_request.routing_tier` column (`specs/019-ai-context-keys-d1-config/data-model.md` §2.6);
A2 `period_reset` / A6 accepted-event framing  
**Status:** Frozen. Later slices may extend these signals and may not rewrite them (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/soft-threshold/index.ts` (gateway-internal
`routing_tier` / `degraded_notice` derivation); `ai-platform/src/router/index.ts` (D2 — consumed,
not rewritten); `ai-platform/src/journal/index.ts` (persist `routing_tier` only);
`ai-platform/src/adapter.ts` (accepted-event `degraded_notice` extension).

**Traces to:** spec Freezes (`routing_tier` signal; soft-threshold → degraded-tier path;
`degraded_notice`); FR-002, FR-006, FR-007, FR-008, FR-010.

---

## 1. Gateway-internal `routing_tier`

| Admission allow | In-memory `routing_tier` |
| --- | --- |
| `degraded: true` | `"degraded"` |
| otherwise (below soft / grace allow without soft signal) | `"standard"` |

- The tier is **never** accepted from the client — no request header, body field, or query
  parameter may set it (§4.3.7; FR-008).
- The tier is what is persisted as `ai_request.routing_tier` (A5 column; FR-006).
- F4 writes **only** `routing_tier`. Persisting `routing_decision` remains out of F4 scope
  (escalation resolution; D2 / later journal wiring).

---

## 2. Soft-threshold → degraded-tier routing path

With `routing_tier = "degraded"`, the D2 provider router matches `rules[].match.tiers` for the
degraded tier and selects that rule's target chain (FR-007). With `"standard"`, the standard-tier
chain is selected (FR-010).

F4 supplies the `RouterContext.routingTier` signal D2 already matches. F4 does **not** redefine
policy document shape, cost-class selection, feature filtering, installation overrides, catch-all
rules, or the provider port (D2 Freezes). Empty or missing degraded-tier rules remain a policy-data
problem under D2's first-match / catch-all rules.

---

## 3. Client-visible `degraded_notice`

On the soft-threshold accept path the opening `accepted` SSE event carries:

```ts
{
  type: "accepted",
  data: {
    request_reference: string; // A2 / A6 — unchanged
    trace_id: string;          // A2 / A6 — unchanged
    degraded_notice?: boolean; // F4: true on soft-threshold allow; omitted otherwise
  }
}
```

- Soft-threshold allow → `degraded_notice: true` (FR-008).
- Below-threshold allow → field omitted (not `false` as a soft-threshold signal) (FR-010).
- The client cannot send `degraded_notice` or a tier; only the gateway emits it.

This **extends** A6's `accepted` event data without rewriting SSE framing, vocabulary, or the
one-terminal-event invariant (`specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md`).

---

## 4. Persistence through C3's request-row writer

`createRequestRow` / `RequestRowInput` accepts gateway-set `routingTier: "standard" | "degraded"`
and writes it to `ai_request.routing_tier`. No migration belongs to F4 — the nullable column is
A5's (§7.3; A5 data-model §2.6). F4 does not rewrite C3's stage-9 timing, transition stamping,
post-response detail, get-request, or R2 envelope (C3 Freezes).

---

## 5. Verification

| Named test | Asserts |
| --- | --- |
| `soft_threshold_selects_degraded_target` | `routing_tier = degraded` → degraded chain; `accepted { degraded_notice }` |
| `below_threshold_traffic_unaffected` | `routing_tier = standard`; no `degraded_notice` |
| `soft_threshold_tier_not_accepted_from_client` | Client-supplied tier / trigger ignored |
| `soft_threshold_persists_routing_tier` | `ai_request.routing_tier` = gateway-set value |
