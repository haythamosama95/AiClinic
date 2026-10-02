# Contract: Alert body

**Unit**: P3.1 · **Requirements**: FR-019, FR-022, FR-025

Later units bind to this file for the text handed to `send_email`. The destination is the `SEND_EMAIL` binding's `destination_address`, the same address as `ALERT_EMAIL_TO`. The worker passes that address as both `from` and `to`. `subject` is the `code`. `text` is the JSON below, one object, no extra keys.

H-AP captures the argument `src/alert/email.ts` passes to `env.SEND_EMAIL.send`. Credential bodies carry codes and ids, plus the decoded operation. The scheduled-job body carries codes and ids only.

## 1. AL-13

`text` is JSON:

| Field | Value |
| --- | --- |
| `code` | `"AL-13"` |
| `credential_id` | The credential id. |
| `operator_email` | The row's `operator_email`. |
| `kind` | `"bootstrap"`, `"register"`, or `"revoke"`. Bootstrap is the empty-registry registration. |
| `operation` | `null` for bootstrap. Otherwise the operation object `{op, params, actor_email, issued_at, nonce, contract_version}` that verified for that call. |

Raised for bootstrap, for a register that inserts a row, and for a revoke that returns `ok`. An idempotent register that does not insert does not raise another AL-13. A `rejected` second unapproved registration does not raise AL-13.

## 2. Scheduled job failure

`text` is JSON:

| Field | Value |
| --- | --- |
| `code` | `"scheduled_job_failed"` |
| `cron` | `"*/5 * * * *"` |
| `job` | The job name. This unit's jobs are `alert_retry` and `heartbeat`. |

`send_email` throwing inside `alert_retry` does not raise this body. That alert stays `unsent` and the retry job itself completes (`contracts/platform-alert.md`). A thrown heartbeat `fetch` uses `job` `"heartbeat"`.
