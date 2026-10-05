# Contract: listGrants

**Unit**: P3.3 · **Requirements**: FR-016

Later units bind to this file for `listGrants`.

## 1. Call

Class M. Argument beyond `contract_version`: `org_id`, `source_kind`, `credential_id`, `applied_from`, `applied_to`. Each filter is optional. An omitted filter does not constrain that column. `credential_id` matches `operator_credential_id`. `applied_from` and `applied_to` are inclusive UTC ISO-8601 bounds on `applied_at`.

`contract_version` is checked first. The method reads `grant_ledger` only. Rows exist after the alarm has shipped.

## 2. Success

`result` is `ok`, `code` is `""`, and the envelope `receipt` is absent. `detail` is the JSON text of the matching rows, ordered by `applied_at` then `grant_id` ascending.

Each row object has keys, in this order: `grant_id`, `origin_grant_id`, `org_id`, `installation_id`, `kind`, `source_kind`, `operator_credential_id`, `envelope_sha256`, `receipt`, `applied_at`. `receipt` is the receipt object, not a string.
