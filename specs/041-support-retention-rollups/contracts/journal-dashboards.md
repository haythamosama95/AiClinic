# Contract: Named journal dashboards (F3)

**Frozen by:** Slice F3 — Support lookup, retention purges, usage rollups, and journal dashboards
**Implements:** §13.1, §7.6 (Analytics and dashboards) of `docs/architecture/ai-platform/01-ai-platform.md`
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

| Id | Diagnostic | Primary source columns / tables | Honesty notes |
| --- | --- | --- | --- |
| `ttft_by_provider` / `avg_attempt_latency_by_provider` | Average first-attempt latency by provider | `ai_attempt.latency_ms` where `attempt_no = 1`, grouped by `provider` | Reports **first-attempt total latency**, not true TTFT — time-to-first-token is not journaled. Code export: `dashboardAvgAttemptLatencyByProvider` (`dashboardTtftByProvider` is a deprecated alias). |
| `validation_failure_by_prompt_version` | Validation-failure rate by prompt version | `ai_request.prompt_artifact_hash` + `terminal_error_code = 'validation_failed'` | Denominator is `state IN ('Completed', 'Failed')` only — `Cancelled` / `AwaitingContext` must not dilute. |
| `repair_rate_by_capability` | Repair rate by capability | Named diagnostic id retained | **Unavailable** until `RepairJournalSink` is persisted on the write path. Function returns empty `{}` rather than querying a never-written `outcome='repair'`. |
| `fallback_rate_by_provider` | True provider-fallback rate by provider | `ai_attempt` compared to the previous attempt's provider | `selection_reason` is not in D1. Heuristic: an attempt is a fallback when its `provider` differs from the previous attempt (`attempt_no - 1`) on the same request; rate = fallback attempts for that provider / all attempts for that provider. Same-provider retries do not count. |
| `cost_per_capability_per_installation` | Cost per capability (+ version) per installation | `ai_attempt.cost` joined to `ai_request` | Grouped by `capability_id`, `capability_version`, and `installation_id` ("+ version as stored"). |
| `quota_rejection_rate` | Quota rejection approximation | `platform_counter` (quota) + `ai_request` count | Rate = `SUM(count)` where `dimension_set LIKE '%quota_exhausted%'` / `COUNT(*)` of journaled `ai_request`. Approximation of rejections per request; returns `0` when request count is 0. Do not use fabricated `ok` counters as denominator. |

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
