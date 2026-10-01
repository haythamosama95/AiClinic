# AI Billing Orchestrator — Contracts

**Status:** Phase 2 design. **Date:** 2026-10-01.

Start with section 0. It explains what this document is for, the systems that talk to each other, and every term used later. Sections 1 to 7 keep their numbers because the other design documents cite them (for example "04 §1.3").

Requirement IDs (such as FR-13 or SR-10) refer to the [seed](00-abo-requirements-seed.md); "01 §n", "02 §n", "03 §n" refer to the [decision memo](01-abo-design-decisions.md), the [architecture and threat model](02-abo-architecture-and-threat-model.md) and the [data model](03-abo-data-model-and-lifecycle.md). The key to every code is in §0.8.

Two ground rules apply to the whole document (JSON, minor units and UTC are explained further in §0.6):

- **Field lists are normative.** "Normative" means binding: the field names and rules written here are the agreed contract, not loose examples.
- **Wire encodings.** Everything sent between systems (on "the wire") is JSON with snake_case keys (lower-case words joined by underscores, such as `grant_id`), money in minor units (whole piastres, not pounds), and times in UTC ISO-8601 form.

## Table of Contents

0. [Start here: the big picture](#0-start-here-the-big-picture)
   - [What we are trying to achieve](#01-what-we-are-trying-to-achieve)
   - [The whole system in one analogy](#02-the-whole-system-in-one-analogy)
   - [The systems and the channels between them](#03-the-systems-and-the-channels-between-them)
   - [What a contract is](#04-what-a-contract-is)
   - [Business words](#05-business-words)
   - [Technical words](#06-technical-words)
   - [One purchase, seen as messages](#07-one-purchase-seen-as-messages)
   - [How to read the rest of this document](#08-how-to-read-the-rest-of-this-document)
1. [ABO and AI Platform](#1-abo-and-ai-platform)
   - [Transport and versioning](#11-transport-and-versioning)
   - [Result envelope](#12-result-envelope)
   - [Method catalogue](#13-method-catalogue)
   - [Grant envelope and validation](#14-grant-envelope-and-validation)
   - [Operator assertion](#15-operator-assertion)
   - [Receipt](#16-receipt)
   - [Coverage snapshot](#17-coverage-snapshot)
   - [Coverage events](#18-coverage-events)
2. [Tokens and ABO clinic API](#2-tokens-and-abo-clinic-api)
   - [Token claims](#21-token-claims)
   - [ABO clinic API](#22-abo-clinic-api)
   - [ABO errors](#23-abo-errors)
3. [Flutter and shared backend](#3-flutter-and-shared-backend)
   - [RPCs](#31-rpcs)
   - [Affected backend and frontend files](#32-affected-backend-and-frontend-files)
4. [Desktops and AI Platform](#4-desktops-and-ai-platform)
   - [Clinic routes and denial codes](#41-clinic-routes-and-denial-codes)
   - [Status view and notice codes](#42-status-view-and-notice-codes)
   - [Read-time computation](#43-read-time-computation)
   - [Desktop behaviour](#44-desktop-behaviour)
5. [Provider port](#5-provider-port)
   - [Operations](#51-operations)
   - [Normalised types](#52-normalised-types)
   - [Paymob adapter](#53-paymob-adapter)
6. [AI Platform change list](#6-ai-platform-change-list)
   - [Existing source files](#61-existing-source-files)
   - [New source files](#62-new-source-files)
   - [D1 migrations](#63-d1-migrations)
   - [wrangler.toml](#64-wranglertoml)
   - [Tests](#65-tests)
   - [Other affected paths](#66-other-affected-paths)
7. [Contract versioning](#7-contract-versioning)
   - [Channels](#71-channels)
   - [Rules](#72-rules)
   - [Changing a version](#73-changing-a-version)

---

## 0. Start here: the big picture

### 0.1 What we are trying to achieve

AiClinic's desktop app has an optional, paid AI add-on. The **AI Billing Orchestrator (ABO)** makes buying it self-service: a clinic administrator picks an offer in the app, pays on the payment provider's web page, and AI switches on by itself within about a minute. It keeps working until the paid time or the paid usage runs out, and then it stops on time. The [data model](03-abo-data-model-and-lifecycle.md) (03) describes *what is written down* to make that work.

This document describes *what is said*. Several separate programs take part in a purchase, and they only cooperate by sending each other messages. For every pair of programs that talk, this document fixes exactly:

1. **Who may call whom, and over what kind of connection.** Some programs may never call each other at all.
2. **What each request contains.** Every field, its type and its allowed values.
3. **What each answer looks like.** Including every way the answer can say "no", and what the caller must do next.
4. **What proof the caller must show.** A signed token, a digital signature, or the operator's touch on a hardware key.
5. **How the message formats can change later** without breaking a clinic that has not updated its app yet.

It also lists which existing source files must change to match these message formats (§3.2 and §6), so every rule can be traced to code.

Four goals shape every contract here:

- **No one can buy AI time without real proof.** Every message that adds AI time carries a signature or a fresh operator approval, and the receiver checks it itself.
- **Each connection carries only what it needs.** A badge for the billing shop cannot run AI, and a badge for AI cannot open a checkout. No prices or payment details travel to places that do not need them.
- **Every answer tells the caller exactly what to do.** "Done", "already done", "never retry" and "retry later" are distinct answers, so retries are safe and nothing is left guessing.
- **Old and new software keep talking during an upgrade.** Every message carries a version number, and each receiver accepts the current and the previous version.

### 0.2 The whole system in one analogy

Think of a **prepaid mobile phone bundle**, the same picture used in 03. You walk into a shop, choose a bundle from the price board, pay at the till, and the network adds the bundle to your SIM card. Every call uses some units. When the month ends or the units run out, the bundle ends.

This document is about the **paperwork that passes between the offices** in that picture. A **contract** is the agreed shape of each form or letter: which office may send it, which boxes it has, what the reply looks like, and what every refusal reason means. If both offices fill in the same form the same way, they never misunderstand each other.

| Mobile bundle world                                                   | In this design                                       | Explained in |
| --------------------------------------------------------------------- | ---------------------------------------------------- | ------------ |
| The shop: price board, till and receipt book                          | The **ABO**                                          | §0.3         |
| The phone network                                                     | The **AI Platform**                                  | §0.3         |
| The clinic's dedicated cashier with a private notebook, one customer at a time | The clinic's **Durable Object (DO)**        | §0.3         |
| The ID office that issues temporary visitor badges                    | The **shared backend**, which issues **tokens**      | §2           |
| The bank's card terminal                                              | **Paymob**                                           | §5.3         |
| A translator for the bank's language                                  | The **Paymob adapter**                               | §5           |
| The shop owner                                                        | The **operator**                                     | §1.5         |
| The agreed shape of a form exchanged between two offices              | A **contract**                                       | §0.4         |
| The standard reply slip with tick-boxes                               | The **result envelope**                              | §1.2         |
| The menu of counter services, and which ID each needs                 | The **method catalogue**                             | §1.3         |
| A sealed order form: "add this bundle to this SIM"                    | The **grant envelope**                               | §1.4         |
| The owner's signature in front of a witness, for one specific form    | The **operator assertion**                           | §1.5         |
| A signed delivery note from the network                               | The **receipt**                                      | §1.6         |
| A photo of the SIM's balance at one moment                            | The **coverage snapshot**                            | §1.7         |
| Change notices posted to the shop, numbered in order                  | **Coverage events**                                  | §1.8         |
| Visitor badges with an expiry time and a named destination            | **Tokens**                                           | §2.1         |
| The specific reason ticked on a refusal slip                          | **Error codes** and **denial codes**                 | §2.3, §4.1   |
| A universal plug socket that any bank's terminal can plug into        | The **provider port**                                | §5           |
| A renovation work order listing every room to change                  | A **change list**                                    | §3.2, §6     |
| Two offices agreeing to accept both the old and new form during a changeover | **Contract versioning**                       | §7           |

Keep this picture in mind. Each later section zooms into one form or one counter.

### 0.3 The systems and the channels between them

**The systems.**

| System                             | What it is                                                                                                                          | Analogy                                                    |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| **Desktop app**                    | The clinic's Flutter app on Windows. A clinic has several desktops. An **administrator** can buy; **staff** only use AI             | The customer                                               |
| **Shared backend**                 | One Supabase (PostgreSQL database) project that holds every clinic's data. Each clinic is a **tenant** inside it                    | The ID office                                              |
| **ABO**                            | A new program on Cloudflare (a **Worker**: code that runs on Cloudflare's servers when a request arrives), with its own storage     | The shop, with price board, till and receipt book          |
| **ABO console**                    | The operator's web page (`ops.<vendor-domain>`), served by the ABO, behind **Cloudflare Access** (a login gate)                      | The shop owner's back office                               |
| **AI Platform**                    | The existing Cloudflare Worker that serves AI requests and alone decides whether each one is allowed                                 | The phone network                                          |
| **Per-clinic Durable Object (DO)** | A Cloudflare feature: one small program instance per clinic, with its own private storage, that handles one request at a time       | The clinic's dedicated cashier with a private notebook     |
| **Paymob**                         | The payment provider (Egypt). Shows a hosted payment page, sends notifications, answers status questions                            | The bank's card terminal                                   |
| **Paymob adapter**                 | The only part of the ABO that knows Paymob's formats                                                                                | A translator                                               |
| **Operator**                       | The developer, the vendor's single human operator                                                                                   | The shop owner                                             |

**The channels.** A **channel** is one direction of conversation between two systems, with its own form shapes. The document is organised by channel:

| Channel                                        | Kind of connection                                                    | Section |
| ---------------------------------------------- | --------------------------------------------------------------------- | ------- |
| ABO to AI Platform                             | A private Cloudflare connection (a service binding), not the internet | §1      |
| Desktop to ABO (the clinic API)                | HTTPS over the internet, with a billing token                         | §2      |
| Desktop to shared backend                      | Database function calls (RPCs)                                        | §3      |
| Desktop to AI Platform                         | HTTPS over the internet, with an AI token                             | §4      |
| ABO to Paymob, through the adapter             | Paymob's own web API and notifications                                | §5      |

Two "never" rules frame all of them:

- **The shared backend talks to no one.** It never calls the ABO or the AI Platform, and neither of them calls it (rule C-02). Its only part is to sign tokens for desktops. Like an ID office, it hands out badges and never phones the shop or the network.
- **The AI Platform never calls the ABO.** The ABO always asks; the platform only answers (01 §3.7).

Section 6 is not a channel: it is the AI Platform's change list. Section 7 gathers the versioning rules for every channel.

### 0.4 What a contract is

A **contract** here is the exact agreement between two systems about the messages they exchange. It covers four things, like the rules printed on the back of an official form:

- **The form's shape.** Which fields exist, their names and types, which are required, and which values are allowed.
- **Who may submit it, and with what ID.** A token, a signature or an operator approval.
- **The reply slip.** What a success looks like, and the full list of refusal reasons, each with a fixed meaning.
- **The form's edition number.** A **contract version**, so both sides know which edition of the form they are holding (§7).

A contract is not code. Two independently written programs can both follow it, and each can be upgraded separately as long as they keep to the agreed shapes.

### 0.5 Business words

These are the same words 03 uses; they are repeated here briefly so this document can be read on its own.

**Who is who**

- **Clinic, tenant, organisation, `org_id`.** One customer clinic. In the shared backend it is a *tenant*: one of many customers sharing one database. Its id is `org_id`, the only clinic key used across all systems.
- **Member, membership role, branch.** A **member** is a clinic user. Their **membership role** says what they may do; only `administrator` may buy. Other members are **staff**. A **branch** is one site of a multi-site clinic.
- **Installation, `installation_id`.** The clinic's identity on the AI Platform, like the SIM card the network knows. It is a separate id from `org_id`. An installation can be marked `deleted`.
- **Tenant binding and epoch.** The record that links an `org_id` to its current `installation_id`, like the contract that links a customer to a SIM. If the platform identity has to be re-created, a new binding is made and its **epoch** (a counter: 1, 2, 3 …) goes up. A binding is `active`, retired, or `held_for_transfer` (frozen because paid time is still on it and must be moved first).
- **Operator.** The developer, the vendor's single human operator, working in the ABO console.
- **Billing contact.** The payer's name, email and phone, which Paymob requires.

**What is sold**

- **Plan and plan version.** The AI Platform's definition of *what AI* a clinic gets: which features (**capabilities**), the most expensive model class it may use (**cost class**), how many requests may run at once (**concurrency limit**), and the largest allowance per month. A published plan version never changes; a change means a new version.
- **Offer and offer version.** What the shop sells: one plan version for a length of time at a price, with an allowance and grace. Repricing makes a new offer version. An offer can be **retired** (taken off sale), and a version is **superseded** when a newer one replaces it.
- **Terms of sale (`terms_version`).** The legal text the buyer accepts before paying. Not to be confused with a *term* below.
- **Credits, allowance and band.** Usage is counted in **credits**. The **allowance** is the number of credits a term includes. The **band** is a coarse "how much is used" marker: `ok`, `75` (75% used), `90` or `exhausted`.

**What is bought and owned**

- **Checkout.** One attempt to buy one offer, like the order slip at the till. It freezes the price and contents when opened.
- **Payment.** Money that Paymob has confirmed was received for a checkout.
- **Grant.** An instruction to the AI Platform: "add this much AI time to this clinic". Its **source** is a payment (**paid**), an operator gift (**complimentary**) or a move between identities (**transfer**). A **term adjustment** is a complimentary grant that changes the current term instead of adding a new one.
- **Term.** The unit of AI time a grant creates: a span of dates plus its allowance. A term is active, **queued** (waiting its turn), **held** (frozen after a reversal, waiting for the operator), in grace, or ended.
- **Placement.** Where a new term goes. At launch only `queue` is allowed: broadly, the term starts now if nothing is running, otherwise after the current one (exact rules in 03 §6.1).
- **Coverage.** All of a clinic's terms together. "Covered" means it may use AI now. **Coverage through** is the date coverage would reach if no allowance ran out.
- **Grace, exhaustion, lapse.** **Grace** is a short courtesy period (7 days) after a term's end date, with a small capped share of leftover allowance. **Exhaustion** is the allowance being fully used; the term ends at once. **Lapse** is the state after grace with nothing new: AI is off.
- **Suspension.** The operator switching a clinic's AI off, for example for abuse. **Resume** switches it back on.
- **Transfer.** Moving a clinic's remaining paid time to a new platform identity of the *same* clinic.
- **Reversal.** Money taken back from a payment: a **refund**, a **void** (payment cancelled before it settled) or a **chargeback** (the card holder's bank forces it back). A reversal is **full** or partial.
- **Voiding a grant.** Cancelling AI time that a grant created, for example after a reversal or a mistaken gift.
- **Ceiling policy and override.** Limits on how much complimentary time the operator may give, per grant and per clinic over 90 days. An **override** is a separately approved, separately alerted exception.
- **Velocity check.** An alarm on unusually many paid grants in a short time.
- **Subscription reference.** A human-readable id the clinic quotes to support.
- **Payout and reconciliation.** A **payout** is money Paymob transfers to the vendor's bank. **Reconciliation** is the daily cross-check that every payout, payment and grant match.
- **Alert, digest and heartbeat.** An **alert** is an email the developer receives quickly. The **digest** is a daily summary email. A **heartbeat** is a regular "I am alive" ping to an outside monitor; if it stops, the monitor raises the alarm.
- **Notices.** Short coded messages on the desktop, such as "your term ends soon".

### 0.6 Technical words

**Talking over a network**

- **HTTP request and response.** The way programs talk on the web. A request has a **method** (`GET` reads, `POST` creates, `PUT` replaces), a **path** (such as `/v1/offers`), **headers** (labelled lines of extra information, like the envelope's address and stamps) and an optional **body** (the letter inside). `?open=1` or `?cursor=` after a path are **query parameters**, small extra inputs in the address. `{id}` in a path stands for an actual id.
- **HTTP status codes.** A three-digit number on every response, like a coded stamp on the reply. The ones used here: `400` bad request (here: wrong form edition), `401` "who are you?" (no valid badge), `403` "you may not" (badge valid but not allowed), `404` not found, `409` conflict with the current state (such as an offer no longer on sale), `422` a field failed validation, `429` too many requests, `503` a service the request depends on is unavailable.
- **Streamed response.** An answer sent in pieces as it is produced, like AI text appearing word by word.
- **Route, endpoint, hostname.** A **route** or **endpoint** is one path a server answers. A **hostname** is the server's web address, such as `billing.<vendor-domain>`.
- **Rate limit.** A cap on how many requests a caller may make in a period.
- **Service binding.** A private connection from one Cloudflare Worker to another inside Cloudflare, not reachable from the internet. Like an internal pneumatic tube between two offices in the same building.
- **RPC (remote procedure call).** Calling a function that lives in another program as if it were local. The word appears in two places: the ABO calls the AI Platform's functions over the service binding, and the desktop calls the shared backend's database functions (§3.1).
- **`WorkerEntrypoint` and method.** `WorkerEntrypoint` is Cloudflare's way of offering a named set of functions over a service binding. Each function is a **method**. The platform's set is called `VendorEntrypoint`, the counter window the ABO talks to.

**Data formats**

- **JSON.** A plain-text format for structured data: `{"grant_id": "…", "count": 3}`. Keys here are in snake_case.
- **Minor units and piastres.** Money is a whole number of the smallest coin. EGP 150.00 is `15000` piastres, so no rounding ever happens.
- **UTC, ISO-8601.** Times are in world time with no time zones, written as `2026-03-01T10:00:00Z`.
- **E.164.** The international phone number format: a plus sign, the country code and the number, such as `+201001234567` (example).
- **UUID and ULID.** Long random ids that nobody can guess.
- **Hex and base64url.** Two ways of writing binary data as text. **Hex** uses the digits 0-9 and letters a-f. **base64url** is shorter and is safe inside web addresses.
- **Snapshot.** A complete picture of something at one moment, like a photo.

**Proof and protection**

- **Hash (SHA-256).** A short fingerprint computed from data. The same data always gives the same fingerprint; any change gives a different one. **SHA-512** is a longer variant.
- **Canonical JSON (RFC 8785, the JSON Canonicalization Scheme).** One fixed way of writing a JSON object (key order, spacing, number format), so both sides compute the same fingerprint for the same content. RFC 8785 is the public standard that defines it.
- **Signature, key pair, `kid`.** A digital wax seal. Only the holder of a private key can make it; anyone with the matching public key can check it. `kid` (key id) names which seal was used, so keys can be replaced over time (**rotation**). A key is active, **retiring** (still accepted for a while), revoked or expired.
- **Ed25519 and EdDSA.** A modern, fast signature method. EdDSA is the family name; Ed25519 is the specific variant used everywhere here. **ES256** is another signature method, used by some hardware keys.
- **HMAC.** A seal made with a secret shared by both sides. Here it shows that a notification really came from Paymob.
- **JWT and JWS.** A **JWT** (JSON Web Token) is a small signed text badge. **JWS** (JSON Web Signature) is the signing format it uses. A JWT has a **header** (which method and key signed it) and **claims** (the statements on the badge).
- **Token.** A short-lived JWT that the shared backend signs for a desktop, like a visitor badge with an expiry time and a named destination. It is sent in a header `Authorization: Bearer <token>` ("bearer" means whoever carries it is admitted).
- **Cloudflare Access and Access JWT.** **Cloudflare Access** is the login gate in front of the operator console. After login it gives the browser an **Access JWT**, forwarded to the platform in the `Cf-Access-Jwt-Assertion` header and checked against the Access "team certificates" (Cloudflare's public keys for the vendor's account).
- **Passkey, WebAuthn, assertion.** A **passkey** is a hardware security key. **WebAuthn** is the web standard for using it. An **assertion** is the signed proof produced when the operator touches the key, bound to one exact operation (§1.5).
- **Authorization classes M, H and HP.** Each platform method needs one of three levels of proof (02 §3.3): **M** (machine: the ABO over the service binding, plus its signature when coverage changes), **H** (a human operator logged in through Access) or **HP** (human plus passkey: H plus a fresh passkey touch for this exact operation). Like a counter that serves some forms by courier, some only to the owner in person, and some only when the owner also signs in front of a witness.

**Reliable work**

- **Idempotent.** Doing it twice has the same effect as doing it once, like pressing a lift button twice. Every method that changes something names what makes it idempotent ("idempotent by"): the id that lets the receiver recognise a repeat.
- **Content hash and conflict.** A repeat with the same id *and* the same fingerprint is a harmless retry. The same id with a *different* fingerprint is a **conflict**: something is wrong and a human must look.
- **Retry with backoff, park.** **Backoff** means waiting longer between each retry. To **park** a task is to stop retrying it and wait for the operator.
- **Work row.** A to-do card in the ABO for one background step, retried until done (03 §2.9).
- **Saga.** A multi-step job where each step is done and recorded separately, and the whole job is driven to completion step by step, like a relay race where each runner's handover is logged.
- **Cron.** A timer that runs a job on a schedule. A **cron expression** such as `*/5 * * * *` (every 5 minutes) writes the schedule in five fields: minute, hour, day of month, month, day of week.
- **Outbox and alarm.** The DO's out-tray of changes to ship to other systems, and its alarm clock that wakes it at a set time (03 §0.6).
- **Event, sequence number, cursor.** An **event** is a "something changed" notice. Sequence numbers put events in order. A **cursor** is a bookmark: "I have read up to here".
- **Tombstone.** A marker saying "this id is dead", stored even before the thing it kills arrives, so the thing is refused when it shows up.
- **Lineage.** The chain linking a term back to the grant that first created it, even after a transfer (`origin_grant_id`).
- **Mirror, view and TTL cache.** `coverage_mirror` (on the platform) and `coverage_view` (in the ABO) are read-only copies of the DO's coverage. A **TTL cache** keeps a copy for a fixed "time to live" before refreshing it, so it can be slightly out of date.

**Storage**

- **D1, R2 and DO storage.** D1 is Cloudflare's database (SQLite); R2 is its file storage; each DO has its own private SQLite database (03 §0.4).
- **Table, row, append-only, trigger.** A table is a stack of forms of one kind; a row is one filled-in form. **Append-only** rows are added but never changed; a **trigger** is an automatic database rule, used here to block edits. A **fact** is one append-only record of something that happened, such as a payment (03 §2.1).
- **Migration.** A numbered script that changes a database's structure (adds or drops tables or columns). Migrations run in order and, once released, are never edited.
- **Contract version, `contract_version`.** The edition number of a message format (§7).

### 0.7 One purchase, seen as messages

03 §0.7 follows a purchase through the records it writes. This walk-through follows the same purchase through the messages it sends, with the section that defines each one in brackets.

1. **The administrator's desktop gets a billing badge.** It calls the backend's `issue_billing_token` and receives a token for the ABO plus the ABO's address (§3.1, §2.1).
2. **It shows the offers.** It calls `GET /v1/offers` on the ABO with the billing token (§2.2).
3. **It opens a checkout.** It calls `POST /v1/checkouts`. The ABO asks the platform how far coverage already reaches (`getCoverage`, §1.3), asks the Paymob adapter to create the payment session (`createCheckout`, §5.1, §5.3), and answers with a link to Paymob's page and whether the new term starts now or after the current one.
4. **The administrator pays.** Paymob notifies the ABO; the adapter checks the notification's HMAC seal (`parseNotification`) and asks Paymob directly for the real state (`inquire`, §5.1). The ABO confirms the amount, currency and order match (§5.2).
5. **The ABO asks for AI time.** It signs a grant envelope and calls the platform's `grant` method (§1.3, §1.4). The clinic's DO validates it, adds the term and answers `applied` with a signed receipt (§1.2, §1.6).
6. **The ABO learns the new state.** Every minute it reads coverage events from the platform (`readCoverageEvents`, §1.8) and updates its own `coverage_view`.
7. **Desktops see the change.** Every desktop with an AI token reads `GET /v1/capabilities` on the platform and finds `status` with `state = active` (§4.1, §4.2, §4.3). Administrators can also read `GET /v1/coverage` on the platform and `GET /v1/subscription` on the ABO.
8. **The clinic uses AI.** Each `POST /v1/requests` is admitted or refused with a specific denial code, which the desktop shows inline (§4.1, §4.4).

At every step, each message carries its channel's contract version, so a desktop or server that is one version behind still works (§7).

### 0.8 How to read the rest of this document

**Reference codes.** Short codes in brackets point to where a rule comes from or what it satisfies. You do not need to follow them to understand the text.

| Code          | Means                                                     | Defined in                                                                       |
| ------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------- |
| G-n, G5       | Product goal                                              | [Seed](00-abo-requirements-seed.md) §2.1                                         |
| FR-n          | Functional requirement (what the product must do)         | Seed §4                                                                          |
| SR-n          | Security requirement                                      | Seed §5                                                                          |
| NFR-n         | Reliability or operational requirement                    | Seed §6                                                                          |
| RC-n          | Records and retention requirement                         | Seed §7                                                                          |
| C-n           | Constraint or given fact                                  | Seed §8.1                                                                        |
| P-n           | A gap in today's AI Platform code                         | Seed §8.2                                                                        |
| A-n, An       | Acceptance scenario that must pass before launch (written both "A-22" and "A22") | Seed §11                                                  |
| X-n           | A future expansion, and the "seam" kept open for it       | Seed §2.3 and 01 §5                                                              |
| T-n, I-n, R-n | Code fact, approved interpretation of the seed, risk or spike (an experiment still to run) | [Decision memo](01-abo-design-decisions.md) §2, §4, §7 |
| AD-n, K-n     | Adversary, credential                                     | [Architecture and threat model](02-abo-architecture-and-threat-model.md) §4.2, §3.1 |
| AL-n, FM-n    | Alert, failure mode                                       | [Operations](05-abo-operations-and-traceability.md) §2, §4                       |

"01 §n" means section n of the [decision memo](01-abo-design-decisions.md); "02 §n" the [architecture and threat model](02-abo-architecture-and-threat-model.md); "03 §n" the [data model](03-abo-data-model-and-lifecycle.md); "05 §n" the [operations document](05-abo-operations-and-traceability.md). A bare "§n" means a section of this document.

**Code references.** A path such as `src/worker.ts:1605-1626` means lines 1605 to 1626 of that file in today's code. A bare `:124` means line 124 of the file named just before it. These are pointers for engineers; you can skip them.

**Field lists.** Field and value names are written in `code font`, exactly as they appear on the wire. A `?` after a field name (such as `receipt?`) means the field is optional. `{a, b}` describes an object with fields `a` and `b`; `x[]` means a list of `x`.

**Order of reading.** Sections 1 to 5 each describe one channel (§0.3). Section 1 is the most detailed, because it carries every change to a clinic's AI time. Sections 3.2 and 6 are the change lists for engineers. Section 7 explains the versioning rules every channel follows; if version numbers puzzle you in earlier sections, read §7 first.

## 1. ABO and AI Platform

**Purpose.** This is the most important channel: the shop talking to the network. Every change to a clinic's AI time (adding a term, voiding one, suspending a clinic, moving time to a new identity) travels here as a request from the ABO, or from the operator through the ABO's console, to the AI Platform. The platform checks every request itself and answers with a standard reply slip. Sections 1.1 to 1.3 describe the connection, the reply slip and the menu of methods; sections 1.4 to 1.8 describe the main forms: the grant envelope, the operator's approval, the receipt, the coverage snapshot and the coverage events.

### 1.1 Transport and versioning

**What this is.** How the shop's messages physically reach the network, how both sides know which edition of a form they hold, and how signed forms are written so both sides compute the same fingerprint.

- **Transport.** "Transport" means the kind of connection a message travels over. Here it is a service binding (a private tube inside Cloudflare, §0.6) from the ABO to the platform's named `WorkerEntrypoint` class `VendorEntrypoint`, using RPC methods (functions the ABO calls as if they were its own). It is not reachable from the internet. The platform never calls the ABO (01 §3.7).
- **Versioning (X-10, NFR-09).** Every argument object (the inputs of a method call) and every result carries `contract_version`. The platform accepts the current version N and the previous one N−1, and answers `rejected` with code `contract_version_unsupported` otherwise. Tokens carry their own version claim `ver`, checked against the existing `token_contract` table. The rules for every channel are in §7.
- **Canonical form.** Signed and hashed objects use the JSON Canonicalization Scheme (RFC 8785): one fixed way of writing the JSON, so both sides produce identical bytes. Signatures are Ed25519 over those canonical bytes. Hashes are SHA-256, written in hex.

### 1.2 Result envelope

**What this is.** The standard reply slip. Every method on the platform answers with the same five boxes, so the ABO always knows what happened and what to do next without reading free text. Think of a reply slip with one tick-box per outcome, a reason code, a note, and sometimes a signed delivery note attached.

Every method returns `{contract_version, result, code, detail, receipt?}`:

- `contract_version`: the form edition the answer is written in.
- `result`: the ticked outcome, one of the six values in the table below.
- `code`: for a refusal, the specific reason (for example `bad_signature`).
- `detail`: extra information; for `transient`, it says which temporary condition applies.
- `receipt?`: the signed receipt (§1.6), present only when something was applied.

How to read the table: **`result`** is the tick-box value; **Meaning** says what the platform is reporting; **ABO action** is what the ABO must do on receiving it. Three of the outcomes need explaining first:

- **`already_applied`** is the platform recognising a repeat: the same id with the same content fingerprint (hash) was applied before, so it returns the original receipt instead of doing the work twice. This is what makes retries safe (NFR-03).
- **`conflict`** is the same id arriving with *different* content. That should never happen, so the ABO parks it (stops retrying and waits for the operator) and alerts.
- **`transient`** means "not now, try later": nothing was changed, and the condition is expected to clear. `detail` names it: `unavailable` (storage or the DO is down), `unknown_kid` (a newly registered signing key is not visible yet), `awaiting_transfer` (the clinic's new DO is waiting for its time to be moved in) or `transfer_pending` (an identity is held until a transfer runs). The ABO retries with backoff forever (NFR-01).


| `result`          | Meaning                                                                                  | ABO action                                         |
| ----------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `ok`              | Read succeeded                                                                           | —                                                  |
| `applied`         | Change made now; `receipt` present                                                       | Record outcome; work done                          |
| `already_applied` | Same id with the same content hash was applied before; the original `receipt` is returned | Record outcome; work done (NFR-03)                 |
| `conflict`        | Same id with a different content hash                                                    | Park and alert; never retried automatically        |
| `rejected`        | Validation failed (`code` says why); retrying cannot help                                 | Park and alert                                     |
| `transient`       | Storage or DO unavailable, or a state that will clear (`detail` says which: `unavailable`, `unknown_kid`, `awaiting_transfer`, `transfer_pending`); nothing was changed | Retry with backoff forever (NFR-01)                |


### 1.3 Method catalogue

**What this is.** The menu of counter services the platform offers the ABO, and which ID each one needs. Each row is one method of `VendorEntrypoint`.

**The three ID levels.** The classes (M, H, HP) are defined in 02 §3.3 and summarised in §0.6:

- **M (machine).** The ABO itself, over the service binding. Methods that change coverage also need the ABO's signature.
- **H (human).** The operator, logged in through Cloudflare Access. Each H method takes `access_jwt` (the operator's Access login badge).
- **HP (human plus passkey).** An H operator who also touches a hardware key for this exact operation. Each HP method takes `access_jwt` and also `assertion` (the signed passkey proof, §1.5).

**How to read the table.**

- **Method**: the method name the ABO calls.
- **Class**: M, H or HP. "HP, or bootstrap" means the very first operator credential can be registered without an approving assertion, because there is no one yet to approve it.
- **Input (beyond `contract_version`)**: what the request must contain, apart from the version every request carries.
- **Output**: what comes back inside the result envelope (§1.2).
- **Idempotent by**: what lets the platform recognise a repeat and return the first answer instead of acting twice (§0.6). "Target state" means the method only sets a state (such as "suspended"), so repeating it changes nothing. "Assertion challenge" means the passkey proof is single-use (§1.5), so the same approval cannot run twice. "—" means a pure read, which is harmless to repeat.

**Words used in the table.**

- A **tombstone** is a "this id is dead" marker stored before the grant arrives (§0.6).
- A **live term** is the term that currently carries a grant's time; after a transfer it is found through `origin_grant_id` (lineage, §0.6).
- The **grant ledger** is the platform's list of all grants. A **reservation** is credits set aside for an AI request in progress.
- A **package** is the bundle of terms a `transferOut` hands to `transferIn`.
- **Kill switch**, **routing policy**, **cohort**, **capability lifecycle** and **token contract** are existing platform controls: switching a feature off for everyone, choosing which AI provider serves a request, grouping clinics, moving a capability through its release stages, and the list of accepted token versions. They keep working as today.
- **Retention** is how long records are kept.
- Three kinds of key appear: **issuer keys** (the shared backend's token-signing keys), **service keys** (the ABO's grant-signing keys, registered on the platform) and **operator credentials** (the operator's passkeys). **Pinned** keys are public keys written into the ABO's own configuration (`ISSUER_KEYS`), so the ABO never has to trust a key list fetched from elsewhere.
- A **WebAuthn attestation** is the proof a new passkey gives when it is first registered (the passkey's "birth certificate"), as opposed to an assertion, which it gives each time it is used. `pending` means a new operator credential exists but cannot be used until its 24-hour waiting period has passed.
- An **isolate** is one running copy of a Worker; "at isolate start" means whenever a fresh copy starts up.

**Groups of methods.** The rows fall into five groups, which helps when scanning:

- **Grants and voids:** `grant` (all three sources and `term_adjustment`), `voidForReversal`, `releaseHeld`, `voidGrant`, `listGrantsForVoid`.
- **Reading coverage:** `getCoverage`, `readCoverageEvents`, `listGrants`, `inspectCoverage`, `supportLookup`.
- **Keys and credentials:** `listIssuerKeys`, `listOperatorCredentials`, `listServiceKeys`, and the register and revoke methods.
- **Clinic identity and transfers:** `transferOut`, `transferIn`, `beginTransfer`, `suspend`, `resume`, `deleteInstallation`.
- **Catalogue and policy:** `publishPlanVersion`, `retirePlanVersion`, `setCeilingPolicy`, and the existing controls (kill switch and the others).


| Method                                         | Class | Input (beyond `contract_version`)                                          | Output                                    | Idempotent by                   |
| ---------------------------------------------- | ----- | -------------------------------------------------------------------------- | ----------------------------------------- | ------------------------------- |
| `grant`                                        | By `source.kind`: `paid` M, `complimentary` HP | Grant envelope (§1.4); `abo_kid` and `abo_signature` for `paid`; `assertion` for `complimentary` | Receipt | `grant_id` plus `envelope_sha256` |
| `voidForReversal`                              | M     | `grant_id` (the paid grant), `reversal_id`, `reason`, `evidence_sha256`, `abo_kid`, `abo_signature` | Receipt. Resolves the live term through `origin_grant_id` (03 §5.5); if the grant is not yet applied, stores a tombstone | `reversal_id` |
| `getCoverage`                                  | M     | `org_id`                                                                   | Snapshot (§1.7), queued and recent terms  | —                               |
| `readCoverageEvents`                           | M     | `after`, `limit` ≤ 200                                                     | Coverage events (§1.8), unsigned          | —                               |
| `listGrants`                                   | M     | Filter: `org_id`, `source_kind`, `credential_id`, time window              | Grant ledger rows                         | —                               |
| `listIssuerKeys`                               | M     | —                                                                          | Active and retiring issuer public keys. The ABO compares them with its pinned `ISSUER_KEYS` hourly and alerts on any difference (§2.2) | — |
| `listOperatorCredentials`                      | M     | —                                                                          | Active operator public keys, so the ABO can verify assertions for its own HP actions (05 §3.2) | — |
| `listServiceKeys`                              | M     | —                                                                          | `kid`, status and validity of each registered ABO service key. The ABO checks at isolate start and hourly that its signing `kid` is active; if not, it pauses `grant` and `reverse` work and raises AL-23 (02 §6) | — |
| `transferOut`, `transferIn`                    | M     | `transfer_id` (an authorised `transfer` row must exist)                    | Package; receipt                          | `transfer_id`                   |
| `suspend`, `resume`                            | H     | `org_id`, `reason`                                                         | Snapshot                                  | Target state                    |
| `inspectCoverage`                              | H     | `org_id`                                                                   | Full DO ledger: terms, grants, reservations | —                             |
| `supportLookup`                                | H     | Request `reference`                                                        | Existing lookup (`ai-platform/src/support/index.ts`); envelope within retention | —             |
| Kill switch, routing policy, cohort, capability lifecycle, token contract | H | As today (`src/control/index.ts:146-211`)                           | As today                                  | As today                        |
| `grant` with `kind = term_adjustment`          | HP    | Envelope with `adjustment` fields                                          | Receipt                                   | `grant_id`                      |
| `beginTransfer`                                | HP    | `org_id`, `from_installation_id` (the org's `active` or `held_for_transfer` binding), `reason`. Same org only | `transfer_id`. Atomically retires the source binding and creates the org's new active binding with the next epoch; the new DO starts `awaiting_transfer` (03 §5.4) | Assertion challenge |
| `releaseHeld`, `voidGrant`                     | HP    | `grant_id`, `reason`                                                       | Receipt                                   | Assertion challenge             |
| `listGrantsForVoid`                            | H     | `credential_id`, window                                                    | Grants, for SR-25                         | —                               |
| `publishPlanVersion`, `retirePlanVersion`      | HP    | Plan version fields (03 §3.2)                                              | Plan version                              | `(plan_id, version)`            |
| `setCeilingPolicy`                             | HP    | Ceiling fields                                                             | Policy version                            | Assertion challenge             |
| `registerIssuerKey`, `revokeIssuerKey`, `registerServiceKey`, `revokeServiceKey` | HP | `kid`, `public_key`, validity                        | Key row                                   | `kid`                           |
| `registerOperatorCredential`                   | HP, or bootstrap | WebAuthn attestation; approving assertion (none only while the table is empty) | Credential, `pending` for 24 hours | `credential_id`             |
| `revokeOperatorCredential`                     | HP    | `credential_id`                                                            | Credential                                | Target state                    |
| `deleteInstallation`                           | HP    | `org_id`, `reason`                                                         | Installation marked `deleted`. With no coverage left, its binding is retired and the org's next token or grant creates a new binding with the next epoch. With coverage left, the binding becomes `held_for_transfer` and AL-18 fires: AI tokens get `coverage_lapsed` (`coverage_reason = transfer_pending`), grants get `transient` (`detail = transfer_pending`), and no new binding is created until `beginTransfer` moves the time, or the remaining grants are voided, which retires the binding (03 §5.4, A24) | Target state |


**What goes away.** Today the platform is controlled through public HTTP routes under `/control/*`, protected by one shared secret token (`OPERATOR_BEARER_TOKEN`, §6.1). All of them are removed, together with the handlers `handleEntitle`, `handleOverride`, `handleEnroll`, `handleRotate`, `handleRevokeKey`, `handlePlanCreate`/`Update`/`Delete` and `handleCreditPriceActivate` (FR-91). The methods above replace them.

**How a transfer runs.** A transfer runs as a saga (a multi-step job driven to completion step by step, §0.6) driven by an ABO work row:

1. `beginTransfer` (HP) records the operator's authorisation.
2. `transferOut` and `transferIn` (M) are then retried until both report `applied` or `already_applied`.

### 1.4 Grant envelope and validation

**What this is.** The grant envelope is the sealed order form "add this AI time to this clinic". The ABO (for a paid grant) or the operator (for a gift) fills it in and seals it with a signature or a passkey approval. The platform then checks it in a fixed order before the clinic's DO adds the time. Because the form is sealed over its canonical bytes, changing any box after sealing breaks the seal.

**The boxes on the form, in plain words.** The table below is the exact specification; this list explains each field first.

- `contract_version`: the form edition.
- `grant_id`: the grant's unique id, a SHA-256 fingerprint written in hex and built by the rule in 03 §7. For a paid grant it is derived from the payment, so the same payment can never produce two grants.
- `org_id`: the clinic, as a tenant UUID. The platform looks up the clinic's active binding, or creates one if none exists.
- `kind`: `term` (a new block of AI time) or `term_adjustment` (a change to the current term, X-07).
- `placement`: where the new term goes. At launch only `queue` is accepted; `immediate` (start now, cutting the current term short) and `replace` (swap the current term) are refused with `placement_not_supported` (X-06). An upgrade during a term (FR-32) is done with `term_adjustment` instead.
- `source`: where the grant comes from. `kind` is `paid`, `complimentary` or `transfer`; `ref` is the ABO's own reference (its `payment_id`, the operator action id or the `transfer_id`), never Paymob's id (SR-10). `operator_email` and `reason` say who gave it and why; they are required for everything except `paid` (FR-36).
- `plan`: which plan version the term gives. The platform takes its own snapshot (frozen copy) of that published version, rather than trusting a copy in the form.
- `duration`: how long, as a unit and a count. Paid grants are 1, 3 or 12 months. Gifts may be in months or days (03 §6.1).
- `allowance_credits`: how many credits the term includes, at least 1.
- `grace`: the grace days and the rule capping grace usage. For paid grants, at most `max_paid_grace_days` (7) and the `proportional` rule.
- `adjustment`: for a term adjustment, what changes: a new plan, extra allowance, extra days, or any of these.
- `paid_at`: for paid grants, when Paymob says the payment happened.
- `evidence`: a fingerprint of the proof behind the grant (`content_sha256`; for paid grants, the ABO payment fact and its evidence) and the operator approvals (`approvals[]`; the policy minimum is one, X-09).
- `ceiling_override`: an optional exception to the gift limits. It needs a second, separate operator approval and raises its own alert (SR-24).

| Field                  | Type and rule                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `contract_version`     | Integer                                                                                                                  |
| `grant_id`             | Hex SHA-256 per 03 §7                                                                                                    |
| `org_id`               | Tenant UUID; the platform resolves or creates the active binding                                                         |
| `kind`                 | `term` or `term_adjustment` (X-07)                                                                                       |
| `placement`            | `queue` only at launch; `immediate` and `replace` are rejected (`placement_not_supported`, X-06). FR-32 upgrades use `term_adjustment` |
| `source`               | `{kind: paid, complimentary or transfer, ref, operator_email, reason}`. `operator_email` and `reason` are required unless `kind = paid` (FR-36). `ref` is the ABO's `payment_id`, operator action id or `transfer_id`; never a provider id (SR-10) |
| `plan`                 | `{plan_id, plan_version}`; the platform snapshots the published version itself                                           |
| `duration`             | `{unit, count}`. `paid`: `month` with count 1, 3 or 12. `complimentary`: `month` or `day` (03 §6.1)                        |
| `allowance_credits`    | Integer ≥ 1                                                                                                              |
| `grace`                | `{days, cap_rule}`. `paid`: `days` ≤ `max_paid_grace_days` (7) and `cap_rule = proportional`                               |
| `adjustment`           | For `term_adjustment`: `{plan?, add_allowance?, extend_days?}`                                                           |
| `paid_at`              | For `paid`: the provider's payment time                                                                                  |
| `evidence`             | `{content_sha256, approvals[]}`. For `paid`, the hash of the ABO payment fact and its evidence. `approvals` holds operator assertions; the policy minimum is 1 (X-09) |
| `ceiling_override`     | Optional; needs a second, separate assertion and is separately alerted (SR-24)                                          |


**How the platform checks the form.** Like a clerk working down a checklist, the platform runs these checks in order and stops at the first failure, answering `rejected` with the named code (or `transient` where stated):

1. **Edition and seal match.** `contract_version` is supported, and the envelope's canonical hash matches the hash that was signed or approved (`bad_signature`, `bad_assertion`).
2. **The right authority sealed it.**
   - Paid: the ABO signature verifies against the named `service_key`. An unknown `kid` answers `transient` with `detail = unknown_kid`, because a newly registered key may still be propagating (spreading to every copy of the platform); if it persists, the ABO's own check raises AL-23. A revoked or expired `kid` answers `rejected` (`bad_signature`).
   - Complimentary: the operator assertion verifies (§1.5).
   - Transfer: the `transfer` row is authorised.
3. **The order is within the plan's limits.** The plan version is published (`plan_not_published`). The source, unit and count are allowed (`unit_not_allowed`, per the `duration` row). For `paid`, `allowance_credits` ≤ `max_allowance_per_month` × months, and grace follows the `grace` row (`exceeds_plan_bound`). This bounds what a compromised ABO can fabricate (02 AD-8): even a forged paid grant can only be as large as a real one.
4. **Gifts are within the ceiling.** For complimentary grants: the grant is within the ceiling policy, both per grant and per clinic over a 90-day window, counting earlier complimentary grants and `term_adjustment` additions (03 §3.2), unless a valid override is attached (`exceeds_ceiling`).
5. **The grant is not dead and the clinic is not moving.** The `grant_id` has no void tombstone (`voided`). The clinic's DO has not transferred out (`transferred_out`). A DO still `awaiting_transfer`, or an org whose binding is `held_for_transfer`, answers `transient` to any non-transfer grant.

**What happens on success.**

- The DO applies the grant atomically (all of it or none of it), stores the envelope and evidence, and through its outbox emits the ledger mirror, the coverage event and the out-of-band alert (an alert sent outside the normal message channels, by email to the developer, 02 §5) (01 §3.5).
- Every grant alerts, paid ones included (AL-11). Complimentary grants, overrides and transfers are marked for attention.
- Paid grants also feed a velocity check: more than 3 paid grants for one clinic in 24 hours, or more than 20 across all clinics in an hour, raises a platform alert.

### 1.5 Operator assertion

**What this is.** The operator's signature in front of a witness, for one specific form. Before any HP method runs, the operator touches their passkey, and the passkey signs a fingerprint of the *exact* operation (which method, which inputs, who, when). The platform checks that proof itself, so nobody can reuse it for a different operation or replay it later.

**How it flows.** The ABO console runs the WebAuthn `get` ceremony (the browser's standard "touch your security key" step) and forwards the result. The platform verifies it; the ABO's own check is only for UX (user experience: showing a friendly error early).

**The rules, element by element.** Words used:

- The **operation object** is the description of what is being approved: `op` (the method), `params` (its exact inputs, without the assertion itself), `actor_email` (who), `issued_at` (when), `nonce` (a random one-time value so two identical operations still get different proofs) and `contract_version`.
- The **challenge** is the value the passkey signs: the SHA-256 fingerprint of the canonical operation object, written in base64url.
- The **relying party** is the website the passkey is registered to. `rpId` is its hostname. `clientDataJSON` is the small record the browser adds, stating which page (`origin`) asked and which ceremony (`type`) ran. This stops a look-alike website from collecting a valid touch.
- **Flags**: *user presence* means someone physically touched the key; *user verification* means they also proved it is them (a PIN or fingerprint on the key).
- **Credential**: the passkey must be `active` in the `operator_credential` table, which means its 24-hour activation delay has passed. Two signature methods are accepted: ES256 (whose DER signature, one standard packing of the signature bytes, is converted to the raw packing before checking) or EdDSA (01 R-5).
- **Freshness and reuse**: the proof must be recent, and each challenge can be used once. Used challenges are recorded in the `assertion_used` table.
- **Actor**: the person in the proof must be the person logged in through Access for the same call.


| Element            | Rule                                                                                                                                                  |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Operation object   | `{op, params, actor_email, issued_at, nonce, contract_version}`; `params` is the exact method input, without the assertion                            |
| Challenge          | base64url(SHA-256(canonical operation object))                                                                                                        |
| Relying party      | `rpId` is the console hostname; `clientDataJSON.origin` must equal `https://ops.<vendor-domain>`; `type` is `webauthn.get`                            |
| Flags              | User presence and user verification both set                                                                                                          |
| Credential         | `active` in `operator_credential` (its 24-hour activation delay has passed); algorithm ES256 (DER signature converted to raw) or EdDSA (01 R-5)      |
| Freshness and reuse | `issued_at` within 5 minutes of now; the challenge hash is inserted into `assertion_used` and must not already be there                             |
| Actor              | `actor_email` equals the email in the Access JWT verified for the same call                                                                           |


### 1.6 Receipt

**What this is.** The network's signed delivery note. Whenever a grant or void is applied, the platform answers with a receipt that says exactly what it did, sealed with the platform's own key. The ABO keeps it as proof, and the platform keeps a copy too.

The receipt's fields are `{contract_version, grant_id or reversal_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`. In plain words:

- `contract_version`: the form edition.
- `grant_id` or `reversal_id`: which request this receipt answers (a grant, or a void after a reversal).
- `installation_id`, `org_id`: which clinic identity and which clinic.
- `result`: the outcome (§1.2).
- `term_ids`: the terms created or changed.
- `applied_at`: when it was applied.
- `ledger_seq`: its position number in the platform's grant ledger.
- `envelope_sha256`: the fingerprint of the envelope it applied, so the receipt is tied to that exact form.
- `kid`, `signature`: which platform key sealed it, and the seal.

**Rules.**

- The signature is by the platform key (02 K-3) over the canonical receipt without the signature.
- Both sides store it (SR-05).

### 1.7 Coverage snapshot

**What this is.** A photo of one clinic's AI coverage at one moment: which state it is in, the current term's dates and usage, and how many terms wait in the queue. It is the one shape used everywhere coverage is shown or copied. It is used by `getCoverage`, coverage events (§1.8), `coverage_mirror` and the ABO's `coverage_view`. Desktop status (§4.2) is computed from it.

**The fields in plain words.**

- `contract_version`: the edition of the snapshot's shape. Every stored copy keeps it, so an old copy is always read by the rules it was written with.
- `state`: the clinic's coverage state as defined in 03 §5.7 (for example `active`, `grace`, `lapsed`).
- `reason`: for a state where AI is not available, why: `none` (never had a term), `expired`, `grace_exhausted` (grace allowance used up), `exhausted` (allowance used up), `reversed` (money taken back), `transferred` (time moved to a new identity) or `transfer_pending`.
- `suspended`: whether the operator has suspended the clinic.
- `term`: the current term, or null. `ref` is its reference; `plan_display_name` its plan's display name; `starts_at`, `ends_at` and `grace_ends_at` its dates; `allowance` and `used` its credits; `band` the usage band (`ok`, `75`, `90` or `exhausted`).
- `queued_count`, `held_count`: how many terms wait in the queue, and how many are held (01 I-3).
- `coverage_through`: how far coverage reaches if no allowance runs out. The ABO reads it live through `getCoverage` to classify duplicate payments, with `coverage_view` as the fallback (03 §2.4).
- `binding_epoch`, `clinic_seq`: the ordering key. A newer snapshot always has a larger pair, so copies never go backwards (03 §2.10).


| Field          | Content                                                                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `contract_version` | Version of the snapshot shape. Every stored copy (`coverage_mirror`, `coverage_view`) keeps it, so old rows are read by the rules they were written with |
| `state`        | 03 §5.7                                                                                                                                           |
| `reason`       | For non-available states: `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, `transfer_pending`                        |
| `suspended`    | Boolean                                                                                                                                           |
| `term`         | Null, or `{ref, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, band}`, where `band` is `ok`, `75`, `90` or `exhausted`    |
| `queued_count` | Unheld queued terms                                                                                                                               |
| `held_count`   | Held terms (01 I-3)                                                                                                                               |
| `coverage_through` | Projected end of coverage assuming no exhaustion; read live by `getCoverage` for duplicate classification, with `coverage_view` as the fallback (03 §2.4) |
| `binding_epoch`, `clinic_seq` | Ordering key; consumers apply a snapshot only if this pair is greater than the stored one (03 §2.10)                                 |


There are no prices, payment references or provider ids in the snapshot (FR-53, SR-10). That is why every role, staff included, may see what is computed from it.

### 1.8 Coverage events

**What this is.** A numbered stream of change notices from the network to the shop. Each time a clinic's coverage changes, the platform records an event containing the new snapshot. The ABO reads the stream every minute, in order, like reading a numbered noticeboard and keeping a bookmark of the last notice read.

**The page the ABO receives.** `readCoverageEvents` returns `{contract_version, after, events[], next_after, has_more}`:

- `after`: the bookmark the ABO asked to read after.
- `events[]`: the events on this page.
- `next_after`: the bookmark to use for the next page.
- `has_more`: whether more events are waiting.

**One event.** Each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}` (§1.7). `event_id` is its id; `feed_seq` its position across all clinics; `org_id` and `installation_id` the clinic; `binding_epoch` and `clinic_seq` the per-clinic ordering key; `kind` what changed; `at` when; `snapshot` the new coverage photo.

**Rules.**

- The ABO is the only consumer.
- Its minute cron reads from its `feed_cursor` (its stored bookmark) and applies each event to `coverage_view` by the ordering rule (03 §2.10).
- It requires `after` to equal the stored cursor and `feed_seq` to ascend, and on any failure it keeps the cursor, so nothing is skipped.
- Events are not signed: they travel over the service binding, and `coverage_view` serves only the console, reconciliation and the checkout fallback (03 §2.4).
- There is no HTTP feed route; the shared backend reads nothing from the platform (C-02).

## 2. Tokens and ABO clinic API

**Purpose.** This section covers how a desktop proves who it is, and what it may ask the shop. The ID office (the shared backend) issues short-lived visitor badges (tokens); the desktop shows a badge to the shop (the ABO) or to the network (the AI Platform). Section 2.1 defines what is written on each badge; sections 2.2 and 2.3 define the shop's counter for clinics: its routes, rules and refusal reasons.

**Why badges.** The backend never calls the ABO or the AI Platform, and neither calls it (C-02). Its only part in these channels is the token it mints (signs and issues) for a desktop:

- a **billing token** for the ABO, carried by the administrator desktop;
- an **AI token** for the platform (§4).

That keeps each channel limited to its purpose and bound to the caller (SR-09). A billing badge only opens the shop's door, and an AI badge only opens the network's.

### 2.1 Token claims

**What this is.** The text printed on each badge. Every badge is a JWT (§0.6) signed by the backend's issuer key. Its **claims** are the statements on it. The claim names are short standard abbreviations:

- `iss` (issuer): who issued the badge, here the backend's issuer id.
- `aud` (audience): which service the badge is for. A service refuses a badge addressed to another.
- `sub` (subject): who the badge holder is, the staff member id.
- `org`: which clinic (tenant) they act for.
- `role`: their membership role.
- `branch`: their current branch.
- `scopes`: the AI permissions they hold.
- `iat` (issued at) and `exp` (expires): when the badge was made and when it stops working. `exp − iat` is its lifetime.
- `jti` (JWT id): a unique id for this one badge, used for tracing.
- `ver`: the badge format's version.

The **header** says how the badge is sealed: `alg` (the signature method), `kid` (which issuer key) and `typ` (the kind of token).

**Rules that apply to all tokens.**

- Header `{alg: EdDSA, kid, typ: JWT}`.
- `iss` = the backend issuer id from `ai.issuer_id`.
- `ver = "2"`.
- `org` always comes from `current_org_id()` (the backend function that returns the signed-in user's own clinic), never from an argument (SR-03). A user cannot ask for a badge for someone else's clinic.

How to read the table: each row is a claim; the two columns give its value on the AI token and on the billing token.


| Claim    | AI token                                   | Billing token                   |
| -------- | ------------------------------------------ | ------------------------------- |
| `aud`    | `ai-platform`                              | `abo`                           |
| `sub`    | Staff member id                            | Staff member id                 |
| `org`    | Tenant id                                  | Tenant id                       |
| `role`   | Membership role                            | `administrator`                 |
| `branch` | Current branch                             | Current branch                  |
| `scopes` | `ai.*` permissions, as today (`backend/supabase/migrations/20260905120300_fix_aat_lifetime_fallback.sql:115-124`). Empty for an administrator with no AI scope: that token reads status and `/v1/coverage` but runs no AI | Absent |
| `exp − iat` | ≤ 600 s                                 | ≤ 300 s                         |
| `jti`    | UUID                                       | UUID                            |


**How the platform checks an AI badge.** Today each clinic's installation signs its own tokens, and the platform treats `iss` as the installation id (`ai-platform/src/identity/index.ts:146-148,298`). That is replaced. Now:

1. The platform checks `kid` in `issuer_key` (the key must be active or retiring, and within its validity dates).
2. It checks `iss`, `aud`, the lifetime and clock skew (a small allowance for clocks that disagree slightly; as today, `:283-296`), and `ver`.
3. It then resolves `org` through `tenant_binding` to find the clinic's installation.
4. The first valid token for an unknown `org` creates an installation and binding.

**Limit on new clinics.** Creation is capped at 50 per day across all tenants, and the platform alerts above that cap. This bounds junk from a leaked issuer key: someone who stole the key could otherwise create endless fake clinics.

### 2.2 ABO clinic API

**What this is.** The shop's counter for clinics. An **API** (application programming interface) is the set of requests one program accepts from another. This one is used only by the administrator's desktop, to see offers, keep the billing contact up to date, pay, and see the subscription and payment history.

**How every call is made.**

- Hostname `billing.<vendor-domain>`.
- Every call sends `Authorization: Bearer <billing token>` and the `Abo-Contract-Version` header (the form edition).
- Every response, errors included, carries the same header and a `contract_version` body field (§7).
- The ABO verifies the token against the issuer public keys pinned in its own configuration (`ISSUER_KEYS`, 02 §6), never against keys fetched from the platform, and re-checks `role` (FR-10).

**How to read the table.** **Method and path** is the request; **Request** lists the fields the desktop sends (— means none); **Response** lists what comes back. Words used in it:

- `client_request_id`: an id the desktop invents for each attempt, so a resend after a network failure is recognised and not acted on twice.
- `localized copy`: the offer's name and summary in each language.
- `not_found`: the error code for "nothing there" (§2.3).
- `starts`: whether a new term begins `now` or `after_current`, with `projected_start` as the expected date.
- **Shown state**: the checkout state as the desktop displays it (03 §5.1).
- `classification`: how the payment was classified when confirmed (03 §2.6 lists `normal`, `likely_duplicate` and `late`).
- **Commercial notices**: short codes about money matters: `duplicate_payment` (the clinic appears to have paid twice), `late_payment_honoured` (a payment made on a checkout that had already expired or been cancelled, still turned into AI time), `payment_withheld` (a payment that did not match its checkout was recorded but not turned into time until the operator decides), `reversal_recorded` (money was taken back), `terms_held` (terms are frozen after a reversal, waiting for the operator).
- `cursor=`: a bookmark for paging through long lists.


| Method and path             | Request                                                             | Response                                                                                                                                                                                                                                      |
| --------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /v1/offers`            | —                                                                   | `offers[]`: `offer_id`, `version`, `plan_display_name`, `term_unit`, `term_count`, `price_minor`, `currency`, `allowance_credits`, `grace_days`, localized `copy`; `terms`: `version` and text (FR-05, FR-17)                                     |
| `GET /v1/billing-contact`   | —                                                                   | `version`, `name`, `email`, `phone`, or `not_found`                                                                                                                                                                                           |
| `PUT /v1/billing-contact`   | `client_request_id`, `name`, `email`, `phone` (E.164)               | New version (FR-51)                                                                                                                                                                                                                           |
| `POST /v1/checkouts`        | `client_request_id`, `offer_id`, `offer_version`, `terms_version`   | `checkout_id`, `reference`, `redirect_url`, `expires_at`, `starts` (`now` or `after_current`, with `projected_start`). The admin sees before paying whether the term queues (FR-30, FR-31, A30). `starts` comes from a live `getCoverage`; if that fails, from `coverage_view`, and the checkout is still created (03 §2.4) |
| `GET /v1/checkouts/{id}`    | —                                                                   | `reference`, shown state (03 §5.1), offer summary, `payment_reference`, `term_ref`, `updated_at` (FR-14)                                                                                                                                      |
| `GET /v1/checkouts?open=1`  | —                                                                   | This tenant's open and recently paid checkouts, so any desktop can resume (FR-14, A2, A12)                                                                                                                                                    |
| `GET /v1/subscription`      | —                                                                   | `subscription_ref`, the snapshot (§1.7), and commercial notices: `duplicate_payment`, `late_payment_honoured`, `payment_withheld`, `reversal_recorded`, `terms_held` (FR-41, FR-43)                                                           |
| `GET /v1/payments?cursor=`  | —                                                                   | Pages of `reference`, `paid_at`, `amount_minor`, `currency`, offer name and version, term covered, `classification`, reversals (FR-50, FR-60)                                                                                                 |


**Rules.**

- **Only your own clinic.** The tenant is the token's `org` only. An id belonging to another tenant answers `not_found` (SR-04, A22, A36), so a caller cannot even learn that the id exists.
- **Safe resends.** `POST` and `PUT` are idempotent by `client_request_id` per tenant (NFR-02).
- **Before a checkout.** A new checkout needs a billing contact and the current terms version. `offer_version` must be the current sellable version, so a price change between viewing and opening is shown before paying (A8).
- **Limits.** 10 checkouts per tenant per hour and 60 requests per token.
- **Traceability.** The token's `jti` is stored on the checkout and payment facts for traceability, so every purchase can be traced to the exact badge used.

### 2.3 ABO errors

**What this is.** The shop's refusal slip. Every error has a fixed `code` (the specific reason ticked), an HTTP status (the coarse category, §0.6) and a `message` (a short human-readable explanation).

Body `{code, message, contract_version}`.

How to read the table: **Code** is the value of `code`; **HTTP** is the status number; **When** is the situation that produces it.


| Code                           | HTTP | When                                                                  |
| ------------------------------ | ---- | --------------------------------------------------------------------- |
| `unauthenticated`              | 401  | Token missing, invalid, expired or wrong audience                     |
| `forbidden_role`               | 403  | `role` is not `administrator`                                         |
| `not_found`                    | 404  | Unknown id, or an id of another tenant                                |
| `offer_unavailable`            | 409  | Offer retired or version superseded; the body includes the current version (FR-06, A21, A33) |
| `billing_contact_required`     | 409  | No billing contact yet                                                |
| `terms_not_accepted`           | 409  | `terms_version` is not current                                        |
| `invalid_request`              | 422  | Field validation failed                                               |
| `rate_limited`                 | 429  | Limits in §2.2                                                        |
| `provider_unavailable`         | 503  | The provider refused or timed out when creating the checkout          |
| `contract_version_unsupported` | 400  | `Abo-Contract-Version` missing or outside N and N−1; the body lists the accepted versions. Checked before authentication, so an outdated desktop gets this and not `unauthenticated` |


The operator console's `/ops/*` calls (the back-office counter) follow the same header and error rules.

## 3. Flutter and shared backend

**Purpose.** This is the desktop (written in Flutter, Google's app framework) talking to the ID office. The desktop asks the shared backend for badges and for the AI Platform's address, and nothing else. The backend signs and returns; it never phones anyone.

### 3.1 RPCs

**What this is.** Here an RPC is a function stored inside the backend's PostgreSQL database that the desktop can call directly, like a service window at the ID office. Three windows exist: one for an AI badge, one for a billing badge, and one that tells the desktop where the AI Platform is.

**Words used.**

- **`SECURITY DEFINER`**: the function runs with the permissions of the account that created it, not of the caller, so it can read protected tables on the caller's behalf while only returning what the caller is allowed to see.
- **`public` and `auth_internal`**: two **schemas** (named folders inside the database). `public` holds the windows callers may use; `auth_internal` holds the protected code that does the work.
- **`current_org_id()`**: the function that returns the signed-in user's own clinic (precondition R-1 makes it work for many clinics).
- **`rpc_result`**: the backend's existing standard reply shape for RPCs, its own reply slip.
- **Signature** (of a function): its name and argument list. An "unversioned signature" is today's form without the version argument.

**Rules.**

- All are `SECURITY DEFINER` in `public`, delegating to `auth_internal`, keyed on `current_org_id()` (R-1).
- Every RPC takes `p_contract_version integer` as its first argument (§7).
- Results use the existing `rpc_result` envelope (`backend/supabase/migrations/20260516100000_auth_rbac_schema.sql:54-58`), extended with a `contract_version` field. The exception is `issue_ai_token`, which keeps returning `text`: the token's `ver` claim states its version.
- A version outside the backend's accepted range answers the error `CONTRACT_VERSION_UNSUPPORTED` (`issue_ai_token` raises it, that is, stops with that error).
- The product is pre-launch, so the unversioned signatures are dropped rather than kept alongside.

How to read the table: **RPC** is the function and its argument; **Who** says which users may call it; **Returns** is what comes back.


| RPC                            | Who                               | Returns                                                                                                      |
| ------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `issue_ai_token(p_contract_version)` | Members with an AI scope, and every administrator (empty `scopes` if it has none) | AI token (§2.1). Same name and return shape as today (`frontend/lib/core/ai/supabase_aat_mint_port.dart:22-30`), plus the version argument |
| `issue_billing_token(p_contract_version)` | `administrator` only   | `{token, abo_base_url, expires_at}`; errors `FORBIDDEN_ROLE`, `RATE_LIMITED` (20 per user per 10 minutes)     |
| `get_ai_endpoints(p_contract_version)` | Every member              | `{platform_base_url}` from `ai.platform_base_url`, so the desktop knows where to send its AI token            |


**Rules.**

- **No outgoing calls.** None of these makes a network call: the backend only signs and returns (C-02).
- **No status window.** It has no status RPC, because desktops read status from the platform (§4.2).
- **No AI, no AI status.** A member with no AI scope and no administrator role gets no AI token and sees no AI status, since it cannot use AI.

**What goes away.**

- `get_ai_availability` and `set_ai_availability` (latest definitions `20260821120000_fix_get_ai_availability_security_definer.sql:4`, `20260905120100_set_ai_availability_rpc.sql:67`, `20260905120400_fix_set_ai_availability_created_by.sql:4`).
- `enroll_installation_keypair`, `rotate_installation_key`, `revoke_installation_key` (`20260803140000_b1_review_resolution.sql:284,293,302`), with their `auth_internal` bodies.

The backend stores no status, so there is nothing for a clinic user to write (SR-07, SR-13).

### 3.2 Affected backend and frontend files

**What this is.** A renovation work order for the backend and the desktop app: the files whose behaviour must change so they speak the new contracts. These are named so the contracts can be traced to code. They are not a task list.

**How to read it.**

- **Area** is the part of the system; **Files** names the files and what changes in them.
- A suffix such as `:67-74` means lines 67 to 74 of the file named just before it, in today's code; `:159` is a single line.
- Files ending in `.sql` under `migrations/` are **migrations** (numbered database change scripts, §0.6). Their names start with a date and time, such as `20260905120300`.
- **Backend tests** are SQL scripts that check the database's behaviour.
- `pg_net`, `http` and `pg_cron` are PostgreSQL add-ons that would let the database make web calls or run timed jobs. None is enabled, which keeps the backend unable to call out (C-02).
- **Plaintext signing** is how the backend signs tokens today: with the installation's secret key read in readable (unprotected) form from a database row. It is replaced by the issuer key (02 K-2).
- The **installation lookup** is today's step that finds the clinic's installation and its key before signing; it is replaced too, because tokens now name the clinic (`org`), not an installation.
- `.dart` files are Flutter source files. `url_launcher` is the Flutter package that opens a web page in the browser (here, Paymob's payment page). `frontend/pubspec.yaml` is the app's list of packages. `app_en.arb` and `app_ar.arb` are the English and Arabic text files for the app's screens (`l10n` stands for "localisation").
- A **gauge** is the usage meter shown in the AI page; a **banner** is a strip of text across the top of a screen.


| Area                         | Files                                                                                                                                                                                                                      |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Backend issuer               | `auth_internal.issue_ai_token` (latest `20260905120300_fix_aat_lifetime_fallback.sql:4`): installation lookup `:67-74` and plaintext signing `:159` replaced; new migrations for §3.1 and 03 §4. No migration enables `pg_net`, `http` or `pg_cron` (C-02) |
| Backend tests                | `backend/tests/ai_keystore_rls.sql`, `ai_token_issuer.sql`, `catalog/stage-02-availability-and-enroll.sql`, `catalog/stage-02-revoke-rotate-availability.sql`                                                               |
| Frontend status              | `frontend/lib/features/ai/availability/ai_availability_reader.dart:17-18` and `ai_availability.dart:11-15` read the platform URL from `get_ai_endpoints` and the status from `/v1/capabilities` (§4.2); `ai_degraded_mode.dart:18-51` and `frontend/lib/core/ai/taxonomy.dart:23-42` take the §4.1 codes |
| Frontend usage               | `frontend/lib/core/ai/usage_summary_client.dart:40-53` becomes a `/v1/coverage` client; the gauge in `ai_feature_host_page.dart:280-305` is shown to administrators only (FR-61)                                             |
| Frontend billing             | New administrator feature: offers, checkout with `url_launcher` (`frontend/pubspec.yaml:60`), billing contact, history; staff notice banner; strings in `frontend/lib/l10n/app_en.arb` and `app_ar.arb`                     |


## 4. Desktops and AI Platform

**Purpose.** This is the desktop talking to the network: running AI requests, and asking "may this clinic use AI right now, and what should I show?". Section 4.1 lists the routes and the refusal reasons; section 4.2 the status the desktop displays and its notice codes; section 4.3 the exact rules that compute that status; and section 4.4 what the desktop does with all of it.

### 4.1 Clinic routes and denial codes

**What this is.** The network's public counters for clinics, and the specific reasons it may tick on a refusal slip. A **denial code** is the reason an AI request was refused, such as "allowance used up" or "too many at once".

**The version header.** Every clinic route (`/v1/requests`, `/v1/requests/{ref}`, `/v1/capabilities`, `/v1/coverage`) requires the `Aip-Contract-Version` request header and returns it on every response, including streamed ones, where it is sent before the first byte of the stream (§7).

**How to read the routes table.** **Route** is the method and path; **Change** says how it differs from today. Words used in it:

- `POST /v1/requests` runs an AI request. **Admission** is the DO's yes-or-no decision before the request runs (03 §6.2); its answers now carry `term_id` (which term pays for the request) internally, that is, not shown to the desktop.
- `GET /v1/capabilities` lists which AI features the clinic may use. It reads `coverage_mirror` by **primary key** (the row's own id, the fastest exact lookup) and *without* the TTL cache (§0.6), so a clinic that has just paid sees its plan at once (NFR-05).
- `GET /v1/coverage` is the administrator's detailed view. It reads the **live snapshot** from the DO itself (read-only, no write).
- `GET /v1/usage` is today's usage route; it is removed.


| Route                         | Change                                                                                                                                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /v1/requests`           | New denial codes below; admission answers carry `term_id` internally                                                                                                                                   |
| `GET /v1/capabilities`        | Lists capabilities from the active term's plan snapshot, read from `coverage_mirror` by primary key without the TTL cache, so a just-paid clinic sees its plan at once (NFR-05). Adds `status` (§4.2) for every role, computed from the same row. A token with empty `scopes` gets `status` and an empty capability list |
| `GET /v1/coverage`            | New, `role = administrator` only: `subscription_ref`, the live snapshot from the DO (read-only, no write) with plan, dates, allowance figures, `queued_count` and `held_count`, queued terms (plan and duration), and the last 12 terms with usage (FR-60, FR-66, P-09) |
| `GET /v1/usage`               | Removed; staff desktops call it today (`frontend/lib/features/ai/host/ai_feature_host_page.dart:148-152`), which FR-61 forbids                                                                          |


**How to read the denial codes table.** **Code** is the refusal reason; **HTTP** its status number (§0.6); **Replaces** names today's code it takes over (— means it is new); **Extra fields** are additional boxes on the refusal slip. Meanings in plain words:

- `allowance_exhausted`: the term's credits are used up. Today this case is reported as the general `quota_exhausted`.
- `coverage_lapsed`: the clinic has no usable coverage; `coverage_reason` says why (the `reason` values of §1.7). Today a missing configuration is reported as `quota_exhausted`.
- `coverage_unknown`: the platform could not find out the clinic's coverage right now; `retry_after` says how long to wait before trying again.
- `suspended`: the operator suspended the clinic. Today this is `installation_suspended`.
- `concurrency_limited`: too many requests are running at once for this clinic's plan; `retry_after` says when to try again.
- `rate_limited`: too many requests in a period; unchanged from today.
- `contract_version_unsupported`: the desktop's form edition is not accepted. It is checked before the token is even looked at, and `accepted_versions` lists the editions that are.

| Code                    | HTTP | Replaces                                                                   | Extra fields                    |
| ----------------------- | ---- | -------------------------------------------------------------------------- | ------------------------------- |
| `allowance_exhausted`   | 403  | `quota_exhausted` (`ai-platform/src/errors.ts:53-58`) for allowance         | —                               |
| `coverage_lapsed`       | 403  | `quota_exhausted` on a config miss (`src/admission/index.ts:612-619`)       | `coverage_reason`               |
| `coverage_unknown`      | 503  | —                                                                          | `retry_after`                   |
| `suspended`             | 403  | `installation_suspended` (`src/errors.ts:35-40`)                            | —                               |
| `concurrency_limited`   | 429  | `quota_exhausted` for concurrency (`src/admission/index.ts:471-483`)        | `retry_after`                   |
| `rate_limited`          | 429  | Unchanged                                                                  | Unchanged                       |
| `contract_version_unsupported` | 400 | —; checked before token verification                                 | `accepted_versions`             |


The `period_reset` supplementary field (`src/errors.ts:193-200`) is removed. (A **supplementary field** is an extra box on a refusal slip. `period_reset` tells the desktop, today, when the clinic's quota period resets; this design has no such periods, only terms.)

### 4.2 Status view and notice codes

**What this is.** The short status card every desktop shows about the clinic's AI, like the balance line on a phone's screen: "AI available, 12 days left, 75% used". It comes inside the answer to `GET /v1/capabilities`.

**The fields of `status`.** `status` in `GET /v1/capabilities` carries:

- `available`: whether AI may be used now (true or false).
- `state`: one of the §1.7 states.
- `reason`: why, when not available.
- `days_left`: days until the current term ends.
- `band`: the usage band.
- `notices[]`: the notice codes below.
- `next_change_at`: when the status will next change by itself, so the desktop knows when to look again.
- `as_of`: the time the status was computed.

**Rules.**

- It carries no prices, payments or references, so every role may see it (FR-61).
- A clinic with no `coverage_mirror` row gets `state = none`.

**Notice codes.** A notice code is a short fixed word, such as `ends_soon`, that the desktop turns into a sentence. Notice codes are a **closed vocabulary**: the list below is complete, and nothing else may appear. They are records, not UI strings (X-05): the platform sends the code, never the wording shown on screen. The desktop renders each code in an administrator form (with a renew action) or a staff form ("ask your administrator"), with no prices (FR-26, FR-27).

How to read the table: **Code** is the notice; **Raised when** is the condition that adds it to `notices[]`.


| Code                    | Raised when                                                                    |
| ----------------------- | ------------------------------------------------------------------------------ |
| `ends_soon`             | `days_left` is 7, 3 or 1 or fewer, with `queued_count = 0` (01 I-10)           |
| `in_grace`              | State `grace`; carries grace days left                                         |
| `allowance_low`         | Band 75 or 90 (FR-34, A29)                                                     |
| `allowance_exhausted`   | State `exhausted`                                                              |
| `lapsed`                | State `lapsed`                                                                 |
| `ended_reversed`        | State `reversed`                                                               |
| `suspended`             | Suspended flag                                                                 |


### 4.3 Read-time computation

**What this is.** The rule for working out the status card at the moment it is read ("read time"), rather than trusting a stored answer. The stored snapshot may be minutes or hours old, but it contains the term's dates, so the platform can compare those dates with the clock right now. It is like a printed bus timetable: even if the station's display board is broken, you can still tell from the timetable and your watch whether the last bus has gone.

For the clinic's `coverage_mirror` snapshot (03 §3.2) and the current time `now`, the platform applies these rules in order:

1. **No row:** `state = none`, `available = false`.
2. **Suspended:** `available = false`, `state = suspended`.
3. **Stored `active`:**
   - if `now < ends_at`, the state is `active`;
   - otherwise, if `queued_count > 0`, it is `active` (the next queued term, the "successor", takes over; its details arrive with the boundary event the DO alarm ships, 03 §6.7);
   - otherwise, if `now < grace_ends_at`, it is `grace`;
   - otherwise `lapsed`.
4. **Stored `grace`:** `grace` while `now < grace_ends_at`, then `lapsed`.
5. **Any other stored state** is unavailable as stored.
6. **Outputs.** `available` is true exactly for `active` and `grace`. `next_change_at` is the next of `ends_at` and `grace_ends_at` that is still in the future.

**Why it matters.**

- Because of rules 3 and 4, a lapse shows on time from stored dates alone, even when the DO and the ABO are down (A10, A28).
- The computation is display-only and never admits a request (SR-13). Whether an AI request runs is decided separately, by admission (03 §6.2, §6.5).

### 4.4 Desktop behaviour

**What this is.** What the desktop does with the status and the refusal codes: when it asks, and what each user sees. The guiding idea is that AI problems never interrupt the rest of the app; they appear as a calm message where the AI feature would be.

- **When to read status.** Every desktop holding an AI token calls `GET /v1/capabilities` on app open, on resume (as `frontend/lib/app/app.dart:47-57` does today), after any AI denial with a coverage code, at `next_change_at`, and every 5 minutes. A staff desktop contacts only the backend, for its token and the platform URL, and the platform's clinic routes (FR-61). Administrators additionally use `/v1/coverage` and the ABO API.
- **Platform unreachable.** A failed status read or `coverage_unknown` shows the platform-unreachable state (FR-65). AI cannot run then either; the rest of the app is unaffected (G5, C-04).
- **Denial display.** Denials are inline states, never dialogs (FR-64), extending the existing `AiDegradedView` pattern (`frontend/lib/features/ai/degraded/ai_degraded_view.dart:33-110`). "Inline" means the message replaces the AI panel in place; a **dialog** would be a pop-up window that blocks the screen. `AiDegradedView` is the app's existing screen part for "AI is not fully working".

How to read the table: **Platform code** is the code received (or a network failure); **FR-65 class** is which of the user-facing categories required by FR-65 it belongs to; **Staff sees** is the message for staff; **Administrator also sees** is what an administrator gets in addition. "Same" in the staff column means the same message as the row above; in the administrator column it means the administrator sees the same as staff, with nothing extra. Three codes come from today's platform rather than §4.1: `forbidden_capability` (the clinic's plan does not include this feature), `capability_disabled` (the feature is switched off, for example by a kill switch) and `provider_unavailable` (the AI provider behind the feature is not answering).


| Platform code                                                   | FR-65 class                   | Staff sees                                            | Administrator also sees     |
| --------------------------------------------------------------- | ----------------------------- | ----------------------------------------------------- | --------------------------- |
| `allowance_exhausted`, `coverage_lapsed`                        | Not paid, lapsed or used up   | "AI not available, contact your administrator"        | Renew or buy action         |
| `suspended`                                                     | Not paid, lapsed or used up   | Same                                                  | "Contact support" and the subscription reference |
| `forbidden_capability`                                          | Paid, nothing available       | "Not included in your clinic's AI plan"               | Plan name                   |
| `capability_disabled`, `provider_unavailable`                   | Paid, nothing available       | "AI temporarily unavailable"                          | Same                        |
| `coverage_unknown`, network failure                             | Platform unreachable          | "AI service unreachable"                              | Same                        |
| `concurrency_limited`, `rate_limited`                           | Safety limit (FR-09)          | "AI busy, try again shortly" with `retry_after`       | Same                        |
| `contract_version_unsupported` from the platform, the ABO or an RPC | App too old (NFR-09)      | "Update the app to use AI"                            | Same; billing screens show the same state |

## 5. Provider port

**Purpose.** This is the shop talking to the bank. A **port** is a fixed, provider-neutral list of operations the ABO needs from any payment provider, like a universal plug socket. Each provider gets an **adapter** (a plug converter, or translator) that turns these neutral operations into that provider's own calls and messages. At launch there is one adapter, for Paymob. The rest of the ABO only ever sees the neutral shapes, so adding a second provider later means writing one more adapter, not changing the shop.

### 5.1 Operations

**What this is.** The neutral operations on the socket. How to read the table: **Operation** is the name; **Input** and **Output** are the neutral shapes; **Launch** says whether it works at launch, and how. Words used in it:

- `capabilities`: what this provider supports (payment methods, cancelling a checkout, refunds, **mandates**, payouts, and whether it sends notifications for pending payments). A **mandate** is a standing permission to charge a card again later, as for automatic renewals.
- `createCheckout`: opens a payment session. `payer` is the billing contact; `expires_in_s` is its lifetime in seconds; `return_url` is where the payer's browser comes back after paying; `notify_url` is where the provider sends its notification.
- `parseNotification`: reads a raw notification and says whether it is **authentic** (really from the provider) and what events it reports.
- `inquire`: asks the provider directly for the real state. `bound` means the provider's order is the one stored when the checkout was created (FR-13), so a notification about some other order cannot be passed off as this one.
- `payoutLines`: reads the provider's payout report (a **CSV** file: a plain-text spreadsheet with one row per line).
- `refund`, `chargeMandate`: kept as **stubs** (placeholders that always answer `unsupported`) for future expansions.


| Operation           | Input                                                                                                                  | Output                                                                                         | Launch                     |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | -------------------------- |
| `capabilities`      | —                                                                                                                      | `{methods, cancel_checkout, refunds, mandates, payouts, pending_notifications}`                 | Yes                        |
| `createCheckout`    | `checkout_id`, `reference`, `amount_minor`, `currency`, `item_name`, `payer {name, email, phone}`, `expires_in_s`, `return_url`, `notify_url` | `redirect_url`, `expires_at`                                   | Yes                        |
| `cancelCheckout`    | `checkout_id`                                                                                                          | `cancelled` or `unsupported`                                                                   | Paymob: `unsupported`      |
| `parseNotification` | Raw request (method, query, headers, body)                                                                             | `{authentic, events[]}`                                                                        | Yes                        |
| `inquire`           | `{checkout_id}` or `{payment_id}`                                                                                      | `{bound, transactions[]}`; `bound` means the provider order is the one stored at creation (FR-13) | Yes                     |
| `payoutLines`       | Uploaded report file                                                                                                   | `PayoutLine[]`                                                                                 | CSV import                 |
| `refund`            | `payment_id`, `amount_minor`                                                                                           | —                                                                                              | Stub, `unsupported` (X-01) |
| `chargeMandate`     | Mandate reference, amount                                                                                              | —                                                                                              | Stub, `unsupported` (X-04) |


**Rules.**

- **No provider ids outside the adapter.** The **domain** (the ABO's own business logic, outside the adapter) never sees a provider id. The adapter maps provider references to `checkout_id` and `payment_id` in its private tables (03 §2.11).
- **Adding a provider.** It means a new adapter, a **registry entry** (a line in the list of known adapters) and a `/notify/{provider}` route (X-03).

### 5.2 Normalised types

**What this is.** "Normalised" means rewritten into one standard shape, whatever the provider's original looked like. These are the neutral forms the adapter hands to the rest of the ABO.

- `ProviderTxn` is one provider transaction (a payment attempt or a money movement). `kind` says what happened: `payment_succeeded`, `payment_failed`, `payment_pending` (not yet decided) or `reversal`. `occurred_at` is when; `dedupe_key` identifies the same transaction if it is reported twice; `reversal?` is present for reversals.
- `reversal` describes money going back: its `kind` (`refund`, `void`, `chargeback` or `unknown`), this reversal's `amount_minor`, the running total so far (`cumulative_reversed_minor`) and `is_full` (whether all the money has now gone back).
- `PayoutLine` is one line of a payout report: its `kind`, the `payment_id` it belongs to (null if unknown), and the **gross** amount (before fees), the **fee** and the **net** amount (after fees), with `settled_at` (when the money was settled to the vendor).


| Type          | Fields                                                                                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ProviderTxn` | `kind` (`payment_succeeded`, `payment_failed`, `payment_pending`, `reversal`), `checkout_id`, `payment_id`, `amount_minor`, `currency`, `occurred_at`, `dedupe_key`, `reversal?` |
| `reversal`    | `{kind: refund, void, chargeback or unknown; amount_minor; cumulative_reversed_minor; is_full}`                                                                      |
| `PayoutLine`  | `kind`, `payment_id` (null if unknown), `gross_minor`, `fee_minor`, `net_minor`, `settled_at`                                                                        |


**Confirmation rule.** Confirmation (01 §3.3 step 2) is a domain rule over `inquire` output, applied by the ABO itself, not by the adapter. A payment is confirmed only when all three hold:

1. `bound` is true;
2. a `payment_succeeded` transaction exists;
3. its `amount_minor` and `currency` equal the checkout snapshot.

Anything else records the payment as `withheld_mismatch` or records nothing, and alerts.

### 5.3 Paymob adapter

**What this is.** The translator between the neutral socket and Paymob. Each row of the table says which Paymob mechanism implements one port operation. Paymob's own terms, explained:

- An **intention** is Paymob's name for a payment session. Creating one gives an intention id, an order id (`intention_order_id`) and a `client_secret` (a one-time value that lets the browser open this payment on Paymob's page).
- **Unified Checkout** is Paymob's hosted payment page. The browser is sent there with the vendor's **public key** (an identifier safe to show) and the `client_secret`.
- A **secret key**, an **API key** and an **HMAC secret** are three separate Paymob credentials (02 K-5, K-6). The **auth token** is a short-lived badge obtained with the API key for inquiries.
- A **callback** is Paymob's notification. The **processed callback** is a `POST` from Paymob's servers with the transaction result; the **response callback** is a `GET` that arrives through the payer's browser when it is redirected back. Both are checked the same way, but the response callback only schedules an inquiry.
- **HMAC-SHA512 over the 20 documented fields in order** means the adapter joins 20 specific fields in Paymob's documented order and computes a seal with the shared HMAC secret. **Constant time** comparison takes the same time whether the seal matches early or late, so an attacker cannot guess it by timing.
- `amount` in **piastres** and `currency` EGP: Egyptian pounds in minor units (§0.6). **Card integration** is Paymob's card payment channel. `billing_data` is the payer's details. `special_reference` is a field for the vendor's own reference. `expiration` is the session's lifetime in seconds.
- `merchant_order_id`, `refunded_amount_cents`, `is_refunded`, `is_voided`, `has_parent_transaction`, `success` and `pending` are fields in Paymob's transaction data. A **child transaction** with `has_parent_transaction` is a later movement (such as a refund) linked to an original (parent) payment. Fields "not covered by the HMAC" are not part of the seal, so a forger could change them; the adapter therefore never trusts them from a callback.
- **Update Intention** is a Paymob endpoint that changes an open intention.

**Sources and caveats.**

- Sources: [callbacks and HMAC](https://developers.paymob.com/paymob-docs/developers/webhook-callbacks-and-hmac), [intention API](https://github.com/paymobaccept/paymob-ai-integration-skill/blob/main/skills/paymob-integration/references/intention-api.md), [HMAC verification](https://github.com/paymobaccept/paymob-ai-integration-skill/blob/main/skills/paymob-integration/references/hmac-verification.md), [transaction inquiry](https://github.com/paymobaccept/paymob-ai-integration-skill/blob/main/skills/paymob-integration/references/transaction-inquiry.md).
- Items marked R-2 are spike-dependent: they depend on an experiment against Paymob's real system that has not run yet (01 §7).
- Paymob's API and callbacks are not ours to version: the adapter pins (fixes in its code) the paths and the HMAC field list it was written against, and records its `adapter_version` on every evidence row (§7).

How to read the table: **Port operation** is the neutral operation of §5.1 (or a related concern); **Paymob mechanism** is how the adapter implements it.


| Port operation      | Paymob mechanism                                                                                                                                                                                                                                                              |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `createCheckout`    | `POST /v1/intention/` with `Authorization: Token <secret key>`; `amount` in piastres; `currency` EGP; card integration only; one item; `billing_data` from the payer; `special_reference` = checkout `reference`; `expiration` = 1800 s; notification and redirection URLs. Stores the intention id, the `intention_order_id` and `client_secret`. Redirect to Unified Checkout with the public key and `client_secret` |
| `parseNotification` | Processed callback (POST, `type = TRANSACTION`): HMAC-SHA512 with the HMAC secret over the 20 documented fields in order, compared in constant time. The response callback (GET) is authentic-checked the same way but only schedules an inquiry |
| `inquire`           | Auth token from `POST /api/auth/tokens` with the API key, cached for its life. `POST /api/ecommerce/orders/transaction_inquiry` by the stored `order_id`; `GET /api/acceptance/transactions/{id}` for a known transaction. Whether order retrieval lists every transaction is R-2 |
| Order binding       | `bound` is true only if the inquiry's `order.id` equals the stored `intention_order_id`. `merchant_order_id` is not covered by the HMAC, so it is never trusted from a callback                                                                                               |
| Normalisation       | `success` and not `pending`, not refunded, not voided: `payment_succeeded`. Not `success` and not `pending`: `payment_failed`. `pending`: `payment_pending` (inquiry only; there is no pending callback). `is_refunded`, `is_voided`, or a child with `has_parent_transaction`: a `reversal` against the parent, with the cumulative amount taken from the inquiry because `refunded_amount_cents` is not HMAC-covered |
| `payment_id` input  | The successful transaction's `id`                                                                                                                                                                                                                                              |
| `payoutLines`       | Dashboard CSV export (one month per file); columns mapped to `PayoutLine`, with transaction ids looked up in `paymob_txn`                                                                                                                                                      |
| Never called        | Update Intention; any refund or void endpoint                                                                                                                                                                                                                                 |


## 6. AI Platform change list

**Purpose.** A renovation work order for the AI Platform: every file, database script, configuration line and test that must change so the platform speaks the contracts above. It exists so that every contract can be traced to code, and nothing is left pointing at the old design. Non-engineers can skip it; the contracts themselves are complete without it.

**How to read it.**

- Every path is under `ai-platform/`. Lines refer to the current code. A suffix such as `:1605-1626` means lines 1605 to 1626 of that file; several suffixes in one row all refer to the same file.
- **Change** is one of: **Modify** (edit parts of the file), **Rewrite** (replace most of it), **Delete** (remove the file) or **Keep** (unchanged; "Keep logic" means the logic stays but how it is reached changes).
- Files not listed are unchanged: the `context`, `contracts`, `invocation`, `logger`, `prompt`, `prompt-artifacts.d.ts`, `provider`, `reference`, `router`, `stream`, `trace`, `validate` and `wall-clock-sleeper` sources.

### 6.1 Existing source files

**What this is.** Today's platform source files that change. Words used in the table that are not in §0:

- **Dispatch** is the code that looks at an incoming request's path and hands it to the right handler. A **handler** is the function that serves one route.
- `Env` is the list of settings, secrets and connections the Worker receives from Cloudflare. A **binding** is one such connection (such as `send_email`, Cloudflare's built-in way for a Worker to send email to a verified address).
- `GatewayObject` is today's name of the per-clinic DO class in the code. Its **RPC kinds** are the requests the Worker can send it. `alarm()` is the function Cloudflare runs when the DO's alarm clock rings.
- `scheduled` is the function Cloudflare runs on each cron schedule; a **branch** is one of the jobs it chooses between.
- **Entitlement, period, period close, plan tier, quota.** Today's model: a clinic has an **entitlement** (a manually set plan with a **tier** such as `starter` or `standard`; `minimumPlanTier` is the lowest tier a capability requires), usage is counted per calendar **period**, a **period close** job ends each period, and **quota** is the per-period usage limit. All of these are replaced by terms and plan snapshots.
- **Handoff settlement** is today's code that settles a request (records its final outcome and cost) when the record handed over between request stages is missing after an internal error. The **cost class** is a request's cost category, which plans cap (§0.5).
- **Fallback admission** is admitting a request from `coverage_mirror` when the DO is unreachable (03 §6.5), recorded in `fallback_admission` and later **drained** (settled into the DO). **Grace reconcile** and the **grace admission cap** are today's equivalents.
- **Reservation** and **settle by reservation id**: credits are set aside at admission and then turned into real usage at the end (03 §6.2).
- **Replay** is a repeated request; a **pipeline stage** is one numbered step in the platform's request processing.
- **Rollup** is the summary of usage; its **dimensions** are what it groups by. **Insert-or-ignore** writes a row only if one with the same key does not already exist.
- **Discovery** is the route that tells the desktop which capabilities exist. A **manifest** describes one capability. **Soft threshold** is the warning when usage passes a level. **Purge** deletes a clinic's data under the retention rules.
- **Cohort**, **routing policy**, **kill switch**, **token contract** and **capability lifecycle** are as in §1.3. **Audit** is the record of who did what; its **actor** is the person who did it.
- `EPHEMERAL_HORIZON_MS`, `GRACE_ADMISSION_CAP`, `INSTALLATION_KEY_TTL_DAYS`, `PLAN_TIERS` and similar upper-case names are constants in the code.


| File                              | Change  | Detail                                                                                                                                                                                                                                                                                                                                                    |
| --------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/worker.ts`                   | Modify  | Remove the `/control/*` dispatch (`:1605-1626`) and `/v1/usage` (`:1589-1598`); add `/v1/coverage` and the `status` field of `/v1/capabilities` (§4.2); check and echo `Aip-Contract-Version` on every `/v1/*` route before token verification (§7); export `VendorEntrypoint`. `Env`: drop `OPERATOR_BEARER_TOKEN` (`:124`); add the platform key, issuer id, Access and WebAuthn settings, the staging `DURATION_SCALE`, and the `send_email` binding. Replace `periodFromIso` (`:290-292`, `:619`) and the handoff settlement's `SELECT period_start FROM entitlement` (`:553-557`) with the admission's `term_id`; take the cost class from the term snapshot instead of the hardcoded values (`:983-984`); drop `minimumPlanTier` (`:1296`). `GatewayObject` (`:1487-1561`): new RPC kinds `grant`, `void`, `transferOut`, `transferIn`, `release`, `suspend`, `resume`, `inspect`, `settleFallback`, plus `alarm()`. `scheduled` (`:1699-1787`): remove the period-close branch (`:1768-1783`); replace grace reconcile (`:1721-1730`) with a `*/5` branch that drains fallback admissions, retries platform alerts and pings the heartbeat |
| `src/quota-do/index.ts`           | Rewrite | SQLite tables of 03 §3.1 in place of `QuotaDoState` (`:57-69`) and `EntitlementSnapshot` (`:32-47`); the rules of 03 §6. Removes `maybeResetPeriod` and `isQuotaExhausted` (`:263-292`); admission reserves (`:401-441`); denial and replay paths stop writing (`:375-418`). Keeps `EPHEMERAL_HORIZON_MS` and the concurrency constant (`:5-6`), with the limit now taken from the plan snapshot |
| `src/admission/index.ts`          | Modify  | Remove `mapEntitlementSnapshot` (`:148-166`); map the DO outcomes to §4.1 codes (`:461-483`, `:510-515`, `:612-619`); fallback (`:489-575`) follows 03 §6.5 using `coverage_mirror` and `fallback_admission`, replacing `GRACE_ADMISSION_CAP` (`:26`)                                                                                                         |
| `src/credit/index.ts`             | Modify  | `creditUsage` (`:207`) settles by reservation id; `reconcileGraceUsage` (`:264`) becomes the fallback drain; remove the 2-hour drop and zero-credit reconcile (`:20-23`, `:324-336`)                                                                                                                                                                       |
| `src/entitlement/index.ts`        | Modify  | Remove the tier and status checks (`:181-189`); keep kill switches (`:221-251`); the capability check reads the plan snapshot                                                                                                                                                                                                                           |
| `src/pipeline/index.ts`           | Modify  | Stage 3 (`:359`) pre-checks against `coverage_mirror`; stage 8 (`:445`) takes `term_id`, reservation id and snapshot from the DO; stage 15 settlement (`:629-661`) passes them on                                                                                                                                                                        |
| `src/identity/index.ts`           | Rewrite | `EnrolledKeyVerifier` (`:236-383`) becomes an issuer-token verifier (§2.1); `Principal` (`:14-25`) keeps `installationId`, now resolved from the binding; audience per route                                                                                                                                                                             |
| `src/config-cache/index.ts`       | Modify  | Remove the `installation_key`, `plan` and `entitlement` readers (`:228-233`, `:242-254`); add `issuer_key` and `tenant_binding` readers; coverage is never read through the cache (P-08)                                                                                                                                                                |
| `src/capability/index.ts`         | Modify  | `discover` (`:666-810`) reads the mirror snapshot instead of the entitlement (`:674-715`) and adds `status` (§4.2, §4.3); remove the tier checks (`:248-251`, `:732-737`) and the `plan:` grant fallback (`:765-771`)                                                                                                                                                                    |
| `src/platform-vocabulary.ts`      | Modify  | Remove `PLAN_TIERS` (`:2-7`) and `planTierMeetsMinimum` (`:92-99`); rename the key-algorithm constant (`:11-12`) for issuer keys                                                                                                                                                                                                                        |
| `src/manifest/index.ts`           | Modify  | `minimumPlanTier` (`:32`) no longer required; ignored if present                                                                                                                                                                                                                                                                                        |
| `src/journal/index.ts`            | Modify  | `period` becomes `term_id` in `PostResponseInput` (`:61-73`) and the insert (`:409-423`), which becomes insert-or-ignore on `request_id` (03 §6.2); `authenticateGetRequest` (`:544-577`) uses the new verifier                                                                                                                                                                                                    |
| `src/discovery/index.ts`          | Modify  | New verifier (`:69-76`)                                                                                                                                                                                                                                                                                                                                 |
| `src/usage-summary/index.ts`      | Delete  | Replaced by `src/coverage-read/index.ts`                                                                                                                                                                                                                                                                                                                |
| `src/period-close/index.ts`       | Delete  | P-13, FR-53                                                                                                                                                                                                                                                                                                                                             |
| `src/rollup/index.ts`             | Modify  | Dimensions `{installation_id, term_id}` (`:35-37`, `:45-86`)                                                                                                                                                                                                                                                                                            |
| `src/dashboards/index.ts`         | Modify  | The rejection-rate query (`:166-192`) counts the §4.1 codes                                                                                                                                                                                                                                                                                              |
| `src/retention/index.ts`          | Modify  | `purgeByInstallationId` (`:287-359`) stops deleting `entitlement` and `installation` (`:348`, `:354`) and marks the installation `deleted`; the `installation_key` delete (`:345`) goes with the table; never touches the grant ledger, coverage events, transfers or DO storage (P-14)                                                                   |
| `src/errors.ts`                   | Modify  | §4.1 codes; remove `quota_exhausted` (`:53-58`) and `period_reset` (`:193-200`); rename `installation_suspended` (`:35-40`)                                                                                                                                                                                                                              |
| `src/adapter.ts`                  | Modify  | Supplementary fields `retry_after` and `coverage_reason`                                                                                                                                                                                                                                                                                               |
| `src/soft-threshold/index.ts`     | Modify  | Reads the allowance band from the admission answer                                                                                                                                                                                                                                                                                                      |
| `src/rate-limit/index.ts`         | Modify  | Guard-rejection counters use the new codes                                                                                                                                                                                                                                                                                                             |
| `src/support/index.ts`            | Modify  | Lookup also by subscription reference and `org_id`                                                                                                                                                                                                                                                                                                      |
| `src/pricing/index.ts`            | Keep    | Provider cost ledger is vendor cost, not commercial output (FR-53)                                                                                                                                                                                                                                                                                      |
| `src/control/index.ts`            | Delete  | HTTP dispatch (`:135-259`) replaced by `src/vendor/entrypoint.ts`                                                                                                                                                                                                                                                                                       |
| `src/control/auth.ts`             | Delete  | Shared bearer (`:26-51`), P-07                                                                                                                                                                                                                                                                                                                          |
| `src/control/http.ts`             | Delete  | HTTP-only helpers                                                                                                                                                                                                                                                                                                                                       |
| `src/control/entitle.ts`          | Delete  | Manual entitle and override (`:161`, `:406`), FR-91                                                                                                                                                                                                                                                                                                     |
| `src/control/credit-price.ts`     | Delete  | P-13                                                                                                                                                                                                                                                                                                                                                    |
| `src/control/lifecycle.ts`        | Modify  | Remove enroll, rotate and revoke-key (`:201-467`) and `INSTALLATION_KEY_TTL_DAYS` (`:30-37`); `handleSuspend`, `handleResume` and `handleDelete` (`:468`, `:521`, `:571`) become entrypoint methods writing the DO flag                                                                                                                                    |
| `src/control/plan.ts`             | Rewrite | Immutable `plan_version` publish and retire (HP) instead of create, update and delete                                                                                                                                                                                                                                                                  |
| `src/control/quota-inspect.ts`    | Rewrite | `inspectCoverage`: DO ledger plus mirror, in place of the entitlement read (`:58-71`)                                                                                                                                                                                                                                                                   |
| `src/control/support-purge.ts`    | Modify  | Purge becomes HP `deleteInstallation` and respects the retention rule above                                                                                                                                                                                                                                                                             |
| `src/control/cohort.ts`           | Modify  | Plan membership from `plan_version` instead of `entitlement` (`:277-278`)                                                                                                                                                                                                                                                                              |
| `src/control/audit.ts`            | Modify  | Actor is the Access email; records `assertion_sha256`                                                                                                                                                                                                                                                                                                  |
| `src/control/types.ts`            | Modify  | Types follow the entrypoint methods                                                                                                                                                                                                                                                                                                                    |
| `src/control/kill-switch.ts`, `routing-policy.ts`, `token-contract.ts`, `capability-lifecycle.ts` | Keep logic | Exposed as class-H entrypoint methods; `token-contract` adds `ver = "2"`                                                                                                                                                                                                         |


### 6.2 New source files

**What this is.** Files that do not exist yet. Each row gives the new file and its job. Words used: **pure** rules are code that only computes answers from its inputs, with no storage or network, so it is easy to test; **end-of-month clamping** means a date that does not exist in the target month moves to that month's last day (for example, one month after 31 January lands on the last day of February, not in March; exact rules in 03 §6.1); a **thin wrapper** is a small file that mostly passes calls on to shared code; to **re-export** is to make shared code available under a local name.


| File                              | Purpose                                                                                                   |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `src/vendor/entrypoint.ts`        | `VendorEntrypoint`, the methods of §1.3 with their class checks                                           |
| `src/vendor/access.ts`            | Access JWT verification against the team certificates                                                     |
| `src/vendor/webauthn.ts`          | Assertion and attestation verification (§1.5); a thin wrapper over the shared package                     |
| `src/vendor/canonical-json.ts`    | Re-exports RFC 8785 canonicalization and hashing from the shared package                                  |
| `src/vendor/contract-version.ts`  | Per-channel accepted versions and the `contract_version_unsupported` answer, from the shared package (§7) |
| `src/coverage/engine.ts`          | Pure placement, boundary, reservation, exhaustion and grace rules (03 §6), used by the DO                 |
| `src/coverage/calendar.ts`        | Month and day arithmetic with end-of-month clamping; the staging `DURATION_SCALE` (03 §6.1)               |
| `src/coverage/grant-verify.ts`    | Envelope validation (§1.4), ceilings, velocity check                                                      |
| `src/coverage/transfer.ts`        | Binding re-creation, transfer package with `origin_grant_id` lineage, and saga steps                      |
| `src/coverage-read/index.ts`      | `GET /v1/coverage`, and the read-time status computation (§4.3) used by `/v1/capabilities`               |
| `src/signing/index.ts`            | Platform key: grant and void receipts                                                                     |
| `src/alert/index.ts`              | `send_email` delivery, `platform_alert` dedupe and retry, heartbeat ping                                  |


**The shared package.** A **package** is a bundle of code that several programs reuse. Both vendor Workers share one, so the two sides of each contract are built from the same definitions, like two offices printing their forms from the same master template.

- **Where it lives.** The shared package is `packages/vendor-contracts/` at the repository root, a `file:` dependency of both `ai-platform/` and the ABO (a `file:` dependency is one taken from a folder in the same repository rather than downloaded).
- **What it holds.** RFC 8785 canonical JSON, Ed25519 JWS signing and verification, WebAuthn verification, the message types of §1 and §2, and the version constants of §7.
- **Same bytes on both sides.** The ABO's console uses the same WebAuthn and canonical-JSON code to build the operation object (§1.5), so both sides hash the same bytes.
- **Not the backend.** The backend cannot import it and needs only to sign tokens in the §2.1 shape; it verifies nothing the vendor services sign, because it receives nothing from them (C-02).


### 6.3 D1 migrations

**What this is.** The numbered scripts that change the platform's D1 database structure (migrations, §0.6). To **create** a table adds it; to **drop** a table deletes it with its data; to **rebuild** one is to recreate it with a new shape. An **append-only trigger** blocks edits and deletions (§0.6); a **unique index** guarantees that no two rows share a value.

**Rules.**

- New files follow `migrations/20260911200000_invoice.sql` (that is, their numbers come after it, so they run after it).
- Existing migrations are not edited.
- The product is pre-launch, so tables are dropped rather than migrated (there is no live data to carry over).

How to read the table: **New migration** is the file name; **Content** says what it does, with the older migrations it reverses in brackets.


| New migration                                   | Content                                                                                                                                                                                                     |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `migrations/20261001120000_drop_invoicing.sql`  | Drop `invoice` (`20260911200000_invoice.sql:1-10`) and `credit_price` (`20260911120000_plan_catalogue.sql:11-17`)                                                                                            |
| `migrations/20261001120100_issuer_identity.sql` | Create `issuer_key`, `service_key`, `tenant_binding` (with `epoch` and a unique active binding per `org_id`); drop `installation_key` (`20260731120000_platform_schema.sql`). `installation` is unchanged: its `status` already accepts `deleted` |
| `migrations/20261001120200_coverage_ledger.sql` | Create `plan_version`, `ceiling_policy`, `coverage_mirror`, `coverage_event`, `grant_ledger`, `grant_void`, `transfer`, `transfer_step`, `fallback_admission`, `platform_alert`; drop `plan`, `entitlement` (with `20260821130000_entitlement_installation_unique.sql`) and `grace_admission_queue` (`20260821120000_grace_admission_queue.sql`); append-only triggers on the ledger tables; `grant_ledger` carries `origin_grant_id`; `coverage_mirror` and `coverage_event` carry `binding_epoch` |
| `migrations/20261001120300_usage_term.sql`      | Rebuild `usage_event` with `term_id` in place of `period` and a unique index on `request_id`, keeping the indexes from `20260805120000_f3_retention_indexes.sql`; reset `usage_rollup` dimensions |
| `migrations/20261001120400_operator_security.sql` | Create `operator_credential`, `assertion_used`; add `assertion_sha256` to `control_audit`; insert `token_contract` version `2` and retire `1` (`20260803120000_token_contract.sql`)                       |


### 6.4 wrangler.toml

**What this is.** `wrangler.toml` is the platform Worker's configuration file, read by Cloudflare's deploy tool (Wrangler). It lists schedules, the DO class, settings and connections. How to read the table: **Line today** is the place in today's file (`:9-10` means lines 9 and 10); **Change** is what happens there. Words used:

- **crons** are the schedules, written as cron expressions (§0.6): `0 3 * * *` is 03:00 every day, `0 4 * * *` is 04:00 every day, `0 5 1 * *` is 05:00 on the first of each month (today's period-close job), and `*/5 * * * *` is every 5 minutes.
- **DO class** is the declaration of the per-clinic DO. "SQLite-backed" means each DO has its own SQLite storage; "the in-DO schema migrates on first access" means each DO updates its own table structure the first time it runs after the deploy.
- **vars** are plain (non-secret) settings. There are three blocks (`:24-29`, `:62-67`, `:100-105`), one per environment (development, staging and production; the three rate-limit ranges below follow the same pattern). The new ones: `ISSUER_ID` (the backend's issuer id, §2.1), `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` (which Cloudflare Access account and application to trust), `WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN` (the relying party and origin, §1.5), and `DURATION_SCALE` (staging's time compression, 03 §6.1). `CONFIG_CACHE_TTL_MS` is the TTL cache's lifetime.
- `workers_dev = false` and `preview_urls = false` turn off Cloudflare's automatic public test addresses for the Worker. `[observability] enabled = true` turns on Cloudflare's logging.
- A **secret** is a setting stored encrypted, such as `PLATFORM_SIGNING_KEY` (the platform key, 02 K-3).
- **Rate limits** are the existing request caps (FR-09).


| Line today                     | Change                                                                                                                                              |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:9-10` crons                  | Keep `0 3 * * *` and `0 4 * * *`; remove `0 5 1 * *`; add `*/5 * * * *`                                                                               |
| `:17-19` DO class              | Unchanged (already SQLite-backed); the in-DO schema migrates on first access                                                                         |
| `:24-29`, `:62-67`, `:100-105` vars | Remove `OPERATOR_ID`; add `ISSUER_ID`, `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `WEBAUTHN_RP_ID`, `WEBAUTHN_ORIGIN`; `DURATION_SCALE` in staging only (absent in production). `CONFIG_CACHE_TTL_MS` stays for non-coverage configuration |
| Top level (absent today)       | `workers_dev = false`, `preview_urls = false`; `[observability] enabled = true` (02 §1.1); a `send_email` binding with the verified destination; secret `PLATFORM_SIGNING_KEY` in place of `OPERATOR_BEARER_TOKEN` |
| `:44-57`, `:82-95`, `:120-133` rate limits | Unchanged (FR-09)                                                                                                                       |


### 6.5 Tests

**What this is.** The automated tests that must be removed, rewritten or added. Paths are under `ai-platform/test/`. Words used:

- **vitest** is the test runner the platform uses; `vitest.e2e.config.ts` and `vitest.workers.config.ts` are its configuration files for two kinds of test run.
- **e2e** ("end to end") tests run the whole platform as a caller would. The **e2e harness** (`e2e/harness/`) is the helper code that sets those tests up and makes the calls, like a test rig.
- `system/*` **interplay tests** check how several parts work together.
- **Test Access JWTs**, **test passkey assertions** and a **test issuer key** are fake credentials made only for tests.
- A **concurrency test** fires many requests at once to prove two cannot both take the last credit (A34). The **write budget** is the agreed maximum number of database rows written per AI request (01 R-7).

How to read the table: **Change** is Delete, Rewrite, Add or Config; **Files** names the test files (or, for Add, what the new tests cover).


| Change   | Files                                                                                                                                                                                                                                                                                                                                                      |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Delete   | `period-close.test.ts`, `price-list-activation.test.ts`, `entitle-grant.test.ts`, `e2e/stage-03-enroll-validation.test.ts`, `e2e/stage-03-lifecycle-rotate.test.ts`, `e2e/stage-04-entitle-auth-period.test.ts`, `e2e/stage-04-entitle-quota-grants-validation.test.ts`                                                                                      |
| Rewrite  | `identity.test.ts`, `config-readers.test.ts`, `config-cache.test.ts`, `quota-do.test.ts`, `admission-credit.test.ts`, `quota-inspect.test.ts`, `entitlement.test.ts`, `plan-catalogue.test.ts`, `usage-summary.test.ts` (becomes coverage-read), `control.test.ts` (becomes vendor-entrypoint), `retention.test.ts`, `support-purge.test.ts`, `taxonomy.test.ts`, `error-body.test.ts`, `rollup-reconciliation.test.ts`, `journal.test.ts`, `discovery-http.test.ts`, `capability.test.ts`, `migrations.test.ts`, `worker-entry.test.ts`, the `system/*` interplay tests and the `e2e/stage-*` tests that enroll or entitle through `/control/*`; the e2e harness `e2e/harness/control.ts` and `e2e/harness/env.ts` (they drive `/control/*` with `OPERATOR_BEARER_TOKEN`) become a harness that calls `VendorEntrypoint` with test Access JWTs and test passkey assertions, and mints issuer tokens with a test issuer key |
| Add      | Coverage engine and calendar, including grace exhaustion and the staging scale; grant verification, ceilings and key-state answers (including `unknown_kid`); void tombstones and reversal through transfer lineage; WebAuthn and Access verification; coverage-event epoch ordering; the §4.3 status rules, including a staff token seeing no prices; transfer saga, `awaiting_transfer` and `held_for_transfer`; contract versions N, N−1 and unsupported on every route and entrypoint method (§7); fallback drain and `request_id` dedupe; a concurrency test for A34 that also measures rows written per AI request against the budget (01 R-7)                                                                                                       |
| Config   | `ai-platform/vitest.e2e.config.ts` and `vitest.workers.config.ts` drop the `OPERATOR_BEARER_TOKEN` binding and bind the test issuer key, Access settings and `DURATION_SCALE` |


### 6.6 Other affected paths

**What this is.** Outside the platform source, these paths depend on what the change removes. They are named so nothing is left pointing at `/control/*` or installation keys; they are not a task list.

Words used: `ai-platform-viewer/` is an existing internal web tool for looking at and controlling the platform; a **shell script** (`.sh`) is a file of command-line steps; **seeding** a setting means putting in its first value; **superseded** means replaced by a newer design.

How to read the table: **Path** is the file or folder; **Why it is affected** says what it uses today; **Outcome** says what happens to it.


| Path                                           | Why it is affected                                                                                                                  | Outcome                                                                                           |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `ai-platform-viewer/`                          | About 20 files call `/control/*` with the shared bearer, and its clinic pages sign with installation keys                          | Its control pages are removed; the ABO console replaces them (FR-91). Clinic-route pages use issuer tokens and send `Aip-Contract-Version` |
| `ai-platform/scripts/bootstrap-routing-policy.sh` | Seeds the routing policy through `/control/*`                                                                                    | Replaced by the console's routing-policy action (class H)                                         |
| `docs/architecture/ai-platform/`               | Describes installation keys, entitlements, periods and `/control/*`                                                                  | Marked superseded where this design changes them, with a link here                                |
| `frontend/` AI and billing clients              | Every platform, ABO and RPC call                                                                                                    | Send the channel version (§7); render `contract_version_unsupported` as the update state (§4.4)  |


## 7. Contract versioning

**Purpose.** Programs are upgraded at different times. A clinic may run an old desktop for weeks; the ABO and the platform are deployed separately. Versioning lets both sides of a channel keep understanding each other during a changeover, like two offices agreeing to accept both the old and the new edition of a form until everyone has switched.

Every request and every response between the desktop app, the ABO console, the ABO, the shared backend and the AI Platform carries a contract version, so either side of a channel can deploy first (NFR-09, X-10). To **deploy** is to release a new version of a program into use.

### 7.1 Channels

**What this is.** Where the edition number is written on each kind of form. Each channel has one integer version, starting at 1 at launch. Tokens keep their own `ver` claim (`"2"`, §2.1).

How to read the table: **Channel** is the sender and receiver (the arrow `→` here simply means "sends to"; `↔` means both ways); **Where the version travels** is the header, argument or field that carries it; **Refusal** is what the receiver answers when it does not accept the version. Words used:

- A **gradual rollout** releases a new version to a share of traffic at a time, so for a while an old Worker may talk to a new DO.
- `/return/{provider}` is the ABO page the payer's browser lands on after paying; `v` is a query parameter (§0.6) on that address.
- **Provider-controlled** means Paymob decides its own formats; the vendor cannot version them.
- A **payload** is the structured content of a message, as opposed to its headers.


| Channel                                              | Where the version travels                                                                                  | Refusal                                                                  |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Desktop → ABO clinic API `/v1/*` (§2.2)              | `Abo-Contract-Version` request and response header; `contract_version` in every response body              | HTTP 400 `contract_version_unsupported`                                   |
| ABO console → ABO `/ops/*`                           | Same as the clinic API. The console ships with the ABO; the check catches a browser tab left open across a deploy | Same; the console asks for a reload                                  |
| Desktop → backend RPCs (§3.1)                        | `p_contract_version` argument; `contract_version` in `rpc_result`                                          | Error `CONTRACT_VERSION_UNSUPPORTED`                                     |
| Desktop → platform clinic routes (§4.1)              | `Aip-Contract-Version` request and response header, sent before the first byte of a stream; `contract_version` in JSON bodies | HTTP 400 `contract_version_unsupported`                   |
| ABO → `VendorEntrypoint` (§1)                        | `contract_version` in every argument object and every result                                               | `rejected` with `contract_version_unsupported`                           |
| Platform Worker → per-clinic DO RPC                  | `contract_version` in every call and answer. They ship in one deployment, but a gradual rollout can pair an old Worker with a new DO | `rejected`; the Worker maps it to `coverage_unknown` for the clinic |
| Browser return from Paymob → ABO `/return/{provider}` | `v` query parameter on the `return_url` the ABO sends at checkout creation                                | None: the page is UX only, so an unknown `v` still schedules an inquiry and shows a neutral page |
| ABO ↔ Paymob API and `/notify/{provider}`            | Provider-controlled. The adapter pins the paths and HMAC field list it was written for and records `adapter_version` on each evidence row (§5.3) | A shape the adapter cannot parse is an A23 alert |
| Tokens (AI, billing)                                 | `ver` claim; the platform checks `token_contract`, the ABO its own accepted list                           | `unauthenticated`                                                        |


The heartbeat ping and `send_email` alerts carry no contract payload and are out of scope.

### 7.2 Rules

**What this is.** The rules every channel follows. N is the current version of a channel and N−1 the one before it. Think of a counter that accepts this year's and last year's form, rejects older ones before even reading them, and always replies on the same edition you used.

- A receiver accepts the current version N and the previous N−1 of each channel it receives, and answers in the version the request used.
- A missing version, or one outside N and N−1, gets `contract_version_unsupported` with `accepted_versions`. The check runs before authentication and before any write, so nothing changes.
- A sender that receives an answer in a version it does not know treats it as `contract_version_unsupported`.
- Readers ignore unknown fields. Adding an optional request field or a new response field keeps the version. Removing or renaming a field, or changing the meaning of a field, code, state or notice, needs a new version.
- Stored payloads (grant envelopes, receipts, snapshots, facts, work-row payloads) keep the `contract_version` they were written in and are never rewritten. Readers support every version still present in storage. Signed objects include the version, so it cannot change after signing.
- A retried work row resends its stored envelope in its original version.
- The version constants live in `packages/vendor-contracts/`, which both Workers import. The backend keeps its copy in `ai_internal.app_settings` (`ai.contract_versions`), the desktop in `frontend/lib/core/contract_versions.dart`. A contract test (an automated check that both sides agree on the contract) fails if either copy differs from the package.

### 7.3 Changing a version

**What this is.** The safe order of steps for moving a channel from version N to N+1, like a changeover where the receiving office first learns to accept the new form, then senders switch to it, and only then is the old form withdrawn. A **sender** is the side that sends requests on a channel; a **receiver** is the side that answers them. "Vendor-internal" channels run only between the vendor's own systems; "desktop-facing" channels are those a clinic's desktop calls. The **minimum supported desktop version** is the oldest app version the vendor still supports.

1. Deploy every receiver of the channel so it accepts N and N+1. A receiver drops N−1 in the same deploy only if the conditions below already hold for N−1.
2. Switch the senders to N+1.
3. Drop N on the receivers once its conditions hold:
   - Vendor-internal channels (ABO → platform, including coverage events; Worker → DO): every sender is deployed on N+1 and no open work row still holds a payload in N.
   - Desktop-facing channels (ABO clinic API, RPCs, platform clinic routes): the minimum supported desktop version sends N+1. Desktops below it show the "update the app" state (§4.4), never an error dialog.

