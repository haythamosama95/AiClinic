# P3.11 escalations

Assumptions chosen by the resolver. This entry amends no design document.

## 1. Dirty `.cursor/skills/abo-workflow/SKILL.md` during specify

**Question:** `.cursor/skills/abo-workflow/SKILL.md` is modified (31 insertions, 8 deletions). Specify must not occupy `075` or write `spec.md` while that file is dirty. The stop condition is a dirty tree: an uncommitted change outside the allowed paths (delivery-plan docs and this unit's `specs/075-abo-…/`).

**Assumption:** The unstaged edit to `.cursor/skills/abo-workflow/SKILL.md` is an orchestrator-owned local edit. It remains unstaged in the working tree for the whole unit. It is not committed, reverted, stashed, or edited. Specify, and every later stage of P3.11, proceeds on branch `ai/075-abo-p3-11-platform-rebuild-procedures-write-budget` while that single file stays dirty. Agents do not read it as a reason to stop, do not stage it, and do not modify it. No design document and no delivery plan needs amendment for this stop. `.cursor/` stays unchanged.

**Why:** The orchestrator owns that local edit and keeps it unstaged for the whole unit. Specify was blocked only while a dirty path sat outside the delivery plan and this unit's spec directory. P3.11 proceeds with that one file left dirty. The stop needs no design-document change and no delivery-plan change.

**Amended:** none (no design document amended).

## 2. Live entry point for the D1 `grant_ledger` / `grant_void` rebuild

**Question:** What live entry point runs the D1 rebuild of `grant_ledger` and `grant_void` from R2 `grant-ledger/` (E2E-P3.11-03)? 05 §5.3 states that rebuild, then a separate class-H method that asks every DO for a fresh snapshot. The Implements line marks the DO rebuild and the snapshot refresh as H methods (a `VendorEntrypoint` method over the H-AP service binding) and marks the load scenario as AI requests (`POST /v1/requests`). It does not mark the D1 rebuild as an HTTP route, a `VendorEntrypoint` method, `scheduled()`, a DO alarm, a PostgREST RPC, or a pg_cron job. The scenario's outcome (rebuilt rows identical to R2) is stated; the entry that produces it is not.

**Assumption:** The D1 rebuild of `grant_ledger` and `grant_void` from R2 `grant-ledger/` is a class-H `VendorEntrypoint` method, invoked over the H-AP self service binding. It is the same live-entry class already used for the DO rebuild and the snapshot refresh in the P3.11 Implements line. It stays a separate method from the snapshot refresh: 05 §5.3 still runs the ledger rebuild first, then the existing per-installation snapshot H method. No new route, cron, alarm, or RPC is added.

**Why:** P3.11 already classifies its other platform rebuilds as H methods on `VendorEntrypoint`. Class H is the operator entry that does not create or move value (02 §3.3), which fits copying existing R2 grant and void objects back into D1. Marking this rebuild `(H)` on the Implements line names the entry E2E-P3.11-03 calls, and matches the DO rebuild marker in the same sentence. 05 §5.3 already describes the rebuild steps and names only the following snapshot as an H method; the DO rebuild is likewise an H method only on the Implements line, so the delivery plan is the line that closes the entry-point gap.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P3.11 Implements line: `a D1 rebuild (H)`).
