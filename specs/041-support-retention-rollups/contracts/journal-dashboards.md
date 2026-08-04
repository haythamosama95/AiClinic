# Contract: Named journal dashboards (F3)

**Frozen by:** Slice F3 — Support lookup, retention purges, usage rollups, and journal dashboards
**Implements:** §13.1, §7.6 (Analytics and dashboards) of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices may **extend** additional diagnostics; they may not **rewrite**
the six named questions, the journal-side metrics rule, or the prohibition on a second metrics
store (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/dashboards/index.ts`.

**Traces to:** spec **Freezes** (named journal dashboards); FR-015–FR-017.

**Consumes (unchanged):** A5/`C3` journal columns on `ai_request` / `ai_attempt`; `usage_rollup`;
`platform_counter` (pre-journal guard rejections).

---

## 1. Overview

Operational dashboards answer the named diagnostics by **query** against
`ai_request` / `ai_attempt` / `usage_rollup` / `platform_counter` in D1 (and Workers tracing/logs
for traces only, as §13.1 already separates). There is **no second metrics store** (§13.1; §9.16
condition to reverse is out of scope).

Analytics and dashboard reads are **read-only** and **off the request path** (FR-017).

---

## 2. Logs vs journal

| Signal | Store | F3 role |
| --- | --- | --- |
| Trace / structured logs | Workers tracing / logs | Not a dashboard source of truth |
| Metrics | Queried from D1 journal + `usage_rollup` | F3 implements the six named queries |
| Counters | `platform_counter` | Quota rejection rate and other pre-journal signals |
| Journal | D1 + R2 | Audit / support (support lookup is separate) |

Every dashboard dimension is already a column (or rollup/counter aggregate) on data written
regardless — querying MUST NOT require a store of its own and MUST NOT be able to disagree with
the audit trail (FR-016).

---

## 3. Named diagnostics

| Id | Diagnostic | Primary source columns / tables |
| --- | --- | --- |
| `ttft_by_provider` | Time to first token by provider | `ai_attempt` latency / provider (and any TTFT field already journaled); aggregate by provider |
| `validation_failure_by_prompt_version` | Validation-failure rate by prompt version | `ai_request.prompt_artifact_hash` + terminal / error codes indicating validation failure |
| `repair_rate_by_capability` | Repair rate by capability | Journal attempt/repair signals by `capability_id` (+ version as stored) |
| `fallback_rate_by_provider` | Fallback rate by provider | Multi-attempt / fallback outcomes by provider on `ai_attempt` |
| `cost_per_capability_per_installation` | Cost per capability per installation | `usage_rollup` and/or `usage_event` / attempt cost dimensions |
| `quota_rejection_rate` | Quota rejection rate | `platform_counter` (and journal where applicable) for quota/admission rejections |

Exact SQL is an implement detail; each named test asserts correct values against a **seeded**
journal (T14–T19).

---

## 4. No second metrics store

| Prohibition | Assertion |
| --- | --- |
| No Analytics Engine / parallel metrics table / dual-write metrics stream introduced by this slice | Spy test `dashboard_no_second_metrics_store` (T20) |
| Dashboard modules are read-only SELECT/aggregate | No INSERT into a metrics-only store |

---

## 5. Control-plane surface

Operational dashboards are a §4.5 control-plane concern. Exposure MAY be operator-authenticated
query helpers / internal functions invoked by tests and ops tooling. F3 does not require a public
clinic-facing metrics API (band G remains out of scope).
