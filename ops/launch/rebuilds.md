# Rebuild procedures (05 §5)

Each procedure ends with a clean reconciliation run.

## ABO (05 §5.1)

1. Within 30 days of the damage, restore D1 with Time Travel to a point before it.
2. Otherwise, create an empty D1, replay the `ledger/` NDJSON facts in `fact_seq` order (inserts pass the append-only triggers), then recompute the status tables.
3. Fill the gap after the last exported fact: re-inquire every checkout and payment reference known to the rebuilt set, and every transaction in the provider's dashboard export for the gap window.
4. Compare with the platform's `listGrants`. A paid grant with no payment is re-derived from the provider inquiry; a payment with no grant gets a grant row (its `grant_id` is deterministic, so the platform answers `already_applied`).
5. Run a clean reconciliation pass.

## Clinic DO (05 §5.2)

1. Load the clinic's last `coverage_event` snapshot (its terms, positions, usage, holds, suspension and epoch) into an empty DO.
2. Apply, in order, every later `grant_ledger` and `grant_void` row and every later hold, release, suspension and transfer event.
3. Re-apply usage recorded after the snapshot from `usage_event` by `term_id`, including shipped `usage_adjustment` rows; `request_id` uniqueness prevents double counting. Retention keeps these rows while their term is unended (03 §8).
4. Compare the result with `coverage_mirror` and alert on any difference. Reservations in flight at the loss are forfeited to the clinic's benefit.
5. Run a clean reconciliation pass.

## Platform D1 (05 §5.3)

1. Restore with Time Travel within 30 days.
2. Otherwise rebuild `grant_ledger` and `grant_void` from the R2 `grant-ledger/` objects.
3. Ask every DO for a fresh snapshot event (an H method run once per installation), which also rebuilds `coverage_mirror`.
4. Run a clean reconciliation pass.

## Backend projection (05 §5.4)

1. Reset `feed_state.cursor` to 0. `coverage_event` is never purged, so the replay reproduces every clinic's latest snapshot.
2. Run a clean reconciliation pass.
