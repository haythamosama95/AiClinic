# Contract: `usage_rollup` production and reconciliation (F3)

**Frozen by:** Slice F3 — Support lookup, retention purges, usage rollups, and journal dashboards
**Implements:** §7.6 (Billing period close / Analytics), R-6 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (including band G commercial surfaces) may **extend** rollup
dimensions or report consumers; they may not **rewrite** ledger-as-evidence, equality-to-ledger,
idempotent re-run, or the two reconciliation flags (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/rollup/index.ts`; Worker scheduled handler in
`ai-platform/src/worker.ts`.

**Traces to:** spec **Freezes** (`usage_rollup` production job); FR-011–FR-014.

**Consumes (unchanged):** A5 `usage_event` / `usage_rollup` shapes; C3 stage-16 `usage_event`
write; B4 credit RPC (evidence of usage settlement — detected by absence, not rewritten).

---

## 1. Overview

A scheduled job produces `usage_rollup` from `usage_event`. The ledger is the **evidence**;
rollups are the **convenience** (§7.6). A reconciliation pass reports requests that have a
terminal state but missing attempt rows or missing usage credit (R-6). A re-run is idempotent.

Band G commercial usage-summary / invoice surfaces remain out of scope.

---

## 2. Rollup production

| Property | Value |
| --- | --- |
| **Input** | `usage_event` rows for the job window |
| **Output** | `usage_rollup` rows (`rollup_id`, `dimensions`, `request_count`, `tokens`, `cost` — A5 shape) |
| **Equality** | Rollup totals for a window MUST equal the corresponding `usage_event` ledger sums (FR-012; T10) |
| **Idempotent re-run** | Re-running the same window MUST NOT duplicate totals; outcome remains equal to ledger sums (FR-012; T13) |
| **Schedule** | Worker cron (wrangler); off the inference request path |

Idempotency strategy (upsert by natural dimensions key / replace-window) is an implement detail
that must satisfy equality + no duplication; it must not alter the A5 `usage_rollup` column set.

---

## 3. Reconciliation report

Operational detection artifact (not a second metrics store; not a new D1 entity required by this
freeze). Produced by the same scheduled pass (or immediately chained job).

### 3.1 Flag: missing attempt rows

| Condition | Report |
| --- | --- |
| `ai_request` has a **terminal** state (`Completed` / `Failed` / `Cancelled` as journaled by C3) **and** zero `ai_attempt` rows for that `request_id` | Include on report (FR-013; T11; R-6 detection) |

### 3.2 Flag: missing usage credit

| Condition | Report |
| --- | --- |
| `ai_request` has a **terminal** state **and** missing post-response usage settlement evidence | Include on report (FR-014; T12) |

**“Missing usage credit”** means absence of the durable settlement evidence the architecture
requires — specifically no settling `usage_event` for that request (C3 stage-16 ledger row),
which is the platform-side evidence paired with B4’s credit path. Detection is against requests
that already have a durable terminal state (R-6). F3 does not call or rewrite the Quota DO credit
RPC to perform this check.

### 3.3 Report shape

```typescript
type ReconciliationReport = {
  window: { start: string; end: string };
  missingAttemptRows: Array<{ requestId: string; requestReference: string }>;
  missingUsageCredit: Array<{ requestId: string; requestReference: string }>;
};
```

Re-run over the same window remains consistent (same membership for unchanged seed data; T13).

---

## 4. Prohibitions

- Must not treat rollups as authoritative over `usage_event`.
- Must not journal guard rejections as requests or write D1 per stream chunk.
- Must not add a second metrics store for reconciliation (journal/ledger only).
