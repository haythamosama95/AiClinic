# P3.11 research

Spike R-7 (06 §2 S6). One command, no install (`ai-platform/node_modules` is present).

## 1. Outcome

The DO schema in `ai-platform/src/quota-do/index.ts` (`COVERAGE_DO_SCHEMA_STATEMENTS`) is the §3.2 layout.

- Tables are `hot`, `term`, `grant`, and `outbox`.
- `hot.reservations`, `hot.replay`, and `hot.idempotency` are JSON text columns on the one `hot` row.
- That block has no `CREATE INDEX`.
- It has no table named `reservation`, `idempotency_key`, or `usage_record`.

The naive layout (a row per reservation, idempotency key, or usage record, plus indexes, about 8 row writes per AI request) is not present. Installed Workers types do not expose a `rowsWritten` field. The load scenario measures the same quantity with SQLite `total_changes()` around admission and settlement.

## 2. Fallback

The R-7 row names this fallback: the §3.2 bound. One `hot` row per clinic, reservations and replay entries swept on that write, no secondary indexes, admission and settlement each write `hot` once, and `term`, `grant`, and `outbox` rows only on events.

That is the layout already in the DO. This unit keeps it. It does not add a per-reservation table, a per-usage table, or a secondary index. E2E-P3.11-05 measures `total_changes()` against that bound.
