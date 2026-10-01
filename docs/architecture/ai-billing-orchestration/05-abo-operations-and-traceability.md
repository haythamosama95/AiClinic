# AI Billing Orchestrator — Operations, Failure Modes and Traceability

**Status:** Phase 2 design. **Date:** 2026-10-01. Requirement IDs refer to the [seed](00-abo-requirements-seed.md); "01 §n" to "04 §n" to the [decision memo](01-abo-design-decisions.md), [architecture and threat model](02-abo-architecture-and-threat-model.md), [data model](03-abo-data-model-and-lifecycle.md) and [contracts](04-abo-contracts.md).

Start with section 0. It explains the purpose, the systems involved and every term used later. Sections 1 to 10 keep their numbers, and the alert ids (AL-…) and failure ids (FM-…) keep their values, because the other design documents cite them (for example "05 §3.3" or "AL-23").

## Table of Contents

0. [Start here: the big picture](#0-start-here-the-big-picture)
   - [What we are trying to achieve](#01-what-we-are-trying-to-achieve)
   - [The whole system in one analogy](#02-the-whole-system-in-one-analogy)
   - [The systems involved](#03-the-systems-involved)
   - [Business words](#04-business-words)
   - [Technical words](#05-technical-words)
   - [A day in the life of the operator](#06-a-day-in-the-life-of-the-operator)
   - [How to read the rest of this document](#07-how-to-read-the-rest-of-this-document)
1. [Scheduled work](#1-scheduled-work)
2. [Alerts](#2-alerts)
3. [Operator console](#3-operator-console)
   - [Views](#31-views)
   - [Actions](#32-actions)
   - [Reconciliation](#33-reconciliation)
   - [Daily digest](#34-daily-digest)
4. [Failure modes and recovery](#4-failure-modes-and-recovery)
5. [Rebuild procedures](#5-rebuild-procedures)
   - [ABO](#51-abo)
   - [A clinic's DO](#52-a-clinics-do)
   - [Platform D1](#53-platform-d1)
6. [Staging and launch](#6-staging-and-launch)
   - [Staging profile](#61-staging-profile)
   - [Launch conditions](#62-launch-conditions)
   - [Delivery sequence](#63-delivery-sequence)
7. [Operating cost and moving parts](#7-operating-cost-and-moving-parts)
8. [Acceptance walkthrough](#8-acceptance-walkthrough)
9. [Traceability matrix](#9-traceability-matrix)
10. [Unmet and partly met requirements](#10-unmet-and-partly-met-requirements)

---

## 0. Start here: the big picture

### 0.1 What we are trying to achieve

AiClinic's desktop app has an optional, paid AI add-on. The **AI Billing Orchestrator (ABO)** makes buying it self-service: a clinic administrator picks an offer in the app, pays on the payment provider's web page, and AI switches on by itself within about a minute. It keeps working until the paid time or the paid usage runs out, and then it stops on time.

The sibling documents describe how this is built: the decisions (01), the security blueprint (02), what is written down (03) and the messages exchanged (04). This document describes **how it is run day to day, and how we know it does what was promised**. The vendor has a single human operator, the developer, who also has other work. So the system must look after itself, call for help only when a human is truly needed, and make every fix a button rather than a database edit.

It answers nine questions:

1. **What runs by itself on a timer, and how often?** Section 1 (scheduled work).
2. **How is the developer told that something needs attention?** Section 2 (alerts).
3. **What can the operator see, and what can they do?** Section 3 (operator console), including the daily cross-check of money against service (§3.3) and the daily summary email (§3.4).
4. **What happens when each piece breaks, and what must the operator do?** Section 4 (failure modes and recovery).
5. **How are the records rebuilt after data is lost?** Section 5 (rebuild procedures).
6. **How is it tested before launch, what must be true on launch day, and in what order is it built?** Section 6 (staging and launch).
7. **What does it cost to run, and how many parts does it add?** Section 7.
8. **Does every required scenario have a defined outcome?** Section 8 (acceptance walkthrough).
9. **Where is each requirement satisfied, and which ones are not fully met?** Sections 9 and 10.

Four goals shape every choice in this document:

- **Nothing stalls silently.** If a confirmed payment has not become AI time within minutes, or any background job stops running, the developer is told by a channel that still works when the main systems are down.
- **Recovery never needs database surgery.** Every failure either heals by itself (a retry, a re-check) or is fixed with one console action. Nobody hand-edits a table.
- **One person can run it.** Routine tasks are console buttons, not SQL queries, and one daily email summarises everything.
- **Every promise can be traced.** Each requirement in the seed points to the place in the design that keeps it, and any gap is written down honestly.

### 0.2 The whole system in one analogy

The sibling documents use a **prepaid mobile phone bundle** as the picture. You walk into a shop, choose a bundle from the price board, pay at the till, and the network adds the bundle to your SIM card. Every call uses some units, and the bundle ends when its month or its units run out. This document keeps that picture and adds the **shop's housekeeping**: the chore rota, the alarms, the manager's office, the end-of-day cash-up and the fire drills.

**The business picture (same as the other documents):**

| Mobile bundle world                                                   | In this design                                                      | Explained in |
| --------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------ |
| The customer                                                          | A clinic's **desktop app**                                          | §0.3         |
| The ID office that issues temporary visitor badges                    | The **shared backend** (Supabase), issuing short-lived **tokens**   | §0.3         |
| The shop: price board, till and receipt book                          | The **ABO**                                                         | §0.3         |
| The phone network                                                     | The **AI Platform**                                                 | §0.3         |
| The clinic's dedicated cashier with a private notebook, serving one customer at a time | The clinic's **Durable Object (DO)** on the AI Platform | §0.3     |
| The bank's card terminal                                              | **Paymob**, the payment provider                                    | §0.3         |
| The shop owner                                                        | The **operator**: the developer                                     | §0.3         |

**The operations picture (new in this document):**

| Shop housekeeping world                                                        | In this design                                                     | Explained in |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------ | ------------ |
| The chore rota (every minute, every hour, every morning) and the night watchman's rounds | **Scheduled work**: timed jobs and **sweeps**             | §0.5, §1     |
| Smoke alarms, each with its own urgency and its own repeat rule               | **Alerts** AL-01 to AL-23                                          | §0.4, §2     |
| A guard who must phone in every hour, or an alarm goes off on its own         | The **heartbeat** and **dead-man's switch** monitor                | §0.5, §1, §2 |
| The manager's office, with the customer files and the action buttons          | The **operator console**                                           | §0.3, §3     |
| A safe that needs both a key card and a fingerprint                           | **HP actions** (human plus passkey)                                | §0.5, §3.2   |
| The end-of-day cash-up: till roll against bank statement against stock sold   | **Reconciliation** and its **findings**                            | §0.4, §3.3   |
| The morning newspaper about yesterday in the shop                             | The **daily digest** email                                         | §0.4, §3.4   |
| The fire-drill playbook: for each emergency, what happens and what you do     | **Failure modes** FM-01 to FM-25                                   | §4           |
| Restoring the books from the carbon copies kept in the vault                  | **Rebuild procedures**                                             | §0.5, §5     |
| A dress rehearsal on a fast-forwarded clock                                   | **Staging**, with compressed time                                  | §0.5, §6.1   |
| The opening-day checklist                                                     | **Launch conditions**                                              | §6.2         |
| A checklist mapping each promise to where it is kept                          | The **traceability matrix**                                        | §9           |

Keep both pictures in mind. Each later section zooms into one part of them.

### 0.3 The systems involved

Each system below is a separate program or service. This table only says what each one is and what part it plays in day-to-day running.

| System                                  | What it is, in plain words                                                                                                                                   | Analogy                                                  | Its part in operations                                                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Desktop app**                         | The clinic's Flutter app on Windows. A clinic has several desktops. An **administrator** can buy; **staff** only use AI                                      | The customer                                             | Reads the clinic's AI status from the AI Platform; shows "AI service unreachable" or "update the app" when needed       |
| **Shared backend**                      | One Supabase project (a PostgreSQL database plus login) holding every clinic's clinical data. Each clinic is a **tenant** in it                               | The ID office                                            | Only signs short-lived tokens for desktops. It runs no vendor jobs and never talks to the ABO or the AI Platform (C-02) |
| **ABO**                                 | A new program on Cloudflare (a **Worker**: code that runs on Cloudflare's servers when a request arrives or a timer fires), with its own storage              | The shop, with price board, till and receipt book        | Runs most of the scheduled jobs, raises most alerts, serves the console, runs reconciliation and sends the digest       |
| **Operator console**                    | A web page at `ops.<vendor-domain>`, served by the ABO                                                                                                       | The manager's office                                     | Where the operator looks things up and presses the action buttons (§3)                                                   |
| **Cloudflare Access**                   | Cloudflare's login gate placed in front of a web address. Only the operator can pass it                                                                       | The guard desk at the staff entrance                     | Protects the console; the logged-in email is recorded as the author of every action                                     |
| **AI Platform**                         | The existing Cloudflare Worker that serves AI requests and alone decides whether each one is allowed                                                         | The phone network                                        | Runs its own timed jobs, raises the alerts only it can see (for example every grant), and answers the ABO's questions   |
| **Per-clinic Durable Object (DO)**      | A Cloudflare feature: one small program instance per clinic inside the AI Platform, with its own private storage, handling one request at a time            | The clinic's dedicated cashier with a private notebook   | Keeps the clinic's terms and usage. Its own alarm clock ends terms on time and ships its news to the rest of the platform |
| **Paymob**                              | The payment provider (Egypt). Shows a hosted card page, sends notifications, answers status questions                                                         | The bank's card terminal                                 | Is asked again and again by the ABO's sweeps, so a lost message never loses a payment                                   |
| **Paymob adapter**                      | The only part of the ABO that knows Paymob's formats                                                                                                          | A translator                                             | Turns Paymob's messages into neutral ones                                                                                |
| **Alert channel**                       | Email sent by Cloudflare's own mail service (**Email Routing**, through its `send_email` function) to the developer's mailbox, which pushes to their phone    | The alarm bell                                           | Carries every alert and the daily digest (02 §5)                                                                         |
| **Heartbeat monitor and audit watcher** | A small scheduler run by a third company, outside Cloudflare and Supabase                                                                                     | A guard outside the building who expects a phone call every hour | Raises the alarm if the vendor systems go silent, and watches Cloudflare's own record of account changes (02 §4.4)  |
| **Operator**                            | The developer, the vendor's single human operator                                                                                                             | The shop owner                                           | Reads alerts and the digest; acts through the console                                                                    |

### 0.4 Business words

These are the same words used in 03 §0.5, shortened. Read them once; later sections use them freely.

**Who is who**

- **Clinic, tenant, `org_id`.** One customer clinic. In the shared backend it is a *tenant* (one of many customers sharing one database). Its id is `org_id`.
- **Installation.** The clinic's identity on the AI Platform: the "SIM card" the network knows.
- **Tenant binding** and **epoch.** The record linking an `org_id` to its current installation. If the identity has to be re-created, a new binding is made and its epoch (1, 2, 3, …) goes up. A binding `held_for_transfer` is frozen because the installation was deleted while paid time remained, and waits for the operator; meanwhile AI is refused with the reason `transfer_pending`, and new grants get `transient` (try later) (03 §5.4). A clinic whose old identity has handed over its time ends `transferred`, and a new identity waiting to receive moved time is `awaiting_transfer`.
- **Tenancy retrofit.** Work in the shared backend, tracked as 01 R-1, that adds proper per-clinic membership (`current_org_id()` and an "active organisation" per session). Today the backend serves one clinic only. Several guarantees here are **conditional** on this retrofit.
- **Billing contact.** The payer's name, email and phone, which Paymob requires. It is personal data, kept in one erasable table (03 §2.3).
- **Subscription reference.** A human-readable id (such as `AIC-` plus 8 characters) that the clinic quotes to support (03 §7). The operator can type it into the console to find the clinic.

**What is sold and bought**

- **Plan version, offer, offer version, terms version.** A *plan version* is what AI a clinic gets. An *offer* is what the shop sells (a plan for a length of time at a price, with an allowance). Each change makes a new *offer version*. The *terms version* is the legal text the buyer accepts. Published versions never change; they can only be **retired** (taken off sale).
- **Checkout.** One attempt to buy one offer: the order slip. It is **open** while it can be paid, and **expires** if nobody pays in time.
- **Payment.** Money Paymob confirmed for a checkout. Each payment gets a **classification** label (`normal`, `likely_duplicate` meaning probably the same purchase paid twice, or `late`) and a **disposition**, the decision about the money: `grant` (turn it into AI time) or **withheld** (held back because the amount, currency or order did not match; only the operator can release it).
- **Grant.** An instruction to the AI Platform: "add this much AI time to this clinic". A grant is **paid** (from a payment), **complimentary** (a gift by the operator, such as a trial or goodwill), a **term adjustment** (a complimentary change to the current term) or a **transfer** (moving time to a new identity of the same clinic).
- **Term.** The unit of AI time a grant creates: a span of dates plus its allowance. A term is **active**, **queued** (waiting its turn), **held** (frozen after a reversal, waiting for the operator), in **grace** or **ended**. **Coverage** is all of a clinic's terms together.
- **Allowance, credits.** Usage is counted in credits; the allowance is the number of credits a term includes. **Band events** are the warnings sent when 75 % and 90 % of it is used.
- **Grace, lapse, exhaustion.** *Grace* is 7 days after the end date when AI keeps working on a capped leftover. *Lapse* is the state after grace with nothing new. *Exhaustion* is the allowance running out, which ends the term at once with no grace.
- **Suspension, kill switch, routing.** The operator switching one clinic's AI off for abuse (suspension), switching an AI feature off for everyone (a kill switch), or choosing which AI provider serves requests (routing).
- **Ceiling** and **ceiling override.** The platform's limit on how much a complimentary grant may give (for example at most 31 days per grant). An override lets one grant exceed it, but needs a second passkey touch and its own alert.
- **Velocity.** How fast paid grants are arriving. Too many too quickly (the thresholds are in 04 §1.4) suggests the ABO is fabricating them.

**When money goes backwards**

- **Reversal.** Money taken back from a payment: a **refund** (returned, perhaps from Paymob's dashboard), a **void** (cancelled before it settled) or a **chargeback** (the card holder's bank forces it back). Paymob does not report chargebacks, so the operator records them by hand (a **manual chargeback**). A reversal's **effect** says what happens to service, for example `end_current` (the current term ends now) or `none` (it paid for an old, ended term, so nothing changes) (03 §5.5).
- **Void receipt** and **tombstone.** When a reversal cancels a grant, the platform answers with a signed receipt. If the grant had not arrived yet, the platform stores a tombstone: a "this grant is dead" marker that refuses the grant when it shows up.
- **Payout.** The money Paymob actually transfers to the vendor's bank, minus fees. Paymob reports it only in a CSV file downloaded from its dashboard, which the operator **imports** into the console each month. Each row of that file is a **payout line**.

**Keeping watch**

- **Alert.** An email to the developer when something needs a human. Each has an id AL-nn (§2).
- **Reconciliation** and **finding.** Reconciliation is the daily cross-check that money, payments and grants all agree, like a shop's end-of-day cash-up. Each disagreement is written down as a *finding* (§3.3).
- **Digest.** One summary email each morning about the last 24 hours (§3.4).
- **Failure mode.** One way the system can break, with an id FM-nn, how it is noticed and what happens next (§4).

### 0.5 Technical words

**Where data is kept**

- **D1.** Cloudflare's database (SQLite). The ABO has its own D1; the AI Platform has another. Think of a filing cabinet of forms.
- **R2, prefix, R2 bucket lock.** R2 is Cloudflare's file storage; a **bucket** is one storage area, and files are grouped by name **prefix**, like folders (`ledger/`, `grant-ledger/`). A **bucket lock** on a prefix means files there can be added but never changed or deleted: a sealed vault with a slot.
- **NDJSON.** "Newline-delimited JSON": a text format with one record per line. The ABO writes one line per commercial fact into the locked `ledger/` prefix, like a carbon copy of the receipt book kept in the vault. Each fact has a running number, `fact_seq`. **Export lag** is how far that copy is behind the database.
- **D1 Time Travel.** Restores a D1 database to any moment in the last 30 days: an "undo to last Tuesday" button.
- **Append-only, triggers, status tables.** Commercial facts are written once and never edited, like a ledger in pen. Database **triggers** (automatic rules) block any edit or deletion. Small editable **status tables** hold "the current state" and can always be recomputed from the facts.
- **Mirror and view.** Read-only copies of each clinic's coverage: `coverage_mirror` on the platform (desktops read their status from it) and `coverage_view` in the ABO (for the console, reconciliation and as a fallback at checkout). A **coverage event** is a "something changed" notice that keeps these copies up to date; `coverage_event` is the platform's list of them. A **snapshot** is a complete picture of a clinic's coverage at one moment.

**Timed and background work**

- **Cron.** A timer that runs a job on a schedule. Schedules such as `0 3 * * *` are written in standard cron notation; that one means "every day at 03:00 UTC". UTC is world time, with no time zones.
- **Work row.** A to-do card in the ABO's D1 for one background step, such as "confirm this payment" or "send this grant". It is **open** until it succeeds (**done**), or it is **parked**: stopped because retrying cannot help, waiting for the operator (03 §5.6).
- **`waitUntil` and inline attempt.** `waitUntil` is a Cloudflare feature that lets a Worker keep working briefly after it has already answered a request. The ABO uses it for the **inline attempt**: the first try of a new work row, made right away instead of waiting for the next cron run.
- **Runner** and **lease.** A runner is whatever is processing a work row (the inline attempt or the cron). A lease is a "someone is working on this until 10:05" tag, so two runners never process the same row at once.
- **Backoff.** Waiting longer between each retry (for example 1, 2, 4, 8 minutes, up to a cap of 15).
- **Idempotent.** Doing it twice has the same effect as doing it once, like pressing a lift button twice. Every job is idempotent, so a repeated run is harmless.
- **Index-backed.** Every scheduled query uses an **index** (a sorted lookup list, like a book's index), so the database never reads every row. D1 bills for rows read.
- **Callback, notification.** A message Paymob sends to the ABO's address `/notify/paymob` when something happens to a payment. It only *triggers* work.
- **Inquiry.** The ABO asking Paymob's API directly "what is the real state of this payment?". It is the *proof*, like phoning the bank instead of trusting a text message. Paymob limits how many questions it answers per minute (its **rate limit**), so all inquiries share one per-minute **inquiry budget**.
- **Sweep.** A scheduled round of inquiries, like a night watchman checking every door. A **checkout sweep** asks about open checkouts, in case the payment callback was lost. A **reversal sweep** (reversal inquiry) re-asks about paid transactions, in case a refund or chargeback notice was lost.
- **DO alarm** and **outbox.** A DO's alarm clock wakes it at a set time, for example at a term's end date. The **outbox** is an out-tray inside the DO: news that the rest of the platform must learn is put there, and the alarm **ships** it to platform D1 later, so AI requests stay fast.
- **Fallback admission.** If a clinic's DO cannot be reached, the platform lets a small, bounded number of AI requests through and writes each one in `fallback_admission`. Later these rows are **drained**: replayed into the DO so the usage is counted (03 §6.5).
- **Retention purge** and **rollup.** The platform's existing nightly jobs: the purge deletes old detailed records that are no longer needed; the rollup adds usage up into summary rows.
- **Cursor.** A bookmark saying "I have read the platform's coverage events up to here".

**Watching from outside**

- **Heartbeat** and **dead-man's switch.** Each scheduled job sends a short "I am alive" message (a **ping**) to the external monitor. The monitor works as a dead-man's switch: it does nothing while pings arrive, and raises the alarm by itself when one is missing. Like a night guard who must phone in every hour.
- **Audit log** and **audit watcher.** Cloudflare keeps its own log of account changes (deploys, secret changes, database exports, login-gate edits). The audit watcher is an hourly job outside Cloudflare that reads that log and alerts on sensitive changes (02 §4.4).
- **`send_email` and deduplication.** Alerts are sent through Cloudflare's `send_email` function to one fixed address (02 §5). Each alert has an **`alert_key`** (its code plus what it is about), so the same problem produces one series of emails, not hundreds.

**Proof and permission**

- **HMAC.** A seal made with a secret shared between Paymob and the ABO. It shows a callback really came from Paymob. An **HMAC failure** is a callback whose seal does not check out.
- **Signature, key, `kid`.** A digital wax seal: only the holder of a private key can make it; anyone with the public key can check it. `kid` (key id) says which key was used. Keys are replaced over time (**rotation**) and can be cancelled (**revocation**). `not_after` is a key's expiry date.
- **Issuer key, service key, platform signing key.** Issuer keys are the backend's keys for signing desktop tokens. The ABO keeps its own fixed list of them, its **pins** (`ISSUER_KEYS`), instead of trusting the platform's list. The service key is the ABO's key for signing paid grants. The platform signing key signs the platform's receipts.
- **Passkey, WebAuthn, assertion, passkey ceremony.** A passkey is a hardware security key. WebAuthn is the web standard for using it. The **ceremony** is the operator touching it in the browser for one exact operation, which produces an **assertion**: signed proof of that touch, valid for that operation only.
- **Operator credential** and **bootstrap credential.** An operator credential is a registered passkey. A new one waits 24 hours and needs approval by an existing one. The very first one, the bootstrap credential, is accepted only while none exists yet, and that is alerted.
- **Authorization classes M, H and HP** (02 §3.3). Each action needs one of three levels of proof. **M** (machine): the ABO over its private connection, with its signature when coverage changes. **H** (human): the operator logged in through Cloudflare Access; the login email becomes the recorded author. **HP** (human plus passkey): H plus a passkey touch for this exact action, like a safe that needs both a key card and a fingerprint.
- **Audit records.** `operator_action` (in the ABO) and `control_audit` (on the platform) record every operator action and who did it.
- **Platform answers.** Every request from the ABO to the platform gets one of these answers: `applied` (done now), `already_applied` (done before; nothing new), `conflict` (same id, different content), `rejected` (invalid; retrying cannot help) or `transient` (try again later) (04 §1.2). A **5xx** answer is the standard web code for "server error, try again"; Paymob then re-sends its callback.
- **`grant_id = H(payment_id)`.** A grant's id is computed from its payment's id by a hash (a fingerprint function), so the same payment always gives the same grant id. The id is **deterministic**, and a repeat is recognised as `already_applied`.
- **Contract version.** The edition number of a message format. Each receiver accepts the current version N and the previous N−1, and refuses others with `contract_version_unsupported` (04 §7).

**Platform operations named in this document.** These are named requests the ABO can send to the AI Platform (04 §1.3): `getCoverage` (read a clinic's coverage), `inspectCoverage` (the full DO ledger: terms, grants and in-flight reservations), `listGrants` (list applied grants), `listGrantsForVoid` (list grants made with one operator credential in a time window, so they can be cancelled), `listServiceKeys` (list the ABO's registered keys and their status), and `beginTransfer`, `transferOut` and `transferIn` (authorise, then carry out, a move of paid time to a new identity).

**Testing and release**

- **Staging.** A separate copy of the whole system, in its own Cloudflare account and Supabase project, used for rehearsals with Paymob's **test integration** (a sandbox that accepts **test cards**, so no real money moves).
- **`DURATION_SCALE`.** A staging-only setting that fast-forwards the calendar, so a month passes in 30 minutes.
- **`wrangler dev`.** Cloudflare's tool for running a Worker on the developer's own computer.
- **Fixture** and **stub.** A fixture is a saved, reusable test input. A stub is a small fake stand-in for an outside service, scripted to give chosen answers.
- **Spec Kit feature** and **constitution check.** The project builds work in separate packages called Spec Kit features. Each must pass a check against the project's founding rules, the **constitution** (`.specify/memory/constitution.md`).

### 0.6 A day in the life of the operator

This is an **illustrative example** to show how the pieces fit. The times and the events in it are made up; the rules it follows are the ones in the later sections, given in brackets.

1. **All night, the chores run by themselves.** Every minute, the ABO's cron picks up due work rows, sweeps open checkouts, reads the platform's coverage events, sends due alerts, copies new facts to the locked R2 vault and pings the heartbeat monitor. Every 5 minutes the platform does its own chores and pings too. Nobody has to watch (§1).
2. **06:00 UTC, the morning newspaper arrives.** The daily job runs reconciliation and sends the digest: yesterday's checkouts, payments, grants, reversals and alerts, any open findings, and the last run time of every job. A quiet digest is good news: it proves the jobs are alive (§3.3, §3.4).
3. **10:12, a smoke alarm.** Paymob's notifications stop checking out for one clinic, so AL-02 arrives by email. The operator does nothing urgent: the sweeps keep confirming payments by inquiry. Later they update the Paymob secret and deploy (§2, §4 FM-18).
4. **14:30, a support call.** A clinic quotes its subscription reference. The operator types it into the console and sees the clinic's terms, payments and alerts on one page (§3.1).
5. **14:35, a goodwill gift.** The operator gives the clinic 3 extra days. This is an HP action, so they touch the passkey. The platform checks the ceiling, applies it, and sends its own alert (AL-11), which the next digest lists again (§3.2, §2).
6. **Once a month, the bank statement.** The operator downloads Paymob's payout CSV and imports it. Reconciliation matches every line to a payment and raises a finding for anything that does not match (§3.3).
7. **If the alarms go quiet.** If Cloudflare itself stopped, no emails could be sent. The external monitor notices the missing pings and alerts the developer over its own channel (§2 AL-21, §4 FM-12).

### 0.7 How to read the rest of this document

**Reference codes.** Short codes in brackets point to where a rule comes from or where it is kept. You do not need to follow them to understand the text.

| Code          | Means                                                                     | Defined in                                                                          |
| ------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| G-n (G1…)     | Product goal                                                              | [Seed](00-abo-requirements-seed.md) §2.1                                            |
| FR-n          | Functional requirement (what the product must do)                         | Seed §4                                                                             |
| SR-n          | Security requirement                                                      | Seed §5                                                                             |
| NFR-n         | Reliability or operational requirement                                    | Seed §6                                                                             |
| RC-n          | Records and retention requirement                                         | Seed §7                                                                             |
| C-n           | Constraint or given fact                                                  | Seed §8.1                                                                           |
| P-n           | A gap in today's AI Platform code                                         | Seed §8.2                                                                           |
| A-n (A1…A36)  | Acceptance scenario that must pass before launch                          | Seed §11                                                                            |
| X-n           | A future expansion, and the "seam" kept open for it                       | Seed §2.3 and 01 §5                                                                 |
| T-n, I-n, R-n | Code fact, approved interpretation of the seed, risk or spike             | [Decision memo](01-abo-design-decisions.md) §2, §4, §7                              |
| AD-n, K-n, TB-n | Adversary, credential, trust boundary                                   | [Architecture and threat model](02-abo-architecture-and-threat-model.md) §4.2, §3.1, §2 |
| AL-n          | Alert                                                                     | This document §2                                                                    |
| FM-n          | Failure mode                                                              | This document §4                                                                    |

A **spike** (in R-n) is a short experiment to answer an unknown before building, for example how Paymob behaves in its sandbox.

"01 §n" means section n of the [decision memo](01-abo-design-decisions.md); "02 §n" the [architecture and threat model](02-abo-architecture-and-threat-model.md); "03 §n" the [data model](03-abo-data-model-and-lifecycle.md); "04 §n" the [contracts](04-abo-contracts.md). A bare "§n" means a section of this document. A reference such as `ai-platform/src/worker.ts:1733-1767` points to lines in today's code.

**Order of reading.** Sections 1 and 2 describe what runs by itself and how it calls for help. Section 3 describes what the operator does. Sections 4 and 5 describe what happens when things break. Section 6 covers testing and launch, section 7 the cost. Sections 8 to 10 are the evidence: every scenario, every requirement and every honest gap.

## 1. Scheduled work

**Purpose.** Most of the system's care happens on a timer, not in response to a person. This is the shop's chore rota: some chores every minute, some every hour, some every morning, and a night watchman who walks round checking doors (the sweeps, §0.5). Because the chores run by themselves, a lost message or a short outage is caught without anyone noticing it first.

**Rules.**

- **Cheap to run.** Every scheduled query is index-backed (01 §3.3), so it never reads the whole database.
- **Safe to repeat.** Each job is idempotent, so a repeated or overlapping run is harmless (NFR-02).
- **One shared question budget.** All provider inquiries, from sweeps and work rows alike, draw on one per-minute budget set from Paymob's rate limit (01 §3.3, R-2). Work rows for confirmation and grants go first, because they turn money into service.

How to read the table:

- **System**: which program runs the job. "External" is the heartbeat monitor and audit watcher outside Cloudflare.
- **Schedule**: when it runs. "Inline (`waitUntil`)" means right away, as part of the request that created the work. "DO alarm" means whenever the clinic's DO sets its alarm clock. `0 3 * * *` and `0 4 * * *` are cron notation for daily at 03:00 and 04:00 UTC.
- **Job**: what it does.

Words used in the table that are not in §0: "**due work rows by `(state, next_attempt_at)`**" means the cron picks open work rows whose retry time has come, found through an index on those two fields, at most 50 per run. The **checkout sweep** times (+2, +5, +10, +20 minutes) are counted from when the checkout opened; "widening to 7 days" means the gaps then grow, up to 7 days. The **last-seen list** is the set of operator credentials the ABO has seen announced by AL-13; a credential on the platform that is not on it is suspicious. A **term boundary** is the moment a term ends or the next one starts. "**Keyed by `term_id`**" means usage is grouped by the term it counted against, instead of by calendar period as today. "Read platform coverage events" moves the ABO's cursor forward over the platform's change notices to update `coverage_view`. "Export pending facts to R2" writes new facts into the locked NDJSON vault copy. "Reversal inquiry" is a reversal sweep (§0.5): re-asking Paymob about a paid transaction in case a refund or chargeback notice was lost. A term that is "active, grace, queued or held" is one that still matters for service. The "R2 lock check" confirms the vault lock still exists, and the "key-expiry check" looks for keys near their `not_after` date. `platform_alert` rows are the platform's own unsent alerts.


| System      | Schedule                   | Job                                                                                                                                                                                        |
| ----------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ABO         | Inline (`waitUntil`)       | First attempt of every new work row                                                                                                                                                        |
| ABO         | Every minute               | Due work rows by `(state, next_attempt_at)`, at most 50 per run; checkout sweeps (+2, +5, +10, +20 min, then every 10 min to expiry, then widening to 7 days); read platform coverage events; evaluate alert conditions; send due alerts; export pending facts to R2; heartbeat ping |
| ABO         | Hourly                     | Reversal inquiry of every payment in its first 7 days or whose grant is not yet applied; comparison of the platform's issuer keys and operator credentials with the ABO's pins and last-seen list (AL-22); check that the ABO's signing `kid` is active (`listServiceKeys`, AL-23) |
| ABO         | Every 6 hours              | Reversal inquiry of every payment that funds an active, grace, queued or held term                                                                                                        |
| ABO         | Daily 06:00 UTC            | Weekly reversal inquiry of all other paid transactions up to 180 days old, one seventh each day, spread across the day; reconciliation (§3.3); R2 lock check; key-expiry check; digest (§3.4); heartbeat ping |
| AI Platform | DO alarm                   | Next term boundary, and outbox shipping (03 §6.7)                                                                                                                                          |
| AI Platform | Every 5 minutes            | Drain `fallback_admission`; retry `platform_alert`; heartbeat ping                                                                                                                         |
| AI Platform | `0 3 * * *`, `0 4 * * *`   | Retention purge and rollup, as today (`ai-platform/src/worker.ts:1733-1767`), keyed by `term_id`                                                                                          |
| External    | Hourly                     | Audit-log watcher (02 §4.4); the heartbeat monitor alerts on any missing ping                                                                                                               |


How the reversal sweep is spread out, in plain words: a payment is re-checked every hour in its first 7 days, or for as long as its grant is not yet applied; every 6 hours while it pays for a term that still matters; and once a week after that until it is 180 days old. The weekly checks are split into sevenths, one seventh each day, spread across the day, so that each day carries the same load.

The backend runs no scheduled vendor work: it never talks to the vendor services (C-02). The ID office has no chores in the shop.


## 2. Alerts

**Purpose.** Alerts are the shop's smoke alarms. Each one watches for one specific danger, and each has its own urgency: some ring once ("a reversal happened, take note"), some keep ringing every hour until the problem is gone ("a payment is stuck"). The goal is that the developer never has to go looking for trouble; trouble comes to them.

**Rules.**

- **One channel.** Alerts go through `send_email` (02 §5) to the developer's fixed address.
- **No floods.** Alerts are deduplicated by `alert_key`, so one problem gives one series of emails.
- **Repeat while it lasts.** An alert is repeated at the stated interval while the condition holds (NFR-04).
- **Nothing is only in an email.** Every alert also appears in the digest (§3.4).
- **Two sides watch.** Most alerts are raised by the ABO. Some can only be seen, or must be trusted only, from the AI Platform's side (for example "a grant was applied"), so the platform raises those itself. A compromised ABO therefore cannot hide them (02 AD-8).

How to read the table:

- **#**: the alert's id. Other documents cite it, so ids are never renumbered. There is no AL-15 in the table.
- **Condition**: what sets the alarm off.
- **Raised by**: which system sends it. "External" means the heartbeat monitor or audit watcher outside Cloudflare.
- **Repeat**: "Once" rings a single time per event. "Hourly" or "Daily" rings again at that interval while the condition holds. "Daily while held" rings daily for as long as a binding is held for transfer. "Per event" rings for each event the monitor sees.
- **Requirement**: the requirement or design rule the alert serves (§0.7).

Words used in the table that are not in §0: "**open for more than 5 minutes**" means a work row has not reached `done` or `parked` within 5 minutes. A payment "**confirmed by inquiry with no verified callback**" is one the sweep found although no valid Paymob notification arrived. A **"late payment honoured"** is a payment made on a checkout that had already expired or been cancelled, which is still turned into service (G3). "**Non-paid ones marked for attention**" means complimentary, adjustment and transfer grants are flagged in the email. The **decoded operation and its target** is the plain-language content of the action and the clinic it touched, so a substituted operation is visible (02 AD-8). A **D1 export** is a download of a whole database, and an **Access policy edit** is a change to who may pass the console's login gate.


| #     | Condition                                                                  | Raised by   | Repeat       | Requirement             |
| ----- | -------------------------------------------------------------------------- | ----------- | ------------ | ----------------------- |
| AL-01 | A work row open for more than 5 minutes                                    | ABO         | Hourly       | G3, NFR-04              |
| AL-02 | 3 or more HMAC failures within 15 minutes                                  | ABO         | Hourly       | A23                     |
| AL-03 | A payment confirmed by inquiry with no verified callback                   | ABO         | Once         | A3, A23                 |
| AL-04 | The platform answers `transient` or cannot be reached for 5 minutes        | ABO         | Hourly       | A4                      |
| AL-05 | Amount, currency or order mismatch; payment withheld                       | ABO         | Once         | FR-16                   |
| AL-06 | Reversal detected or recorded                                              | ABO         | Once         | FR-43                   |
| AL-07 | Grant or reversal void parked (`conflict` or `rejected`)                   | ABO         | Hourly       | NFR-03                  |
| AL-08 | Late payment honoured on an expired or cancelled checkout                  | ABO         | Once         | G3                      |
| AL-09 | Payment classified `likely_duplicate`                                      | ABO         | Once         | FR-41                   |
| AL-10 | Reconciliation finding (§3.3)                                              | ABO         | Daily        | FR-81                   |
| AL-11 | Any grant applied: paid, complimentary, term adjustment or transfer; non-paid ones marked for attention. The body carries the decoded operation and its target (02 AD-8) | AI Platform | Once | SR-23 |
| AL-12 | Ceiling override used                                                      | AI Platform | Once         | SR-24                   |
| AL-13 | Issuer key, service key or operator credential registered or revoked; bootstrap credential. The body carries the decoded operation and its target | AI Platform | Once | SR-11, SR-25 |
| AL-14 | A key is within 30 days of `not_after`                                     | ABO         | Daily        | A25                     |
| AL-16 | R2 bucket lock missing, or fact export more than an hour behind            | ABO         | Daily        | RC-03                   |
| AL-17 | Paid-grant velocity above the 04 §1.4 thresholds                           | AI Platform | Hourly       | 02 AD-8                 |
| AL-18 | Installation deleted with coverage remaining; binding held for transfer (03 §5.4) | AI Platform | Daily while held | A24              |
| AL-19 | Suspension, resume or kill-switch change                                   | AI Platform | Once         | FR-74                   |
| AL-20 | Tenant-binding creation above 50 per day                                   | AI Platform | Daily        | 04 §2.1                 |
| AL-21 | Heartbeat missing, or audit event: production deploy, secret change, D1 export, Access policy edit | External | Per event | NFR-04, A26 |
| AL-22 | The platform's issuer keys differ from the ABO's pinned `ISSUER_KEYS`, or an operator credential appeared that the ABO has not seen announced by AL-13 | ABO | Hourly | SR-11, 02 AD-9 |
| AL-23 | The ABO's signing `kid` is not active on the platform; `grant` and `reverse` work is paused until it is | ABO | Hourly | NFR-04, 02 §6 |

## 3. Operator console

**Purpose.** The console is the manager's office at the back of the shop: the customer files on the desk, the action buttons on the wall, and the daily paperwork. Everything the operator needs to look up or fix is here, so no routine task needs SQL (a database query language) (G7).

**Where it is.** The console is on `ops.<vendor-domain>`, behind Access (02 §1.4), the guard desk at the staff entrance.

This section has four parts: what the operator can see (§3.1), what they can do (§3.2), the daily cross-check of the books (§3.3) and the morning summary email (§3.4).

### 3.1 Views

**What this is.** The customer files. One page per clinic gathers everything about it, and a few global lists show what needs attention across all clinics.

One clinic page, found by subscription reference, `org_id`, billing email, or checkout, payment or grant reference (FR-70). It shows:

- the live coverage from `inspectCoverage`: terms, grants, reservations and suspension. A **reservation** is the credits held by an AI request that is still running (03 §6.2);
- checkouts with their events; payments with classification and disposition; reversals; grant requests with outcomes and receipts;
- operator actions on this clinic, and open findings and alerts.

Global views list parked work, open findings, recent grants by source and by credential, payout imports, and key and credential registries. "By source" means grouped by paid, complimentary, adjustment or transfer; "by credential" means grouped by the operator passkey that authorised them. The **registries** are the platform's lists of registered keys and passkeys.

### 3.2 Actions

**What this is.** The buttons on the office wall. Some are ordinary (log in and press). Others move money or AI time, so they sit behind a safe that needs both a key card and a fingerprint: the Access login plus a passkey touch for that exact action.

**Rules.**

- **Two levels of proof.** Each action has a class (§0.5). **H** needs only the Access login. **HP** also needs the passkey: HP actions run the passkey ceremony in the console.
- **Who checks.** "Verified by" says which system checks the evidence; the other system's check is only for UX (user experience: a convenience, such as greying out a button, not a protection). Actions on the ABO's own records (offers, checkouts, payments, findings, payer data) are checked by the ABO. Actions on the platform (coverage, suspension, plans, keys, installations) are checked by the AI Platform itself, so a compromised ABO cannot fake them (02 §3.3).

How to read the table: **Action** is the button; **Class** is H or HP; **Verified by** is the system that checks the proof; **Requirement** is where the action is required (§0.7).

Words used in the table: **retry parked work** restarts a parked work row after the cause is fixed. **Cancel an open checkout** marks it cancelled on the ABO's side; Paymob cannot cancel its own payment session, so a late payment is still honoured and alerted (AL-08, 01 §3.6). **Resolve a finding** closes a reconciliation finding once explained. **Publish or retire** puts a version on sale or takes it off. **Transfer or re-create identity** moves paid time to a new installation of the same clinic. **Release held terms** lets frozen queued terms run again. **Void a grant** cancels it. **Delete an installation** removes a clinic's AI identity (its records stay). **Erase** blanks a payer's personal data and the raw provider messages that contain it.


| Action                                          | Class | Verified by | Requirement         |
| ----------------------------------------------- | ----- | ----------- | ------------------- |
| Retry parked work                               | H     | ABO         | FR-71               |
| Cancel an open checkout                         | H     | ABO         | FR-71               |
| Import a payout CSV; resolve a finding          | H     | ABO         | FR-80               |
| Record a manual chargeback                      | HP    | ABO         | FR-44, A18          |
| Release a withheld payment                      | HP    | ABO         | FR-16               |
| Publish or retire an offer or terms version     | HP    | ABO         | FR-01, FR-06        |
| Suspend or resume a clinic; kill switches; routing | H  | AI Platform | FR-74               |
| Complimentary grant; term adjustment            | HP    | AI Platform | FR-32, FR-35, A20   |
| Ceiling override (second assertion)             | HP    | AI Platform | SR-24               |
| Transfer or re-create identity; release held terms; void a grant | HP | AI Platform | FR-72, SR-25, 01 I-3 |
| Publish or retire a plan version; set the ceiling policy | HP | AI Platform | FR-01, SR-24     |
| Register or revoke an issuer key, service key or operator credential | HP | AI Platform | SR-11, SR-25 |
| Delete an installation                          | HP    | AI Platform | A24                 |
| Erase a tenant's payer contact data and raw provider bodies (03 §2.3) | HP | ABO   | 01 R-9              |


**Audit.** Every action writes `operator_action` in the ABO and `control_audit` on the platform, with the Access email as actor (FR-73). The actor is the person recorded as having done it. Like a sign-in book in the manager's office, nothing is done without a name next to it.

**Compromise response (SR-25).** If an operator passkey or session may have been stolen, the operator follows these steps, in order:

1. Revoke the suspect credential from another credential (any active passkey can cancel another).
2. List grants by credential and window (`listGrantsForVoid`): every grant that passkey authorised in the suspect period.
3. Void each one.
4. Revoke Access sessions, so any hijacked login ends.
5. Rotate any machine key involved (02 §6).

### 3.3 Reconciliation

**What this is.** The end-of-day cash-up. A shopkeeper counts the till, compares it with the bank statement, and checks that every bundle sold was paid for and every payment got its bundle. Reconciliation does the same across four sets of books: the ABO's payments, the AI Platform's grants, the operator's recorded actions and Paymob's payout file. If any two disagree, something is wrong: a stuck payment, a forged grant, a refund nobody recorded.

**Rules.**

- **When.** It runs daily, and again after each payout import (FR-80, FR-81).
- **What a failure produces.** Each failed check writes a `finding` and raises AL-10. The operator investigates and resolves the finding in the console (§3.2).

How to read the table: **Check** is the rule that must hold; **Finding kind** is the label written when it does not.

Words used in the table: **`applied` outcome** is the platform's "done" answer for a grant. **`grant_id = H(payment_id)`** (§0.5) ties each paid grant to exactly one ABO payment. A **`beginTransfer` `operator_action`** is the ABO's record of the operator authorising a transfer; the **`transferOut` package** is the bundle of terms the old identity handed over. A **full reversal** takes back all the money; its effect `none` means it changed no service (§0.4). A **payment settled** is one whose money Paymob has finalised; the **imported period** is the date range the payout file covers. A **payout payment line** is a row of that file for a payment, and a **refund or chargeback line** is a row for money taken back. An **HMAC-valid success callback** is a correctly sealed "paid" notification. The last check compares the ABO's copy of each recently active clinic's coverage (`coverage_view`) with the live answer from `getCoverage`.


| Check                                                                                         | Finding kind                    |
| --------------------------------------------------------------------------------------------- | ------------------------------- |
| Every payment with disposition `grant` has an `applied` outcome within 15 minutes             | `payment_without_grant`         |
| Every paid platform grant (`listGrants`) has `grant_id = H(payment_id)` of an ABO payment     | `grant_without_payment`         |
| Every complimentary platform grant matches an ABO `operator_action`                           | `grant_without_operator_action` |
| Every transfer grant matches an HP `beginTransfer` `operator_action` and the `transferOut` package it came from | `transfer_without_authorisation` |
| Every full reversal of a payment has a void receipt or tombstone, unless its effect is `none`  | `reversal_not_applied`          |
| Every payout payment line matches a payment by `payment_id` and amount                         | `payout_unmatched`              |
| Every payment settled more than 7 days before the end of an imported period appears in it      | `payment_not_in_payout`         |
| Every payout refund or chargeback line has a recorded reversal                                 | `unrecorded_reversal` (A18)     |
| Every HMAC-valid success callback was confirmed by an inquiry                                  | `callback_without_confirmation` |
| For clinics with events in the last day, the ABO's `coverage_view` snapshot equals `getCoverage` | `feed_divergence`             |


### 3.4 Daily digest

**What this is.** The morning newspaper about yesterday in the shop: one email, sent by the daily job at 06:00 UTC (§1). It has two jobs:

- **It proves the jobs are alive (NFR-04).** If the newspaper does not arrive, or shows a job that has not run, something has stopped. A missing digest is itself a warning sign (§4 FM-16).
- **It lists every grant (SR-23).** Every gift of AI time is printed again, so none can slip by unnoticed even if its alert email was missed.

It contains:

- 24-hour counts of checkouts, payments by classification, grants by source, reversals and alerts;
- every grant; complimentary, adjustment and transfer grants with operator, reason, length and allowance;
- open findings, parked work and open alerts;
- the last run time of each scheduled job;
- the R2 lock status and export lag, and keys expiring within 30 days;
- per channel, the contract versions received and the count of `contract_version_unsupported` answers, which show when an old version can be dropped (04 §7.3). A **channel** is one direction of conversation between two systems, such as desktop to ABO (04 §0.3). The counts help the operator see when the conditions in 04 §7.3 for dropping an old version are met.

## 4. Failure modes and recovery

**Purpose.** This is the fire-drill playbook. For each way the system can break, it says how we find out, what the system does by itself, and what, if anything, the operator must do. Most rows end in "None": the system heals itself through retries and sweeps, and the operator only watches.

**The promise.** Recovery never needs database surgery (G3, NFR-01). Database surgery means hand-editing rows to repair state. Every fix is either automatic or a console action.

How to read the table:

- **#**: the failure's id. Other documents cite it.
- **Failure**: what went wrong.
- **Detection**: how it is noticed: an alert (§2), the platform's logs, reconciliation (§3.3) or the heartbeat.
- **Automatic behaviour**: what the system does without help.
- **Operator step**: what the operator must do. "None" means nothing; a section number points to a procedure.

Words used in the table that are not in §0: a **stalled row** is a work row that stays open. **"Answered with 5xx"** means the ABO replied "server error" to Paymob, so Paymob may try again. **Evidence write** is the ABO saving Paymob's raw message in R2 before anything else; "nothing is enqueued" means no work row was created. `provider_unavailable` is the ABO's answer to a desktop when Paymob cannot be reached. **Mint tokens** means the backend issues new tokens. A **lapse already due** is a term whose end date passed while Cloudflare was down; it takes effect at the clinic's next **admission** (the DO's yes-or-no decision on an AI request). **Roll back** means redeploy the previous version of the code. **Email Routing** is Cloudflare's mail service behind `send_email`. **One D1 batch** means all of a step's writes succeed together or not at all. **`held_for_transfer`**, `transfer_pending` and `transient` are explained in §0.4 and §0.5. **The event reader keeps its cursor** means the ABO does not move its bookmark past a coverage event it could not read, so it reads it again later. **The update state on desktops** is the "please update the app" screen.


| #     | Failure                                              | Detection               | Automatic behaviour                                                                                                               | Operator step                                            |
| ----- | ---------------------------------------------------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| FM-01 | ABO crashes after receiving a callback               | AL-01 if a row stalls   | The callback was answered with 5xx or the row is open; the sweep inquires within 2–20 minutes                                     | None                                                     |
| FM-02 | Callback lost or delayed (A3)                        | AL-03                   | Checkout sweep finds the payment by inquiry                                                                                       | None                                                     |
| FM-03 | HMAC verification fails for every callback (A23)     | AL-02                   | Sweeps keep confirming by inquiry                                                                                                 | Fix the adapter or secret; deploy                        |
| FM-04 | Platform unreachable or failing (A4)                 | AL-04 hourly            | Grant rows retry with backoff up to 15 minutes, forever; the term starts at activation (01 I-2)                                    | None                                                     |
| FM-05 | Platform answers `conflict` or `rejected`            | AL-07                   | Row parked                                                                                                                        | Inspect; fix the cause; retry                            |
| FM-06 | One clinic's DO unavailable                          | Platform logs           | Bounded fallback (03 §6.5); drained later                                                                                          | None                                                     |
| FM-07 | ABO D1 unavailable                                   | AL-01, AL-21 heartbeat  | Callbacks get 5xx; sweeps recover once D1 returns                                                                                 | None                                                     |
| FM-08 | ABO R2 unavailable                                   | AL-01                   | Evidence write fails, so the callback gets 5xx and nothing is enqueued; sweeps recover                                           | None                                                     |
| FM-09 | Paymob API down                                      | AL-01                   | Checkout creation answers `provider_unavailable`; inquiries retry                                                                 | None                                                     |
| FM-10 | Platform status reads fail while the ABO is up       | Desktops show "AI service unreachable"; platform logs | AI is unusable on those desktops until it returns; the rest of the app works (G5). Grants keep retrying (FM-04) | Fix or roll back the platform                            |
| FM-11 | Supabase down                                        | Clinic app down (C-04)  | Payments already made still provision (the ABO and platform do not depend on the backend); desktops mint tokens again on return  | None                                                     |
| FM-12 | Cloudflare down                                      | Heartbeat (AL-21)       | Nothing runs; on return, sweeps and alarms catch up; lapses already due apply on the next admission                              | None                                                     |
| FM-13 | Bad ABO deploy                                       | AL-01, AL-07            | Rows stay open or parked; no fact is lost                                                                                         | Roll back; retry parked rows                             |
| FM-14 | Bad platform deploy                                  | AL-04, AL-07            | Grants retry                                                                                                                      | Roll back                                                |
| FM-15 | Two runners pick the same work row                   | —                       | The lease update admits one; the platform deduplicates by `grant_id`                                                              | None                                                     |
| FM-16 | Alert email not delivered                            | Missing digest; external heartbeat | `alert` rows retry                                                                                                    | Check Email Routing                                      |
| FM-17 | Issuer key nearing expiry (A25)                      | AL-14                   | —                                                                                                                                 | Rotate (02 §6)                                           |
| FM-18 | Paymob HMAC secret rotated in the dashboard          | AL-02                   | As FM-03                                                                                                                          | Update the secret                                        |
| FM-19 | ABO data loss or bad restore                         | AL-16, reconciliation   | —                                                                                                                                 | §5.1                                                     |
| FM-20 | Platform D1 or DO state loss                         | Reconciliation, AL-10   | —                                                                                                                                 | §5.2, §5.3                                               |
| FM-21 | ABO fails partway through a step                     | AL-01 if a row stalls   | Each step commits in one D1 batch (03 §2.9), so either all of its facts and its next work row exist or none do; the row is retried | None                                                     |
| FM-22 | `getCoverage` fails while a checkout opens           | Logs; AL-04 if it persists | The checkout uses `coverage_view` and records `coverage_source = view` (03 §2.4); the sale proceeds                            | None                                                     |
| FM-23 | Installation deleted with paid time left             | AL-18                   | Binding `held_for_transfer`: AI refused with `transfer_pending`, grants wait as `transient`, no second binding (03 §5.4)          | `beginTransfer`, or void the remaining grants            |
| FM-24 | ABO signing key not registered or revoked on the platform | AL-23              | `grant` and `reverse` work pauses; nothing is parked                                                                              | Register the key or deploy the right secret (02 §6)      |
| FM-25 | One side deployed with a contract version the other does not accept | `contract_version_unsupported` answers; AL-07 on ABO channels, the update state on desktops | Nothing is written; the ABO parks the row, and its event reader keeps its cursor | Deploy the receiver first (04 §7.3), or roll back; retry parked rows |


## 5. Rebuild procedures

**Purpose.** If a database is lost or damaged, the books must be restored from the copies. Think of restoring a shop's receipt book from the carbon copies kept in the vault, then phoning the bank to fill in anything written after the last copy was made. There are three procedures, one per store that can be lost: the ABO's database (§5.1), one clinic's DO (§5.2) and the platform's database (§5.3).

**Rules.**

- These satisfy RC-04.
- **Finish with a cash-up.** Each procedure ends with a clean reconciliation run (§3.3), which proves the restored books agree with each other.
- **Nothing to rebuild in the backend.** The backend has no AI status to rebuild: desktops read it from the platform (04 §4.2).

### 5.1 ABO

**What this is.** Restoring the shop's receipt book. The quick route is the 30-day undo button. Otherwise the book is rewritten from the vault copy, and the gap since the last copy is filled by asking Paymob and the platform.

1. Within 30 days of the damage: restore D1 with Time Travel to a point before it.
2. Otherwise: create an empty D1, replay the `ledger/` NDJSON facts in `fact_seq` order (inserts pass the append-only triggers), then recompute the status tables.
3. Fill the gap after the last exported fact: re-inquire every checkout and payment reference known to the rebuilt set, and every transaction in the provider's dashboard export for the gap window.
4. Compare with the platform's `listGrants`. A paid grant with no payment is re-derived from the provider inquiry; a payment with no grant gets a grant row (its `grant_id` is deterministic, so the platform answers `already_applied`).

Notes on the steps: in step 2, "replay … in `fact_seq` order" means re-inserting the facts one by one in their original order; the inserts are allowed because the append-only triggers block only edits and deletions, not new rows. "Recompute the status tables" rebuilds the "current state" summaries from those facts. In step 3, the **gap window** is the time between the last fact copied to the vault and the damage, and the **provider's dashboard export** is a list of transactions downloaded from Paymob's dashboard. In step 4, a "grant row" is a new `grant` work row.

### 5.2 A clinic's DO

**What this is.** Restoring one clinic cashier's private notebook. Start from the last full picture of the clinic's coverage, then re-apply, in order, everything that happened after it.

1. Load the clinic's last `coverage_event` snapshot (its terms, positions, usage, holds, suspension and epoch) into an empty DO.
2. Apply, in order, every later `grant_ledger` and `grant_void` row and every later hold, release, suspension and transfer event.
3. Re-apply usage recorded after the snapshot from `usage_event` by `term_id`, including shipped `usage_adjustment` rows; `request_id` uniqueness prevents double counting. Retention keeps these rows while their term is unended (03 §8).
4. Compare the result with `coverage_mirror` and alert on any difference. Reservations in flight at the loss are forfeited to the clinic's benefit.

Notes on the steps: **positions** are the terms' places in the queue; **holds** are terms frozen after a reversal. `grant_ledger` and `grant_void` are the platform's lists of applied and cancelled grants. `usage_event` is the platform's log of each AI request's usage, labelled with the term it counted against (`term_id`); `usage_adjustment` rows are usage corrections the DO shipped through its outbox. `request_id` is each AI request's unique id, so no request is counted twice. **Retention** is the purge rule: it keeps these rows while their term is unended (03 §8). "Forfeited to the clinic's benefit" means credits held by requests running at the moment of loss are simply not charged.

### 5.3 Platform D1

**What this is.** Restoring the network's shared filing cabinet. The platform keeps its own vault copy of every grant and void, so it never depends on the ABO for this.

Restore with Time Travel within 30 days. Otherwise rebuild `grant_ledger` and `grant_void` from the R2 `grant-ledger/` objects. Then ask every DO for a fresh snapshot event (an H method run once per installation), which also rebuilds `coverage_mirror`. An "H method" is a platform operation the logged-in operator may run without a passkey (§0.5).

## 6. Staging and launch

**Purpose.** Before real clinics pay real money, every scenario is rehearsed. This section describes the rehearsal (§6.1), the opening-day checklist (§6.2) and the order in which the pieces are built (§6.3).

### 6.1 Staging profile

**What this is.** A dress rehearsal on a fast-forwarded clock. A real month is far too long to wait for a test, so staging shrinks time: a month passes in half an hour, and every renewal, grace period and lapse can be watched in one afternoon.

**Rules.**

- **Same lifecycle, compressed time.** Staging runs the full lifecycle in compressed real time (NFR-07).
- **Same offers.** Offers use the production units and validation, so nothing about the products is faked; only the clock is.
- **The fast-forward.** The staging platform's `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute (03 §6.1).
- **Test money.** The Paymob test integration supplies test cards.

How to read the table: **Offer term** is the length as sold; **Runs for** is how long it lasts in staging; **Grace (7 days)** is the 7-day grace period at 1 minute per day; **Allowance** is the credits included; **Covers** lists the scenarios the offer is used to test. A **low-allowance warning** is the band event at 75 % or 90 % use.


| Test offer          | Offer term | Runs for   | Grace (7 days) | Allowance   | Covers                                                                        |
| ------------------- | ---------- | ---------- | -------------- | ----------- | ----------------------------------------------------------------------------- |
| "Monthly" test      | 1 month    | 30 minutes | About 7 minutes | 20 credits | Purchase, early renewal, lapse, grace, reactivation, exhaustion with and without a prepaid term |
| "Quarterly" test    | 3 months   | 90 minutes | About 7 minutes | 60 credits | Purchase for the quarterly length                                             |
| "Annual" test       | 12 months  | 6 hours    | About 7 minutes | 240 credits | Purchase for the annual length; low-allowance warnings                       |


**Failures staged on purpose.** These are run against these offers:

- a duplicate payment;
- a reversal (a test-card refund made from the dashboard);
- a manual chargeback;
- a lost callback (blocked notify URL, so Paymob's notifications cannot reach the ABO);
- a platform outage (platform route disabled).

Every scenario in §8 is a staging test (FR-90).

**Before staging: a rehearsal at home.** Before staging, the same flows run locally with `wrangler dev` (on the developer's own computer) and no Paymob account. Three tools make that possible:

- **HMAC replay fixture.** A set of saved Paymob notifications that can be sent again on demand, like a recording of real calls replayed to test the phone line. Recorded Paymob callback bodies (test integration, no real card data), re-signed with a local HMAC secret, are posted to `/notify/paymob`. It covers success, decline, refund as parent flags, refund as a child transaction, a bad HMAC, and a replayed body. (Paymob reports a refund either by changing flags on the original transaction, the **parent**, or as a new **child transaction** linked to it; a **replayed body** is the same message sent twice.)
- **Inquiry stub.** A fake Paymob that answers whatever the test script says, like an actor playing the bank clerk. A local stand-in for Paymob's auth, order-inquiry and transaction endpoints (**endpoints** are the web addresses of its API functions), scripted per test: bound or unbound order (whether the Paymob order is the one tied to the checkout), amount mismatch, pending, reversed, timeout, rate limit. The adapter points at it through its base URL setting (the address it sends its questions to).
- **Version matrix.** A grid that tries every pairing of old and new message formats. Each channel is exercised with N, N−1 and an unsupported version (04 §7), including an ABO on N+1 against a platform still on N.

### 6.2 Launch conditions

**What this is.** The opening-day checklist. These are conditions on the production state, not tasks: each line describes how the live system must look on launch day, not work to do. **Production** is the real system that real clinics use, as opposed to staging.

Words used in the list:

- **`/control/*` routes, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, manual entitle path.** Today's ways of switching AI on by hand: the platform's old operator web addresses, the single shared password that protected them, a backend function that set a clinic's AI flag, and the old manual "entitle" operation. All must be gone (FR-91).
- **Pre-launch installations** are clinic identities created before launch, during development or pilots. A **pilot clinic** is one that tried AI before launch. Their **ledgers** (usage and grant records) stay, per RC-05.
- **Bootstrapped** means the very first operator passkey has been registered (§0.5).
- **`ai.contract_versions`** is the backend's own copy of the version numbers; the **shared package** is `packages/vendor-contracts/`, the code both Workers share (04 §7.2).
- **`pg_net`, `http` extension, Edge Function.** `pg_net` and `http` are database add-ons that would let the database make web calls; an Edge Function is a small Supabase-hosted program. None may call the vendor services.
- **`workers_dev` and preview URLs** are extra Cloudflare web addresses that would bypass the Access gate; they must be switched off. A **stored token with production rights** is a saved password that could deploy or change the live system.

- The tenancy retrofit (01 R-1) is live, and RC-06 legal confirmation is recorded (01 R-9).
- No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability` or manual entitle path exists (FR-91).
- Production platform D1 holds no terms or grants. Pre-launch installations are deleted (their ledgers stay, per RC-05). A pilot clinic that keeps AI gets an HP complimentary grant of 30 days (unit `day`) with reason "pre-launch pilot"; this fits the ceilings (03 §3.2), and the clinic then buys like everyone else (FR-92).
- The first operator credential is bootstrapped and a second one is registered (24-hour delay). The issuer and service keys are registered, the platform signing key is set, and the issuer keys are pinned in the ABO's `ISSUER_KEYS`; the ABO's key self-check passes (AL-23 clear).
- Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package (04 §7).
- The backend has no outbound path to vendor hosts: no `pg_net` or `http` extension, and no Edge Function that calls the ABO or the platform (C-02).
- R-9 advice on payer contact data is recorded, and the erasure action (§3.2) has been run once in staging.
- `workers_dev` and preview URLs are off. The audit watcher and heartbeat monitor are live. No stored token has production rights (02 §4.4).

### 6.3 Delivery sequence

**What this is.** The building order, like putting up a house: foundations first, then walls, then the roof. The design ships as separate Spec Kit features (§0.5), in this order. Each one is a precondition of the next and passes its own constitution check.

Words used in the list: **membership** and **active organisation** are the tenancy retrofit's parts (§0.4). **Canonical JSON** is one fixed way of writing a message so both sides compute the same fingerprint; **JWS** is a standard format for signed messages; **WebAuthn** is the passkey standard. **Issuer tokens** are the tokens the backend signs; the **per-clinic coverage ledger** is the DO's record of terms and grants; `VendorEntrypoint` is the set of named operations the platform offers the ABO (04 §1.3); `/v1/capabilities` is the platform route desktops read their status from. **RPCs** are the backend's database functions that desktops call. **Denial states** are the screens shown when AI is refused, and **version headers** carry the contract version on each request. The **viewer** is the old `ai-platform-viewer/` tool that used `/control/*`.

1. **Tenancy retrofit (01 R-1).** Membership, active organisation and `current_org_id()` in the backend. Nothing tenant-scoped in the later features is safe without it (SR-03, A36).
2. **Shared contract package and versioning.** `packages/vendor-contracts/` with canonical JSON, JWS, WebAuthn, message types and the version constants (04 §6.2, §7).
3. **AI Platform rework.** Issuer tokens, tenant bindings, the per-clinic coverage ledger, `VendorEntrypoint`, the status view on `/v1/capabilities` and the removal of `/control/*` (04 §6).
4. **ABO.** Offers, checkouts, the Paymob adapter, the work pipeline, the ledger copy and the console (02 §1.2, 03 §2).
5. **Backend.** Issuer signing and the RPCs of 04 §3.1, with no outbound calls (C-02).
6. **Desktop.** Status reads from the platform, denial states, the administrator billing feature and version headers (04 §3.2, §4.4).
7. **Clean-up of dependent paths.** The viewer, the bootstrap script and the superseded platform documents (04 §6.6).
8. **Staging acceptance.** Every §8 scenario on the staging profile (§6.1), then the §6.2 launch conditions.

Steps 3 and 4 can overlap once step 2 is merged, because they meet only through the shared package and the entrypoint contract.

## 7. Operating cost and moving parts

**Purpose.** The project's founding rules require it to stay small and cheap, sized for clinics, not for a bank. This section counts what the design adds and how much work it creates each day, to show that it fits within the plans already paid for.

**New runtime parts.** One Worker (the ABO), one D1 database, one R2 bucket, an external heartbeat monitor and an external watcher job. The backend gains no extension or job. There are no new servers, queues or databases outside Cloudflare and Supabase (constitution; C-06). A **queue** here means a separate message-queue service; the design uses work rows in D1 instead.

**Daily load.** At a few orders per day (C-08), the steady load is:

- about 1,440 ABO cron runs;
- 288 platform cron runs;
- about 288 status reads a day per open desktop, each one `coverage_mirror` read by primary key and no write;
- about 168·o + 4·L + P/7 reversal inquiries a day, where o is new payments per day, L is payments funding a live, queued or held term, and P is other payments under 180 days old (01 §3.3). At o = 5, L = 300 and P = 1,500 that is about 2,250 a day, or under 2 a minute, plus the checkout sweeps. The per-minute budget (§1) keeps bursts under Paymob's limit;
- about two DO row writes per AI request (01 §3.2).

How to read these numbers: 1,440 is one ABO cron run per minute for a day (60 × 24); 288 is one platform run every 5 minutes (12 × 24); and a desktop that stays open re-reads its status about every 5 minutes, which also gives about 288 reads. In the reversal-inquiry formula, 168·o is 24 hourly checks for 7 days for each day's new payments, 4·L is four 6-hourly checks a day, and P/7 is one weekly check spread over seven days. "Read by primary key" means the database jumps straight to one row, the cheapest possible read. Cloudflare bills a DO mainly by rows written, so two writes per AI request keeps cost low.

That should stay inside the included allowances of the Cloudflare Workers Paid plan (Cloudflare's paid subscription, which includes a monthly amount of usage) and the Supabase project; confirm against the account's plan (NFR-08).

## 8. Acceptance walkthrough

**Purpose.** The seed lists 36 **acceptance scenarios**, A1 to A36 (seed §11): real-life situations such as "the payment notification is lost" or "a chargeback arrives on an old payment", each with the outcome the business requires. Passing all of them in staging is the launch gate (FR-90). This table walks each scenario through the design and says what happens, step by step, like rehearsing every scene of a play before opening night.

**Rules.**

- Each row is the defined, tested outcome (FR-90).
- "Status" marks rows whose outcome depends on something outside the design (§10).

How to read the table:

- **#**: the scenario's number in seed §11. Read the scenario itself there; this table gives only the design's answer.
- **Path through the design**: what the design does, with links to where each step is defined.
- **Status**: **Met** means the design fully delivers the required outcome. **Partial** means it delivers it only under an operating policy that the code cannot enforce (A26; §10). **Conditional** means it holds only once the tenancy retrofit (01 R-1) is live (A36; §10).

Words used in the rows that are not in §0: `GET /v1/payments` and `GET /v1/checkouts?open=1` are the ABO's lists of a clinic's payments and open checkouts; **polling** means asking again every few seconds. The **intention amount** is the price fixed in Paymob's payment session. An **`attempt_declined` event** records a failed card attempt on a checkout. A `duplicate_payment` **notice** is a message shown in the administrator's app. `starts: after_current` is the ABO's answer meaning "this purchase begins when the current term ends". `ends_soon` and `allowance_low` are the notices desktops show near the end date and at the 75 % and 90 % bands. **Serializes admissions** means the DO decides AI requests strictly one at a time; **overshoot** is how far usage may go past the allowance on the last request, at most `w_max − 1` credits, where `w_max` is the largest cost of any one request (03 §6.6). The **successor** is the next queued term. **TB-5** is the trust boundary between the shared backend and the vendor services (02 §2). **Transfer lineage** is the chain linking a moved term back to the grant that first created it (`origin_grant_id`).


| #   | Path through the design                                                                                                                                                                                             | Status      |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| A1  | Checkout (04 §2.2), then callback, inquiry and grant (02 §1.5). The term is active at once with the full offer allowance (03 §6.1). The payment appears in `GET /v1/payments`. The admin desktop shows Active by polling the checkout, then re-reads its status from `/v1/capabilities`. Tested for 1, 3 and 12 months | Met |
| A2  | Nothing on the provisioning path needs the desktop. Any desktop's status read from the platform shows active on open; `GET /v1/checkouts?open=1` shows the outcome                                                 | Met         |
| A3  | The checkout sweep inquires at +2, +5, +10 and +20 minutes and provisions; AL-03 is raised                                                                                                                          | Met         |
| A4  | The grant row retries every 15 minutes for 4 days; AL-04 is raised hourly. When the platform returns, the grant applies; the term starts at activation, so no paid days are lost (01 I-2)                             | Met         |
| A5  | The declined attempt is an `attempt_declined` event and the checkout stays open. The later success is one payment and one grant. Nothing is cancelled                                                               | Met         |
| A6  | Two payments. The second is `likely_duplicate` (03 §5.2), stacks as the next term, and raises a `duplicate_payment` notice and AL-09                                                                                | Met         |
| A7  | The payment is bound to the monthly checkout's order and snapshot, so the monthly term is granted at the monthly price. The annual checkout expires unpaid                                                          | Met         |
| A8  | The intention amount is fixed at creation from the checkout snapshot, and the grant uses the same snapshot                                                                                                          | Met         |
| A9  | The renewal queues. The current allowance is unchanged; the new term starts at the old end date with its own allowance (03 §6.8)                                                                                    | Met         |
| A10 | The DO enters grace at the end date and ends it at `grace_ends_at` on its own alarm and on admission, with no ABO involvement. The status view computes the lapse from dates (04 §4.3)                             | Met         |
| A11 | The new term starts at activation, seconds after payment (03 §6.8)                                                                                                                                                  | Met         |
| A12 | The tenant comes from the backend session; nothing is stored on the desktop                                                                                                                                         | Met         |
| A13 | Issuer-key rotation (02 §6) does not touch the tenant binding or the terms                                                                                                                                          | Met         |
| A14 | Same-org `beginTransfer` (HP) retires the old binding and creates a new one with the next epoch; the new DO waits in `awaiting_transfer`. `transferOut` and `transferIn` then move the terms with their `origin_grant_id`. The old identity ends `transferred` and refuses new grants; `coverage_mirror` and the ABO's `coverage_view` follow the higher epoch (03 §2.10). AL-11 is raised, and reconciliation matches the transfer to its authorisation (§3.3) | Met |
| A15 | Manual chargeback (HP), effect `end_current`. The grant is voided, the term ends `reversed` with no grace, and queued terms are held. AL-06 is raised                                                               | Met         |
| A16 | The refund arrives as parent flags or a child transaction. The adapter folds it into a `reversal`, never a payment; inquiry confirms; the effect follows 03 §5.5, through transfer lineage if the term moved; AL-06. A lost callback is caught within an hour in the payment's first 7 days, within 6 hours while it funds a live, queued or held term, and within a week otherwise up to 180 days (§1) | Met |
| A17 | Effect `none`: recorded and alerted, with no service change                                                                                                                                                         | Met         |
| A18 | Payout import raises `unrecorded_reversal`. The operator records the chargeback (HP) and the effect applies. Once linked to the payout line, reconciliation is clean                                               | Met         |
| A19 | The trial is a complimentary term. The purchase queues after it, so there is no gap and no overlap                                                                                                                  | Met         |
| A20 | An HP complimentary grant of 14 days (unit `day`), within the 31-day ceiling, queued after existing coverage. AL-11 and the digest report it; reconciliation matches it to the `operator_action`                                | Met         |
| A21 | The retired offer leaves `/v1/offers`. Existing terms keep their plan snapshot until they end. A stale offer id answers `offer_unavailable`                                                                        | Met         |
| A22 | No token can be obtained for another tenant; foreign ids answer `not_found`; nothing is locked by an open checkout                                                                                                  | Met         |
| A23 | AL-02 within 15 minutes; sweeps confirm by inquiry                                                                                                                                                                  | Met         |
| A24 | HP delete marks the installation `deleted`. With paid time left, the binding is `held_for_transfer` and AL-18 is raised: AI is refused with `transfer_pending`, a renewal paid meanwhile waits as `transient`, and no second binding appears. The operator moves the time with `beginTransfer` from the held binding, or voids the remaining grants, which retires it (03 §5.4, 04 §1.3) | Met |
| A25 | No per-clinic credential exists. Issuer keys raise AL-14 30 days ahead and rotate without an outage                                                                                                                 | Met         |
| A26 | Stored tokens have no production rights by policy; HP needs a passkey; the watcher alerts on deploys                                                                                                                | Partial     |
| A27 | Without the passkey, no grant is possible. With it, the 31-day ceiling blocks a year, an override needs a second assertion and raises AL-12, AL-11 fires within minutes, and grants can be listed and voided      | Met         |
| A28 | Staff get `ends_soon` at 7, 3 and 1 days in the staff form. The lapse shows from stored dates. Staff cannot mint billing tokens, `/v1/coverage` refuses them, and `/v1/usage` is gone                             | Met         |
| A29 | Band events at 75 % and 90 % produce `allowance_low` for every role; admission continues                                                                                                                           | Met         |
| A30 | The app offers the change for the next term only; `POST /v1/checkouts` answers `starts: after_current`; nothing changes now                                                                                        | Met         |
| A31 | Exhaustion ends the term on that request with no grace. A new purchase starts at activation; the rest of the calendar is forfeited (03 §6.8)                                                                       | Met         |
| A32 | The prepaid term activates at the exhaustion instant with its full allowance and runs one month from then (03 §6.8)                                                                                                | Met         |
| A33 | Retired offers are not listed; the owner picks a current offer                                                                                                                                                      | Met         |
| A34 | The DO serializes admissions: one crosses, exhaustion is recorded once, overshoot is at most `w_max − 1` (03 §6.6), and the other request goes to the successor or is refused `allowance_exhausted`              | Met         |
| A35 | Neither service holds any database credential or Supabase JWT, and there is no network path between them and the backend (C-02, 02 §2 TB-5, §4.3)                                                                | Met         |
| A36 | The ABO and RPCs take the tenant only from the session and answer `not_found` across tenants                                                                                                                        | Conditional |


## 9. Traceability matrix

**Purpose.** This is the checklist that maps each promise to where it is kept. It lists the seed's goals, requirements, constraints, code gaps and expansions, one row each. Following the row's references leads to the section of the design that keeps that promise. If someone asks "where does the design make sure of FR-41?", the answer is one row away.

How to read the table:

- **ID**: the item in the seed (§0.7 explains the prefixes). The last row, A1–A36, covers all the acceptance scenarios at once.
- **Satisfied in**: where the design keeps it. A bare § refers to this document; "03 §5.2" means section 5.2 of the data model, and so on. A name in `code font` after a reference (such as `plan_version` or `placement`) is the field or file at that place.
- **Status**: how fully it is kept.

Status values:

- **Met.** Fully delivered.
- **Met (I-n)** means met as interpreted in 01 §4: the seed's wording was open or needed adjusting, and the design follows the reading given in interpretation I-n.
- **Seam** means the expansion seam exists, as required. An expansion seam is a hook built now so a future feature (an X-n item) can be added later without rework; the feature itself is not built.
- **Conditional** means it depends on the tenancy retrofit (01 R-1).
- **Respected** (for C-n constraints) means the design stays within that constraint.
- **Closed** (for P-n gaps) means the design removes that gap in today's AI Platform code.
- **Partial** and **Not met** are explained in §10. Some rows add a short caveat, such as "with the lock limit in §10", that is also explained there.


| ID     | Satisfied in                                  | Status      |
| ------ | --------------------------------------------- | ----------- |
| G1     | 02 §1.5; 04 §2.2                              | Met         |
| G2     | 02 §4.3                                       | Met         |
| G3     | 03 §5.6; §2; §4                               | Met         |
| G4     | 03 §2                                         | Met         |
| G5     | 04 §4.4; 03 §6.5                              | Met         |
| G6     | 02 §1.2; 04 §5                                | Met         |
| G7     | §3                                            | Met         |
| G8     | §7; 01 §6                                     | Met         |
| FR-01  | 03 §2.2; §3.2                                 | Met         |
| FR-02  | 03 §2.2; 04 §1.4                              | Met         |
| FR-03  | 03 §2.2                                       | Met         |
| FR-04  | 03 §2.2, §2.4                                 | Met         |
| FR-05  | 04 §2.2                                       | Met         |
| FR-06  | 03 §2.2; 04 §2.3                              | Met         |
| FR-07  | 03 §6.2, §6.3                                 | Met         |
| FR-08  | 03 §5.4, §6.4                                 | Met         |
| FR-09  | 03 §6.2; 04 §4.1                              | Met         |
| FR-10  | 04 §2.1, §3.1                                 | Met (I-1)   |
| FR-11  | 04 §5.3                                       | Met         |
| FR-12  | 02 §1.5; 01 §3.3                              | Met         |
| FR-13  | 04 §5.1, §5.3                                 | Met         |
| FR-14  | 03 §5.1; 04 §2.2                              | Met         |
| FR-15  | 03 §5.1                                       | Met         |
| FR-16  | 04 §5.2; 03 §2.6                              | Met         |
| FR-17  | 04 §2.2                                       | Met (I-9)   |
| FR-20  | 04 §5.1                                       | Met         |
| FR-21  | 03 §6.1, §6.3                                 | Met         |
| FR-22  | 03 §6.4                                       | Met (I-6)   |
| FR-23  | 03 §6.2, §6.5; 02 §4.3                        | Met         |
| FR-24  | 03 §5.4; 04 §2.1                              | Met (I-2)   |
| FR-25  | 02 §6; 03 §7                                  | Met         |
| FR-26  | 04 §4.2                                       | Met         |
| FR-27  | 04 §4.2, §4.4                                 | Met         |
| FR-30  | 04 §2.2                                       | Met         |
| FR-31  | 04 §2.2; 03 §6.1                              | Met         |
| FR-32  | 03 §5.3                                       | Met         |
| FR-33  | 03 §6.3                                       | Met (I-2)   |
| FR-34  | 03 §6.7; 04 §4.2                              | Met         |
| FR-35  | 03 §5.3                                       | Met         |
| FR-36  | 04 §1.4; §3.2, §3.3                           | Met         |
| FR-37  | 03 §6.1; §8 A19                               | Met         |
| FR-38  | 02 §3.3                                       | Met         |
| FR-40  | 03 §5.1                                       | Met         |
| FR-41  | 03 §5.2                                       | Met (I-8)   |
| FR-42  | 04 §5.3; 03 §2.7                              | Met         |
| FR-43  | 03 §5.5                                       | Met (I-3)   |
| FR-44  | §3.2                                          | Met         |
| FR-45  | 04 §5.1; 03 §2.7                              | Seam        |
| FR-50  | 03 §2.6, §2.7, §7                             | Met         |
| FR-51  | 03 §2.3; 04 §2.2                              | Met         |
| FR-53  | 04 §1.7, §6.1                                 | Met         |
| FR-60  | 04 §4.1                                       | Met         |
| FR-61  | 04 §4.1, §4.2, §4.4                           | Met         |
| FR-62  | 01 §3.4; 04 §3.1, §4.2                        | Met         |
| FR-63  | 04 §4.3; 03 §6.7                              | Met (I-7), with the desktop lag in §10 |
| FR-64  | 04 §4.4                                       | Met         |
| FR-65  | 04 §4.4                                       | Met         |
| FR-66  | 03 §7                                         | Met         |
| FR-70  | §3.1                                          | Met         |
| FR-71  | §3.2                                          | Met         |
| FR-72  | 04 §1.3; 03 §5.4                              | Met         |
| FR-73  | 03 §2.10; §3.2                                | Met         |
| FR-74  | 03 §5.7; §3.2                                 | Met (I-4)   |
| FR-80  | §3.3                                          | Partial     |
| FR-81  | §2, §3.3                                      | Met         |
| FR-82  | §1; 01 §3.3                                   | Partial     |
| FR-90  | §6.1, §8                                      | Met         |
| FR-91  | 04 §1.3, §3.1, §6.1; §6.2                     | Met         |
| FR-92  | §6.2                                          | Met         |
| SR-01  | 02 §4.3                                       | Met         |
| SR-02  | 03 §2.11, §7                                  | Met         |
| SR-03  | 02 §4.3; 04 §2.1                              | Conditional |
| SR-04  | 04 §2.2                                       | Met         |
| SR-05  | 04 §1.4, §1.6                                 | Met         |
| SR-06  | 02 §3.3                                       | Met         |
| SR-07  | 04 §3.1; 03 §4                                | Met         |
| SR-08  | 02 §4.3; 04 §2.2, §3.1                        | Conditional |
| SR-09  | 02 §2 TB-5, §4.3                              | Met         |
| SR-10  | 03 §2.11; 04 §1.7                             | Met         |
| SR-11  | 02 §6                                         | Met         |
| SR-12  | 02 §4                                         | Met         |
| SR-13  | 04 §4.3; 02 §4.2 AD-15                        | Met         |
| SR-20  | 02 §2 TB-7, §3.3                              | Met         |
| SR-21  | 02 §3.3, §4.4                                 | Partial     |
| SR-22  | 02 §1.4                                       | Met         |
| SR-23  | 02 §5; §2 AL-11; §3.4                         | Met         |
| SR-24  | 04 §1.4; 03 §3.2                              | Met         |
| SR-25  | 04 §1.3; §3.2                                 | Met         |
| NFR-01 | 03 §5.6; §4                                   | Met         |
| NFR-02 | 03 §7; 04 §2.2; §1                            | Met         |
| NFR-03 | 04 §1.2                                       | Met         |
| NFR-04 | §2; 02 §5                                     | Met         |
| NFR-05 | 03 §6.5; 04 §4.1                              | Met         |
| NFR-06 | 03 §6.2–§6.6                                  | Met         |
| NFR-07 | §6.1                                          | Met         |
| NFR-08 | §7                                            | Met         |
| NFR-09 | 04 §7, §4.4; §6.1                             | Met         |
| RC-01  | 03 §2.1, §8                                   | Met         |
| RC-02  | 03 §2.5                                       | Met         |
| RC-03  | 03 §8; 02 §4.4                                | Met, with the lock limit in §10 |
| RC-04  | §5                                            | Met         |
| RC-05  | 03 §8; 04 §6.1                                | Met         |
| RC-06  | 01 R-9; §6.2                                  | Not met     |
| C-01   | 04 §6                                         | Respected   |
| C-02   | 01 §3.4, R-1; 02 §1.1, §2 TB-5; §6.2          | Respected   |
| C-03   | 04 §2.1                                       | Respected   |
| C-04   | 04 §4.4; §4 FM-11, FM-12                      | Respected   |
| C-05   | 04 §5.3                                       | Respected   |
| C-06   | 02 §1.1                                       | Respected   |
| C-07   | 02 §1.2                                       | Respected   |
| C-08   | §7                                            | Respected   |
| P-01   | 03 §6.2, §6.4                                 | Closed      |
| P-02   | 03 §6.1                                       | Closed      |
| P-03   | 03 §5.4, §6.3                                 | Closed      |
| P-04   | 03 §3.2 `plan_version`; 04 §6.1               | Closed      |
| P-05   | 04 §6.1 `src/worker.ts`                       | Closed      |
| P-06   | 02 §3.1; 04 §6.1                              | Closed      |
| P-07   | 02 §3.3; 04 §6.1                              | Closed      |
| P-08   | 03 §6.5; 04 §4.1, §6.1                        | Closed      |
| P-09   | 04 §4.1                                       | Closed      |
| P-10   | 04 §2.1                                       | Closed      |
| X-01   | 04 §5.1; 03 §2.7                              | Seam        |
| X-03   | 03 §2.4; 04 §5.1                              | Seam        |
| X-04   | 03 §2.4; 04 §5.1                              | Seam        |
| X-05   | 04 §4.2                                       | Seam        |
| X-06   | 04 §1.4 `placement`; 03 §5.3                  | Seam        |
| X-07   | 04 §1.4 `kind`; 03 §5.3                       | Seam        |
| X-08   | 03 §2.4                                       | Seam        |
| X-09   | 04 §1.4 `approvals`                           | Seam        |
| X-10   | 04 §7                                         | Seam        |
| A1–A36 | §8                                            | Met, except A26 (Partial) and A36 (Conditional) |


**Where this design refines the decision memo.** The decision memo (01) was written first, in Phase 1. While the detailed design (Phase 2, documents 02 to 05) was worked out, some of its points were made more precise. Phase 2 refines 01 in these places; none reverses a [Decided] item. (In the seed, [Decided] marks a product-owner decision; [Assumed] marks a working assumption that may be confirmed or overridden.)

Words used in the list: `placement` says where a new grant goes (`queue` after existing coverage, or `immediate`). A **service binding** is the private connection from the ABO to the platform inside Cloudflare, not reachable from the internet. "Grant-origin reconciliation" is the check that every grant came from a payment or an authorised action (§3.3). The **ABO–platform channel** is the connection between the two Workers.

- **X-06 and X-07 share one mechanism.** FR-32 needs an operator-only `term_adjustment` at launch, and a later paid adjustment reuses it. The X-06 seam therefore accepts only `placement = queue` at launch; `immediate` is rejected rather than accepted (04 §1.4).
- **Checkout states.** There is no `superseded` state: a new checkout leaves an open one payable (03 §2.4, FR-15).
- **Coverage events.** The ABO reads the platform's coverage events (01 §3.7) for its console and grant-origin reconciliation. Duplicate classification reads `getCoverage` live instead. Nothing depends on the platform calling the ABO.
- **Ceilings (01 I-10).** Allowance ceilings are counted in months of the plan's `max_allowance_per_month`, and `term_adjustment` additions and extensions count toward the 90-day window (03 §3.2).
- **Issuer keys at the ABO.** The ABO verifies billing tokens against issuer keys pinned in its own configuration, not the platform registry (02 §6, 04 §2.2).
- **Unsigned coverage events.** Events the ABO reads are not signed, because they travel over the service binding and `coverage_view` serves only the console, reconciliation and the checkout fallback; the platform key signs receipts only (04 §1.8).
- **No backend link to the vendor services.** The status feed to the backend was dropped when the product owner revised C-02 (01 I-11); desktops read status from the platform instead (01 §3.4, 04 §4.2).
- **Deletion with paid time left.** The binding is held for transfer instead of retired, so an org never has two live identities (03 §5.4).
- **Payer contact data.** Contact values live only in the erasable `billing_contact` table; facts and the ledger copy hold its version and hash (03 §2.3).
- **Versioning on every channel.** X-10 covered the ABO–platform channel and tokens; NFR-09 extends it to every request and response (04 §7).
- **Reversal sweep cadence.** Tiered by payment age and whether it funds live coverage, under one inquiry budget (01 §3.3, §1).
- **Checkout without the platform.** A failed `getCoverage` falls back to `coverage_view` instead of blocking the sale (03 §2.4).

## 10. Unmet and partly met requirements

**Purpose.** An honest list of the promises the design cannot fully keep on its own, and why. A good inspector's report does not hide the cracks; it says where they are, how serious they are, and what would fix them. Most gaps here come from outside the design: Paymob's missing features, a legal confirmation still pending, or the backend's tenancy retrofit that must be built first.

How to read the table: **ID** is the requirement or risk; **Gap** is what is not fully delivered; **Why, and what closes it** explains the cause and what would remove the gap.

Words used in the table that are not in §0: a **payout API** would be a way for the ABO to fetch payout data automatically instead of a CSV; `payoutLines` is the provider port's slot ready for it (04 §5.1). A **drift alert** is the alert raised when reconciliation finds the books disagree. A **leaked deploy or D1-write credential** is a stolen password that can change the live code or database directly, bypassing every in-code check. **pgsodium** is a database encryption add-on that Supabase plans to retire; an **Edge Function signer** would sign tokens outside the database instead. **EdDSA-only credentials** means accepting only passkeys that use the EdDSA signature type, avoiding the format conversion the other common type needs in Workers (01 R-5). A **reversal event feed** would be a provider-side list of refunds and chargebacks that could be replayed. Egypt's **Personal Data Protection Law** is Law No. 151 of 2020 (01 R-9).


| ID                     | Gap                                                                                                                                                                                                                                  | Why, and what closes it                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-80                  | Payout matching needs the operator to import Paymob's dashboard CSV each month; it is not automatic                                                                                                                                  | Paymob offers no payout API (01 R-2). The import is one routine action, after which matching and drift alerts are automatic. It closes when a provider offers an API, through `payoutLines` |
| SR-21, A26             | A leaked deploy or D1-write credential bypasses every in-code check                                                                                                                                                                 | This is inherent (SR-12). It holds only under the 02 §4.4 policy, with the external audit watcher; spike R-6                                                  |
| SR-03, SR-08, A36      | Tenant isolation in the backend depends on the membership, active-org claim and `current_org_id()` retrofit                                                                                                                         | The backend is single-tenant today (01 T-1, T-2). The ABO and platform sides are complete; the retrofit is a separate precondition feature (01 R-1)            |
| RC-06                  | Legal confirmation of the no-refund policy                                                                                                                                                                                           | Outside the design. It is a launch condition (§6.2); the terms shown at checkout are a versioned record (03 §2.2), so the text can follow the advice          |
| 01 R-9 (personal data) | How long payer contact data and raw provider bodies may be kept, and when they must be erased, is not yet confirmed under Egypt's Personal Data Protection Law                                                                        | Outside the design. The data is already confined to one erasable table and an unlocked R2 prefix, with an HP erasure action (03 §2.3, §3.2), so any retention period the advice sets can be applied |
| RC-03                  | An account-level token can remove the R2 bucket lock                                                                                                                                                                                 | Detected by the daily lock check (AL-16); the platform's grant ledger in its own bucket is a second copy                                                      |
| FR-82                  | Lost payment callbacks are recovered within minutes by the checkout sweeps. Lost reversal notices are recovered within an hour in a payment's first 7 days, within 6 hours while it funds a live, queued or held term, and within a week for older payments | Paymob has no event list to replay, so a lost refund callback is found only by inquiring each payment. Minute-level polling of every live payment would multiply inquiry volume for little gain; a reversal of an old payment has no service effect (A17). It closes when a provider offers a reversal event feed |
| FR-63                  | The 1-minute bound applies to what the platform answers. A desktop can show the change up to 5 minutes later unless it opens, resumes or sees a denial first                                                                          | Approved in 01 §3.4; FR-64 covers the lag                                                                                                                     |
| Spike-dependent items  | R-2 (Paymob redelivery, second success on one intention, order listing, expiry default); R-3 (issuer key custody without pgsodium); R-5 (WebAuthn and Access details)                                                                  | The design names a fallback for each: inquiry sweeps for R-2; an Edge Function signer for R-3; EdDSA-only credentials for R-5 |
| 02 AD-8                | A compromised ABO can fabricate paid grants within the plan bounds until velocity alerts or reconciliation catch it                                                                                                                  | Inherent: the platform cannot verify payments without provider data, which SR-10 and FR-53 forbid                                                             |

