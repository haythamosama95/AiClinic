# ABO rebuild runbook

Operator procedure for FM-19 (ABO data loss or bad restore). Satisfies RC-04. The procedure ends with a clean reconciliation run.

## 1. Within 30 days of the damage

Restore the ABO D1 database with **Time Travel** to a point before the damage.

No ledger replay is required when Time Travel succeeds.

## 2. Otherwise — rebuild from the ledger

When Time Travel is not available (damage older than 30 days, or restore is unsuitable):

1. **Create an empty D1** for the ABO worker (drop existing tables or provision a fresh database and bind it).
2. **Replay** the `ledger/` NDJSON facts from R2 in `fact_seq` order. Inserts pass the append-only triggers. Status tables are recomputed from the replayed facts.
3. **Fill the gap** after the last exported fact:
   - Re-inquire every checkout and payment reference known to the rebuilt set.
   - Copy **provider transaction references** from the provider **dashboard export** for the gap window and pass them to the rebuild script.
4. **Compare with the platform** (`listGrants`). A paid grant with no payment is re-derived from provider inquiry. A payment with no grant receives a grant row; its `grant_id` is deterministic, so the platform answers `already_applied`.
5. **Confirm reconciliation** is clean (no open findings).

### Operator script

Run from the `abo/` directory:

```bash
npx tsx scripts/rebuild-abo.ts <provider-transaction-reference> ...
```

Before running the script, export the gap-window transactions from the provider dashboard. Copy each **provider transaction reference** from that **dashboard export** and pass it as a script argument. The script calls `rebuildAbo`, which replays `ledger/`, re-inquires the gap, compares grants, and ends with `runReconciliation`.

Implementation: `abo/src/rebuild.ts`. Operator wrapper: `abo/scripts/rebuild-abo.ts`.
