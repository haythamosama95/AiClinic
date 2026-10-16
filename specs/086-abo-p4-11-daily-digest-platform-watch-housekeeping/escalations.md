# P4.11 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Housekeeping scheduled job

**Question:** Which scheduled job deletes completed work rows and sent alerts after 90 days, and invalid-HMAC samples after 30 days? 03 §8 states those retention periods. The ABO hourly and daily rows in 05 §1 do not name a housekeeping job. E2E-P4.11-05 deletes 91-day-old done work rows and sent alerts and leaves facts untouched, but no Read span names an HTTP route, `scheduled()` cron, Durable Object alarm, RPC, or other live entry that performs that deletion.

**Assumption:** Housekeeping is not a new cron. It runs inside the ABO daily 06:00 UTC job, the Worker `scheduled()` handler for cron `0 6 * * *` (the same run as reconciliation, the digest, the R2 lock check, the key-expiry check, and the daily heartbeat). That run deletes completed work rows and sent alerts older than 90 days, and invalid-HMAC samples older than 30 days (03 §8). It does not delete commercial facts.

**Why:** 03 §8 already sets those two retention periods, and the delivery plan already assigns that deletion to P4.11. 05 §1 already has one ABO daily schedule, Daily 06:00 UTC, and `abo/wrangler.toml` already declares that trigger as `0 6 * * *` on the Worker `scheduled()` handler. Retention is measured in days, so it belongs on that daily run. The platform `0 3` / `0 4` crons purge platform usage, not ABO work rows, alerts, or HMAC samples.

**Amended:** `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md` (§1 ABO daily row: `scheduled()`, `0 6 * * *`, housekeeping deletion); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P4.11 Implements and E2E-P4.11-05 name that same cron).

## 2. AL-13 operator-credential list

**Question:** How does the ABO obtain the operator-credential list “announced by AL-13” that the hourly AL-22 comparison uses? 05 §1 (ABO hourly row) and 05 §2 row AL-22 require comparing `listOperatorCredentials` with the credentials the ABO has seen announced by AL-13 (its last-seen list). AL-13 is raised by the AI Platform. No cited span names an intake, stored list, or other entry the ABO uses to learn that announcement.

**Assumption:** The last-seen list is the stored list the hourly row already names. The ABO appends `{credential_id, public_key_cose, alg}` from the `detail` of its own `ok` `registerOperatorCredential` call, including bootstrap. That call is the operation AL-13 announces, and 04 §1.3 already returns the `operator_credential` row in `detail`. The hourly job compares `listOperatorCredentials` (the existing class-M read) with that list and raises AL-22 when an active triple is absent. A credential stored while `pending` is not a new appearance when it later becomes `active`. The platform's `send_email` is not an intake, and no new read is added.

**Why:** AD-9 is a compromised platform that can inject an operator credential and suppress its own alerts, so the list cannot be filled from `send_email` or from `listOperatorCredentials` itself. The ABO already receives the credential row as the caller of the register call that causes AL-13, and the hourly row already names the last-seen list those rows accumulate. `listOperatorCredentials` is already the platform side of the comparison.

**Amended:** `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md` (§1 ABO hourly row; §2 row AL-22); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P4.11 Implements and E2E-P4.11-04). 04 was not amended.
