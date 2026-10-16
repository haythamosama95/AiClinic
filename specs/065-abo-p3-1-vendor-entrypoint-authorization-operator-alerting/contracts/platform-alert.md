# Contract: `platform_alert`

**Unit**: P3.1 · **Requirements**: FR-019, FR-020, FR-021, FR-023

Later units bind to this file for the vendor alert row and the `*/5` branch. Columns are `data-model.md` section 4. The email text is `contracts/alert-body.md`.

## 1. Dedupe and send

Insert on the first raise of an `alert_key`. A later raise of the same key increments `count`, sets `last_at`, and does not insert a second row.

`src/alert/email.ts` calls `env.SEND_EMAIL.send`. Success sets `send_state` to `sent`. A throw leaves `send_state` `unsent`, sets `next_send_at` to the clock's now, and does not throw out of the retry job.

The `*/5` retry selects `send_state = unsent` and sends each selected row once. A row already `sent` is not sent again (AL-13 repeats once).

## 2. `*/5` branch

`scheduled` on cron `*/5 * * * *` runs, in order:

1. `alert_retry` — the unsent send above.
2. `heartbeat` — `fetch(HEARTBEAT_URL)`. H-AP records that outbound fetch.

Each job is wrapped. A throw logs one JSON line and inserts `scheduled_job_failed`:

```json
{"cron":"*/5 * * * *","job":"<job>","error":"<message>"}
```

The line is `console.log` of that JSON text. `src/logger.ts` is unchanged.

`send_email` throwing is handled inside `alert_retry` and is not a job failure. A thrown heartbeat `fetch` is a job failure.

The existing `0 3 * * *`, `0 4 * * *`, and `0 5 1 * *` branches are unchanged and do not raise `platform_alert`.
