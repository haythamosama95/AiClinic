# Contract: feedConsumerHealth

**Unit**: P3.9 · **Requirements**: FR-007

Later units bind to this file for `feedConsumerHealth`.

## 1. Call

Class M on `VendorEntrypoint`. Argument `{contract_version}` only. No Access JWT and no assertion. `contract_version` is checked first with the existing vendor-channel `negotiate`. A rejected version is `rejected` with that code and writes nothing.

The method reads `feed_consumer` where `consumer` is `backend-feed`. It does not write.

## 2. Success

`result` is `ok`, `code` is `""`, and `receipt` is absent. `detail` is the JSON text of:

```json
{ "last_pull_at": null, "last_cursor": null }
```

Before the first successful feed pull both values are null. After a pull, `last_pull_at` is that pull's UTC ISO-8601 time and `last_cursor` is that pull's `next_after`.
