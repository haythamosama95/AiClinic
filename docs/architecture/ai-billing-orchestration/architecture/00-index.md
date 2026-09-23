# AI Billing Orchestration — Architecture Index

**Status:** Architecture — decided
**Date:** 2026-09-11
**Scope:** The vendor-side AI Billing Orchestrator Worker (purchase + orchestrator modules), the ai-platform
control-plane trust refactor, clinic Supabase changes, and Flutter purchase/activation flows.
**Related:** [`../01-proposal.md`](../01-proposal.md) (agreed decisions, verification findings, attack model),
[`../../ai-platform/01-ai-platform.md`](../../ai-platform/01-ai-platform.md) (§8.1, §12.5, A15, A16),
[`../../ai-platform/03-ai-platform-delivery-plan.md`](../../ai-platform/03-ai-platform-delivery-plan.md),
[`../04-abo-delivery-plan.md`](../04-abo-delivery-plan.md).

---

## Table of Contents

- [Start here](#start-here)
- [Architecture parts (§1–§15)](#architecture-parts-1-15)
- [Section index (§ → part)](#section-index-part)
- [How to use this corpus](#how-to-use-this-corpus)

### Start here

- [Overview — map, layers, trust chain, happy path](01-overview.md)

### Architecture parts (§1–§15)

1. [Context and deployables (§1–§2)](02-context-and-deployables.md)
2. [Trust model and key management (§3)](03-trust-and-keys.md)
3. [Data model (§4)](04-data-model.md)
4. [Wire contracts (§5)](05-wire-contracts.md)
5. [State machines and dunning policy (§6)](06-lifecycle-and-policy.md)
6. [Payment adapter, cron, ops, reconciliation (§7, §11)](07-billing-worker-ops.md)
7. [Platform-side changes (§8)](08-platform-changes.md)
8. [Clinic-side changes (§9)](09-clinic-changes.md)
9. [Flutter flows (§10)](10-flutter-flows.md)
10. [Security traceability, open items, deviations, constitution (§12–§15)](11-governance.md)

### Section index (§ → part)

| § | Topic | Part |
| --- | --- | --- |
| — | Overview (read first) | [01-overview.md](01-overview.md) |
| §1–§2 | Context, deployables, repo layout | [02-context-and-deployables.md](02-context-and-deployables.md) |
| §3 | Trust model, keys, rotation | [03-trust-and-keys.md](03-trust-and-keys.md) |
| §4 | Billing + platform D1 | [04-data-model.md](04-data-model.md) |
| §5 | HTTP/JWS wire contracts | [05-wire-contracts.md](05-wire-contracts.md) |
| §6 | Order/entitlement lifecycle, dunning | [06-lifecycle-and-policy.md](06-lifecycle-and-policy.md) |
| §7 | Payment provider adapter | [07-billing-worker-ops.md](07-billing-worker-ops.md#7-payment-provider-adapter) |
| §8 | ai-platform control-plane changes | [08-platform-changes.md](08-platform-changes.md) |
| §9 | Clinic Supabase RPCs | [09-clinic-changes.md](09-clinic-changes.md) |
| §10 | Flutter purchase/activation UX | [10-flutter-flows.md](10-flutter-flows.md) |
| §11 | Cron, ops endpoints, reconciliation | [07-billing-worker-ops.md](07-billing-worker-ops.md#11-scheduled-work-and-billing-reconciliation) |
| §12–§15 | Security matrix, resolutions, deviations, constitution | [11-governance.md](11-governance.md) |

---

## How to use this corpus

Read [the overview](01-overview.md) first, then follow the parts that match your role.
Section numbers (**§N**, **§N.M**) are stable across all part files — [`../04-abo-delivery-plan.md`](../04-abo-delivery-plan.md)
and feature specs cite them by number; use the table above to open the right file.

The parent series entry point is [`../02-architecture-toc.md`](../02-architecture-toc.md) (folder-level pointer).
This file is the master TOC for everything under `architecture/`.
