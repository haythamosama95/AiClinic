# Contract: Retention purge policy (F3)

**Frozen by:** Slice F3 — Support lookup, retention purges, usage rollups, and journal dashboards
**Implements:** §7.7, Open Decision 4 / A10 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices may **extend** horizons or purge entrypoints; they may not
**rewrite** the four-class table, the per-capability diagnostic rule, the in-horizon prohibition,
or purge-by-installation-id across D1 and R2 (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/retention/index.ts`; Worker cron / control-plane
installation-purge wiring in `ai-platform/src/worker.ts` and `ai-platform/src/control/index.ts`.

**Traces to:** spec **Freezes** (retention purge policy); FR-007–FR-010, FR-018.

**Consumes (unchanged):** C3 envelope key `request/{id}/envelope`; B4 ephemeral in-place expiry
(`EPHEMERAL_HORIZON_MS`); A4/C1 `Governance.retentionClass` on capability manifests.

---

## 1. Overview

Retention expires each class on its own horizon. The diagnostic envelope’s horizon is
**per-capability** via the manifest retention class. An installation deletion is executable as
**purge by installation id** in both D1 and R2. Nothing still inside its horizon is deleted
(§7.7; Open Decision 4).

---

## 2. Retention classes

| Class | Applies to | Default horizon (architecture band) | F3 default constant | Expiry mechanism |
| --- | --- | --- | --- | --- |
| `diagnostic` | R2 payload envelope (prompt, context, raw responses, result) | Days to weeks; short by default, extendable per capability | **7 days** baseline; override via manifest `retentionClass` (e.g. `diagnostic_30d` → 30 days) | Scheduled purge deletes past-horizon R2 objects |
| `journal` | `ai_request`, `ai_attempt` metadata | Months | **90 days** | Scheduled purge deletes past-horizon D1 rows as a unit. Before deleting requests, `usage_event.request_id` is set NULL so ledger rows may retain years of commercial evidence with a nulled FK. |
| `ledger` | `usage_event`, `usage_rollup`, `control_audit`, `capability_grant` | Years | **2555 days** (~7 years) | Scheduled purge deletes past-horizon D1 rows |
| `ephemeral` | `jti` replay and idempotency records inside the Quota DO | Minutes to hours | **B4 `EPHEMERAL_HORIZON_MS` (2 hours)** — unchanged | Expire **in place** inside the DO; **no** D1/R2 table to prune |

Horizon clocks use the durable timestamp already on the row/object (e.g. request
`created_at` / `completed_at`, `usage_event.recorded_at`, `control_audit.recorded_at`, envelope
associated request time). Exact column choice per class is an implement detail within this policy.

---

## 3. Per-capability diagnostic horizon

- Retention class is a **per-capability** manifest Governance field (`retentionClass`).
- Production wiring uses `createManifestRetentionClassResolver()` (eager-bundled
  `manifests/published/*.json`) in support lookup and the scheduled purge; unknown
  capabilities fall back to the diagnostic baseline via `defaultRetentionClassResolver`.
- When two capabilities differ, a purge run at a time between their horizons deletes only the
  shorter-horizon capability’s envelopes (FR-008; T8).
- Unknown / missing `retentionClass` falls back to the diagnostic baseline (7 days).

F3 **reads** manifests; it does not redefine the A4/C1 Governance field set.

---

## 4. Invariants

1. **No in-horizon delete** — a purge MUST NOT delete any row or object still inside its class
   horizon (FR-009).
2. **Ephemeral is not pruned from D1/R2** — F3 proves B4 in-place expiry; it adds no ephemeral
   table (FR-007; T7).
3. **One R2 object per request remains the layout** — purge deletes the C3 envelope key; it does
   not invent additional objects.

---

## 5. Purge by installation id

| Property | Value |
| --- | --- |
| **Trigger** | Operator-authenticated control-plane action (installation deletion recovery path §7.7); may be invoked alongside or after B2 lifecycle `delete` without rewriting enroll/suspend/resume/rotate |
| **D1** | Delete platform rows scoped to that `installation_id`: journal (`ai_request` / `ai_attempt`), `usage_event`, `usage_rollup` (via `json_extract(dimensions, '$.installation_id')`), and `platform_counter` (via `json_extract(dimension_set, '$.installation_id')`) |
| **R2** | Delete envelopes for that installation’s requests |
| **Isolation** | Other installations untouched |
| **Audit** | Mutation journaled to `control_audit` with **operator identity** (FR-018; reuse B2 pattern) |

B2’s existing `delete` marks installation status and writes audit; F3 supplies the **purge stores**
recovery executable named by §7.7. F3 does not redefine B2 lifecycle semantics beyond executing
this purge path (spec Out of Scope).

---

## 6. Scheduled class-horizon purge

Worker cron (wrangler triggers) invokes the retention job. Scheduled horizon expiry is a system
job (not clinic identity). Operator-triggered installation purge remains operator-audited per §5.

---

## 7. Relationship to support lookup

Support lookup treats an envelope as “within diagnostic retention” using the same per-capability
horizon rules frozen here (`contracts/support-lookup.md` §6).
