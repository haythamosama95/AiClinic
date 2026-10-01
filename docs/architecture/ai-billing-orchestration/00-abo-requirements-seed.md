# AI Billing Orchestrator — Product Requirements (Design Seed)

**Status:** Seed — the input for the ABO design. It states *what* the ABO must achieve, not *how*.
**Date:** 2026-09-30. **Revised:** 2026-10-01, the shared backend talks only to the desktop app
(C-02, FR-61, FR-62, SR-09).

This document is self-contained. The ABO design is derived from it and from the current code. Tags:

- **[Decided]** = a product-owner decision.
- **[Assumed]** = a working assumption that follows from a decision; confirm or override during
  design.
- Untagged = a baseline requirement.

Nothing here prescribes tables, keys, endpoints, or state machines. Those belong to the design.

## Table of Contents

1. [Product description](#1-product-description)
2. [Goals and non-goals](#2-goals-and-non-goals)
   - [Goals](#21-goals)
   - [Non-goals](#22-non-goals)
   - [Expected future expansions](#23-expected-future-expansions)
3. [Actors and context](#3-actors-and-context)
4. [Functional requirements](#4-functional-requirements)
   - [Offers and catalogue](#41-offers-and-catalogue)
   - [Purchase and activation](#42-purchase-and-activation)
   - [Renewal, lapse, and reactivation](#43-renewal-lapse-and-reactivation)
   - [Plan changes and allowance exhaustion](#44-plan-changes-and-allowance-exhaustion)
   - [Complimentary grants and trials](#45-complimentary-grants-and-trials)
   - [Reversals, duplicates, and failures](#46-reversals-duplicates-and-failures)
   - [Payment records](#47-payment-records)
   - [Clinic visibility and the AI flag](#48-clinic-visibility-and-the-ai-flag)
   - [Vendor operations and support](#49-vendor-operations-and-support)
   - [Reconciliation](#410-reconciliation)
   - [Launch](#411-launch)
5. [Security requirements](#5-security-requirements)
   - [General](#51-general)
   - [Complimentary-grant authority](#52-complimentary-grant-authority)
6. [Reliability and operational requirements](#6-reliability-and-operational-requirements)
7. [Records and retention](#7-records-and-retention)
8. [Constraints and givens](#8-constraints-and-givens)
   - [Environment](#81-environment)
   - [Current AI Platform gaps](#82-current-ai-platform-gaps)
9. [Product decisions](#9-product-decisions)
10. [Design parameters](#10-design-parameters)
11. [Acceptance scenarios](#11-acceptance-scenarios)
12. [Glossary](#12-glossary)

---

## 1. Product description

AiClinic clinics use an optional, paid AI add-on served by the vendor's AI Platform. Today the
vendor turns AI on by hand: enrolling the clinic on the platform, granting an entitlement, and
flipping the clinic's AI flag.

The **AI Billing Orchestrator (ABO)** is the vendor-side service that makes this **self-service and
paid**:

- A clinic owner picks a plan in the desktop app and pays through a hosted payment page.
- The clinic's AI is provisioned automatically, with no vendor involvement.
- The service keeps being renewed and recorded correctly for as long as the clinic is a customer.

The ABO owns the **commercial relationship**: offers, payments, subscriptions, reversals, and
renewal and allowance notices. The AI Platform remains the **only place that enforces AI access**.
The ABO tells the platform what a clinic is entitled to; the platform decides every request.

The product is not launched. It launches only when the whole ABO is implemented, so there is no
interim manual-selling phase and no live customer data to migrate. [Decided]

## 2. Goals and non-goals

### 2.1 Goals

1. **G1 — Paid self-service.** A clinic can go from "AI off" to "AI on" by paying, with no vendor
   contact.
2. **G2 — No way around payment.** Nobody can obtain AI service without a corresponding payment or a
   deliberate, attributed, securely authorised vendor grant. [Decided]
3. **G3 — Money always turns into service, or the vendor is told.** A received payment is
   provisioned within minutes. If it is not, the vendor is alerted, and recovery never needs
   database surgery.
4. **G4 — Correct commercial records.** Every payment, grant and reversal is recorded accurately and
   can be traced end to end.
5. **G5 — AI is never a blocker.** Losing or lapsing AI must never block clinical workflows or lose
   clinic data. The rest of the app keeps working.
6. **G6 — Provider independence.** Paymob is the first payment provider, but every provider
   capability (checkout, notifications, status inquiry, and later refunds and payouts) sits behind
   one provider-neutral interface. No provider concept leaks into the ABO's domain, the clinic app,
   the shared backend, or the AI Platform. [Decided]
7. **G7 — Operable by one person.** The developer, as the single vendor operator, can run support,
   grants and incidents without touching raw databases for routine work.
8. **G8 — Proportionate, not minimal.** The design fits the real volume: a few orders per day at
   clinic scale, and one operator. Simplicity is a tie-breaker only, applied in this order:
   1. Every security requirement (§5) and correctness invariant is met in full. Simplicity never
      justifies weakening, merging or deferring one. Defence in depth is expected where a single
      control failing would expose payments, grants or clinic data.
   2. Every other requirement is met.
   3. Every expansion in §2.3 stays possible without redesign.
   4. Among designs that pass 1–3, prefer fewer runtime components, fewer moving parts, and less
      operator burden.

   "Simple" means fewer things to run and understand. It does not mean fewer checks, fewer
   records, or fewer extension points.

### 2.2 Non-goals

- Collecting card data, or holding payment credentials in any vendor or clinic system.
- Saved cards or merchant-initiated charges. Every payment is made by the payer. [Decided]
- Issuing refunds at launch. [Decided] The domain model and provider interface must still leave
  room to add refunds later without a redesign (FR-45).
- Mid-term upgrades, downgrades, proration or repricing as a self-service flow while allowance
  remains. [Decided] Allowance exhaustion (§4.4) is the only early exit.
- Email, SMS or other out-of-app reminders. Notices are in-app only, including for staff (FR-27).
  [Decided]
- Per-clinic backends or clinic-owned backends. [Decided]
- Enterprise billing: purchase orders, net terms, multi-currency, usage-based overage billing.
- Enforcing AI access in the ABO or in the clinic app. That is the AI Platform's job.
- A manual or partial launch. [Decided]

### 2.3 Expected future expansions

None of these is built at launch. Each must be addable later without redesigning the core
flows, migrating the meaning of existing records, or weakening a security requirement. The
design must name, for each one, the seam that keeps it open, such as an interface, a record
field, a state, or a contract version. It must build no more than that seam.

| # | Expansion | What must stay possible |
|---|-----------|-------------------------|
| X-01 | Refunds, full and partial (FR-45) | Vendor-initiated reversals through the provider interface, applied to a specific payment |
| X-03 | Additional payment providers | A second provider alongside the first, chosen per checkout; no provider concept outside the adapter |
| X-04 | Saved cards and automatic renewal | Merchant-initiated charges for renewals, with explicit payer consent |
| X-05 | Out-of-app notices | Email, SMS or WhatsApp delivery of the same notices, to the billing contact |
| X-06 | Mid-term upgrades with proration | Changing plan or term length mid-term by paying a computed difference |
| X-07 | Allowance top-ups | Buying extra allowance inside the current term without starting a new term |
| X-08 | Discounts and promotional codes | Price adjustments recorded against the payment and the offer version |
| X-09 | More operators | Several named operators with roles, and a two-person rule for large grants |
| X-10 | Contract evolution | Versioned contracts on every request between the desktop app, the ABO, the shared backend and the AI Platform, so either side can deploy first (NFR-09) |

## 3. Actors and context

| Actor | Role in billing |
|-------|-----------------|
| Clinic owner / administrator | Chooses a plan, pays, renews, changes plan for the next term, maintains the billing contact details, and sees payment history. May use any of the clinic's desktops (multi-branch). |
| Clinic staff | Use AI features when the clinic is entitled. See renewal and allowance notices that ask them to tell an administrator. Never pay, see payment details, or contact billing services. |
| Clinic desktop app (Flutter, Windows) | Presents offers and status; starts checkout in the system browser. |
| Shared backend (one Supabase/PostgreSQL project) | Hosts **all clinics as tenants** of one remotely hosted project **owned by the developer**. Holds clinic data and whatever credentials let it vouch for each clinic's users toward the vendor services. Talks only to the desktop app (C-02). Reachable over the internet. |
| AI Platform (existing Cloudflare Worker + D1 + per-clinic Durable Object) | Knows clinics and their credentials; enforces entitlement and usage on every AI request; tells each desktop its clinic's AI status; exposes control operations. |
| Payment provider (Paymob first) | Hosted checkout, payment notifications, transaction inquiry, payout reports. Reports reversals the vendor did not initiate. |
| Vendor operator (the developer, one person) | Owns and operates the shared backend, the ABO and the AI Platform. Handles support, complimentary grants, incident response and reconciliation review. |

## 4. Functional requirements

### 4.1 Offers and catalogue

- **FR-01** The vendor defines sellable **offers**: which platform plan, term length, price,
  currency, usage allowance and grace policy. Offers live in vendor data, not in code, so the vendor
  can add, reprice or retire them without an app release or a deploy. [Decided]
- **FR-02** Monthly, quarterly and annual terms are all available at launch. [Decided]
- **FR-03** Prices are the final amount the buyer pays. Nothing is added to them at checkout.
  [Decided]
- **FR-04** Price changes never alter what a clinic has already paid for. Past prices stay
  reconstructable from the records.
- **FR-05** The desktop app shows offers from the vendor at runtime. Names, prices, terms and copy
  are never compiled into the app. [Decided]
- **FR-06** A plan or offer can be retired from sale. Clinics on it keep it until their term ends,
  and must pick a current offer to renew. A retired offer is never charged silently.
- **FR-07** Each offer defines one **usage allowance** for its whole term. An annual buyer gets the
  full term's allowance from the first day and can use it at any pace. There are no monthly
  allocations. [Decided]
- **FR-08** Allowance left over when a term reaches its end date does not carry into the next term.
  [Assumed]
- **FR-09** Safety limits that protect the vendor from runaway cost, such as concurrency and rate
  caps, stay separate from the allowance. They never shorten or end a subscription. [Assumed]

### 4.2 Purchase and activation

- **FR-10** An owner or administrator can buy from any of the clinic's desktops. Staff cannot.
  [Decided]
- **FR-11** Payment happens on the provider's hosted page in the system browser. The app never
  handles card data or embeds a provider SDK. [Decided]
- **FR-12** Once a payment is confirmed, AI becomes available automatically. The typical time from
  payment to AI on is under a minute. It never waits on a person, and it does not depend on the
  buyer's desktop staying open.
- **FR-13** The purchase is bound to the paying clinic, so it cannot be redirected to another clinic.
- **FR-14** The app shows clear progress and outcome (waiting, paid, active, failed or abandoned),
  and recovers after an app restart, reinstall, or switch to another desktop.
- **FR-15** An abandoned or failed checkout never blocks a new attempt or a different plan choice.
- **FR-16** Exactly what was bought is what gets granted: the plan, term, allowance and price of the
  specific checkout that was paid. Any amount or currency mismatch grants nothing and alerts.
- **FR-17** The checkout states that payments are non-refundable (FR-45) before the buyer pays.
  [Assumed]

### 4.3 Renewal, lapse, and reactivation

- **FR-20** Renewals are paid manually by the owner or administrator for the next term. There is no
  automatic charging. [Decided]
- **FR-21** Paying early never loses paid time. The prepaid term starts when the current one ends,
  whether it ends at its end date or earlier because its allowance is used up (FR-33). A prepaid
  term's allowance is never added to the current term. [Decided]
- **FR-22** After a term reaches its end date unpaid, service continues through a **grace period**.
  After grace, AI stops, and nothing else in the app is affected. The initial grace is 7 days. There
  is no grace after allowance exhaustion (FR-33). [Decided]
- **FR-23** AI stops on time even if the ABO is down, degraded, or misconfigured. Non-payment
  enforcement must not depend on the ABO being healthy at that moment.
- **FR-24** A lapsed clinic can reactivate by paying, at any time and from any owner or
  administrator desktop, without vendor contact and without re-onboarding.
- **FR-25** Renewal and reactivation keep working after a desktop reinstall and after any rotation of
  the credentials the shared backend uses to act for the clinic.
- **FR-26** Owners and administrators see in-app notices at these points, so AI features never just
  quietly disappear:
  - before a term's end date;
  - when the allowance is running low (FR-34);
  - when AI has lapsed or the allowance is used up.
- **FR-27** Staff see the same notices in a staff form, for example "AI ends in N days" or "AI
  allowance almost used; ask your administrator to renew". A clinic whose owner rarely opens the app
  still hears about it. Staff notices show no prices, payment details or purchase actions. [Decided]

### 4.4 Plan changes and allowance exhaustion

- **FR-30** The owner can switch plan or term length for the next term through self-service. The
  change takes effect at the term boundary, with no proration. [Decided]
- **FR-31** While allowance remains, a clinic cannot upgrade, downgrade or change term length
  mid-term. The app offers a plan change only as a choice for the next term. [Decided]
- **FR-32** The vendor can still grant an immediate upgrade or other adjustment as an attributed
  goodwill action (§4.5).
- **FR-33** When a term's allowance is fully used, AI stops at once and that subscription ends early
  with no grace. Unused calendar time is forfeited, and no refund or credit is given. What happens
  next:
  - If the clinic has a prepaid term, it starts immediately (FR-21).
  - Otherwise the owner or administrator can buy any **currently offered** plan and term, including
    the same plan if it is still offered. The new term and its allowance start at payment.
  - Retired offers cannot be bought.

  [Decided]
- **FR-34** Owners, administrators and staff are warned as the allowance runs low, so exhaustion is
  never a surprise. [Assumed]

### 4.5 Complimentary grants and trials

- **FR-35** The vendor can grant complimentary access (a trial, goodwill, a correction or an
  extension) to any clinic, including one that is already paying.
- **FR-36** Every complimentary grant is attributed to the operator who made it, carries a reason,
  and appears in reconciliation like any other grant.
- **FR-37** A clinic on a trial or complimentary grant can convert to paid by itself, with no gap and
  no double coverage.
- **FR-38** One operator can grant alone. That authority is protected as in §5.2. [Decided]

### 4.6 Reversals, duplicates, and failures

- **FR-40** A declined or pending payment attempt never cancels the clinic's ability to pay. The owner
  can retry.
- **FR-41** Paying twice for the same term is detected, and the extra payment is added as more paid
  time: the next term of the paid offer, stacked after existing coverage. The owner and the operator
  are both told. No value is lost. [Assumed, follows from FR-45]
- **FR-42** A reversal the vendor did not initiate is recognised, recorded against the **specific
  payment** it reverses, and never read as a new payment. Examples are a chargeback, a provider void,
  or a refund someone issued from the provider dashboard despite FR-45.
- **FR-43** A full reversal of the payment that funds the current term ends access now, with no
  grace. Reversing an older payment does not affect current service. Every reversal alerts the
  operator.
- **FR-44** Chargebacks can be recorded manually when the provider does not notify them, and then
  take effect like a full reversal.
- **FR-45** The vendor issues no refunds at launch. The provider-neutral interface and the records
  must allow refunds (full and partial) to be added later as a new capability, not a redesign.
  [Decided]

### 4.7 Payment records

- **FR-50** Every payment and reversal is recorded with amount, currency, date, offer, term covered,
  and a reference the owner and support can both quote.
- **FR-51** The owner provides the billing contact details the payment provider requires (name,
  email, phone) once and can update them.
- **FR-53** The AI Platform does not hold amounts paid and does not issue anything commercial. Usage
  reporting is separate from payment records.

### 4.8 Clinic visibility and the AI flag

- **FR-60** Owners and administrators can see the current plan, term end date, allowance used and
  remaining, grace status, and payment history.
- **FR-61** Staff see whether AI is available and the staff notices of FR-27, nothing more. They
  never see prices or payment details, and staff desktops never contact billing services. A staff
  desktop reads its clinic's status from the AI Platform, which it already uses for AI, and only
  in the staff form. [Decided]
- **FR-62** The "AI available" flag and subscription status are read by each desktop from the AI
  Platform when it needs them. No copy is kept on the clinic's behalf, so there is nothing a desktop
  could refresh or set. [Decided]
- **FR-63** The flag and status reflect a renewal, lapse, exhaustion or reversal within a bounded
  time, even if no owner or administrator opens the app. [Assumed]
- **FR-64** If a staff member uses AI after it has stopped but before the flag catches up, the denial
  is shown as a plain "AI not available, contact your administrator" state, never an error dialog.
- **FR-65** The app can tell "not paid, lapsed or used up" apart from "paid, but nothing available",
  and from "the AI Platform is unreachable".
- **FR-66** The clinic shows a short reference for its subscription that it can read out to support.

### 4.9 Vendor operations and support

- **FR-70** The operator can look up a clinic's subscription, payments, grants, provisioning state and
  live platform state in one place, without raw SQL.
- **FR-71** The operator can retry a stuck provisioning, record a chargeback, grant complimentary
  time, and cancel an open checkout.
- **FR-72** Because there are no refunds, the operator can move a clinic's remaining paid time and
  allowance to a new identity for the same clinic, for example if its tenant or platform identity
  has to be re-created. The move is attributed, and the old identity loses the time. [Assumed]
- **FR-73** Every operator action is attributed to a named person and audited.
- **FR-74** The operator can stop abuse (suspend a clinic's AI) independently of billing, and doing so
  never grants service.

### 4.10 Reconciliation

- **FR-80** Every provider payout traces to a recorded payment. Every recorded payment traces to a
  grant. Every platform grant traces to a payment or an attributed complimentary grant.
- **FR-81** Drift is detected automatically and reaches the operator as a notification, not only as
  a stored row.
- **FR-82** Missed or lost provider notifications are found and recovered automatically, within
  minutes rather than days.

### 4.11 Launch

- **FR-90** Launch requires every requirement in this document to be implemented and every
  acceptance scenario in §11 to pass in staging. [Decided]
- **FR-91** At launch, today's manual paths are removed: the shared operator bearer token, manual
  entitle, and manual flag flips. No bypass of the ABO remains in production. [Decided]
- **FR-92** Production starts with no carried-over entitlements. Pre-launch test and pilot clinics are
  purged or re-enrolled. Any pilot clinic that must keep AI gets an attributed complimentary grant
  ending 30 days after launch, with reason "pre-launch pilot", and then buys like everyone else.
  [Assumed]

## 5. Security requirements

### 5.1 General

- **SR-01** No client, internet caller, or holder of a leaked credential can create or extend AI
  service without payment. [Decided]
- **SR-02** Provider notifications are verified as authentic, and each distinct payment state change
  is processed exactly once.
- **SR-03** A payment for clinic A can never grant service to clinic B. Every billing request is
  bound to the clinic (tenant) of the authenticated owner or administrator making it. A user who
  belongs to several clinics acts for exactly one of them per request.
- **SR-04** Nobody can block or hijack another clinic's purchase or billing relationship just by
  knowing its identifier.
- **SR-05** Every grant the platform accepts carries evidence that the platform can verify and keep,
  so tampering with either store is detectable.
- **SR-06** There is no shared or unattributed operator credential anywhere on the control surfaces.
- **SR-07** Clinic users (owners, administrators, staff) reach the shared backend only through the
  app's roles and functions. None of them can read the credentials used to act for their clinic,
  set the AI flag or subscription status directly, or reach any billing credential. [Decided]
- **SR-08** Tenant isolation covers billing too. A clinic's subscription status, allowance, notices
  and payment history are visible only to that clinic's users. No clinic's action can change another
  clinic's entitlement, even under a bug in one clinic's request.
- **SR-09** The ABO and the AI Platform hold no credentials that can read or write the shared
  database. Only the developer's own administrative access can, and it is kept separate from the
  billing and AI services. One database holds every clinic's clinical data, so a compromise of
  either service must not reach it. No messages pass between the shared backend and the ABO or
  the AI Platform (C-02). The backend's only part in billing and AI is the short-lived,
  single-purpose credentials it issues to desktops.
- **SR-10** No payment-provider data is stored in the shared backend, and no card data anywhere.
  Provider identifiers stay inside the provider integration boundary.
- **SR-11** Signing keys and service credentials can be rotated, and a compromised one revoked,
  without a service outage and without a multi-day wait.
- **SR-12** The threat model is stated honestly:
  - The developer controls every component, so it does not claim protection against the developer.
  - It names what each of these can do: a leaked developer credential, a compromised ABO, a
    compromised AI Platform, and a compromised shared backend (which can act for every clinic at
    once).
  - It treats clinic users and internet callers as the untrusted parties.

  [Decided]
- **SR-13** The "AI available" flag is a UI convenience. The design must not depend on it for
  security.

### 5.2 Complimentary-grant authority

These properties let one person hold grant authority safely (FR-38). [Decided; mechanisms left to
the design]

- **SR-20** Grant authority belongs to a named human identity only. It requires phishing-resistant
  multi-factor authentication (passkey or hardware key) and short-lived sessions.
- **SR-21** No long-lived token, API key, CI secret, deploy credential, or service-to-service binding
  can issue a complimentary grant by itself. A leaked machine credential or config file is not
  enough.
- **SR-22** The grant surface is not reachable from the public internet without passing the identity
  layer.
- **SR-23** Every grant immediately sends an out-of-band alert to the developer (outside the operator
  console) and appears in the daily digest, so a grant made with stolen access is noticed within
  minutes.
- **SR-24** Grants have configurable ceilings: maximum length and allowance per grant, and total per
  clinic per period. Going over a ceiling needs a deliberate, separately alerted override.
- **SR-25** Grant authority can be revoked at once, and every grant made during a suspected
  compromise can be listed and voided.

## 6. Reliability and operational requirements

- **NFR-01** A received payment is provisioned automatically. Every transient failure path (crash,
  timeout, platform outage of any length, bad deploy) eventually heals without manual data repair.
- **NFR-02** Retries and repeated scheduled runs are harmless. No duplicate charges, grants,
  checkouts or notifications.
- **NFR-03** The ABO and the platform agree on a clinic's state through one idempotent grant
  operation. "Already done" responses can be told apart from real failures.
- **NFR-04** Failures that need a human reach the developer by push notification within minutes. A
  daily digest proves the scheduled jobs are alive.
- **NFR-05** A stale platform cache or an ABO outage never keeps a lapsed clinic active past its
  grace. A just-paid clinic is not left waiting behind a stale cache for long.
- **NFR-06** Usage is counted against the allowance of the term it happened in. It is never
  double-counted, never lost, and never charged to a prepaid term before that term starts.
  Exhaustion is detected on the request that uses the last of the allowance, not later by a batch
  job. [Decided]
- **NFR-07** The whole lifecycle can be run end to end in staging in real time, using short test
  offers with small allowances. It covers:
  - purchase for every term length;
  - early renewal;
  - lapse, grace and reactivation;
  - allowance exhaustion, with and without a prepaid term;
  - duplicate payment;
  - reversal.
- **NFR-08** The operating cost and the moving parts are proportionate to a few orders per day and
  one operator.
- **NFR-09** Every request between the desktop app, the shared backend, the ABO and the AI Platform
  carries a contract version, and every response states the version it answers in. Each receiver
  accepts the current and the previous version, so any side can deploy first, and it refuses other
  versions with a distinct answer instead of guessing. A desktop too old to talk to a service shows
  an "update the app" state, never an error dialog.

## 7. Records and retention

- **RC-01** Payments, reversals and grants are append-only facts. Nothing commercially meaningful is
  ever overwritten.
- **RC-02** Raw verified provider notifications are kept as evidence.
- **RC-03** Payment and grant records are never deleted until a retention policy is set. A durable
  off-database copy survives accidental deletion or a bad restore. [Assumed]
- **RC-04** The billing state can be rebuilt after a loss from the provider records, the platform
  grant records and the off-database copy, following a documented procedure.
- **RC-05** Deleting or purging a clinic on the platform never destroys the records of what was
  granted and paid.
- **RC-06** Before launch, legal counsel confirms that a no-refund policy for prepaid digital
  services is compatible with Egypt's Consumer Protection Law (No. 181 of 2018). The terms shown at
  checkout match that advice.

## 8. Constraints and givens

### 8.1 Environment

- **C-01** The AI Platform already exists as a Cloudflare Worker with D1 and a per-clinic Durable
  Object for strongly consistent usage counting. Clinics are identified by Ed25519 installation keys,
  and clinic-signed access tokens authenticate AI requests. Its control surface and identity model
  may be reworked for the ABO (§8.2).
- **C-02** All clinics share **one** remotely hosted Supabase project owned by the developer, with one
  auth service. Clinics are tenants inside it, and branches sit within a clinic. [Decided] The shared
  backend holds clinic data only and talks only to the desktop app. It makes no outbound calls to
  the ABO or the AI Platform, and they never call it. Anything the vendor services need from it
  travels through a desktop, as a credential it issued. [Decided] SR-09 limits what the billing and
  AI services may hold.
- **C-03** The clinic backend is never on a clinic PC or LAN. [Decided] A desktop reinstall does not
  change a clinic's identity. Clinic users cannot touch the database outside the app's roles and
  functions.
- **C-04** The desktop app is Flutter on Windows. Several desktops per clinic and several branches are
  normal. With a remote backend, a clinic that loses internet loses the whole app, not just AI. So
  "AI Platform unreachable" matters mainly when Cloudflare is down but Supabase is up.
- **C-05** The first provider is Paymob (Egypt, EGP), with these properties:
  - Hosted checkout and HMAC-signed transaction notifications.
  - Refunds and voids arrive as child transactions of the original payment.
  - No reliable chargeback notification.
  - Payment intentions expire and cannot be cancelled once created.
  - Checkout requires buyer billing data (FR-51).
- **C-06** The vendor runs on one Cloudflare account plus the Supabase hosting, all owned by the
  developer, who is the only operator.
- **C-07** The ABO is a separate deployable from the AI Platform, so payment secrets and provider
  traffic stay out of the AI request path and deploys and faults stay isolated.
- **C-08** Volume is a few orders per day, and clinics are small to mid-size.

### 8.2 Current AI Platform gaps

These facts about today's AI Platform code conflict with the requirements above. The design must
close each one.

| # | Current behaviour | Conflicts with |
|---|-------------------|----------------|
| P-01 | An entitlement carries period start and end dates, but nothing stops service when the end date passes. There is no date-based expiry and no grace handling. | FR-22, FR-23, NFR-05 |
| P-02 | An entitlement can be activated only from `pending`; any later grant to an active or previously active clinic is rejected with `409 not_pending`. | FR-21, FR-24, FR-37, FR-41, NFR-03 |
| P-03 | Usage counters reset whenever the entitlement's period dates change, and each period is a single span. There is no notion of a current term plus prepaid terms, and exhaustion does not end a term or start the next one. | FR-07, FR-21, FR-33, NFR-06 |
| P-04 | Plan tiers are a fixed list in code, so a new plan needs a deploy. | FR-01 |
| P-05 | The streaming path passes a hardcoded maximum cost class of `premium` to routing, so plans cannot differ by cost class there. | FR-16 |
| P-06 | Installation keys expire 365 days after enrollment. | FR-25, SR-11 |
| P-07 | Control operations authenticate with one shared operator bearer token. | SR-06, SR-20, SR-21, FR-91 |
| P-08 | Configuration reads are cached for up to 30 seconds. | NFR-05 |
| P-09 | Clinic-facing routes cover capabilities, usage and requests only. None lists plans or reports a clinic's entitlement status. | FR-05, FR-60, FR-65 |
| P-10 | Clinic identity is built on per-clinic installation keys and clinic-minted access tokens, a model made for clinics that each run their own backend and signing secret. With one shared backend and one auth service, the platform could trust that service directly. | C-02, SR-09, SR-11 |

## 9. Product decisions

| Decision | Status |
|----------|--------|
| Launch only when the whole ABO is implemented; no manual-selling phase | Decided |
| Renewals are paid manually; no saved card, no automatic charges | Decided |
| Monthly, quarterly and annual terms at launch; offers are data, never hardcoded | Decided |
| Prices are final; nothing is added at checkout | Decided |
| The provider sits behind a provider-neutral interface; Paymob is the first implementation | Decided |
| No refunds at launch; reversals the vendor does not initiate are still handled | Decided |
| One usage allowance per term, usable at any pace; no monthly allocations | Decided |
| No mid-term plan or term changes while allowance remains; changes apply at the next term | Decided |
| Using up the allowance ends the subscription early, with no grace and no refund; the clinic may then buy any current offer, and the new term starts at payment | Decided |
| Notices are in-app only; staff see them too, with no payment details | Decided |
| One operator may grant complimentary access alone, protected as in §5.2 | Decided |
| Desktops read AI status from the AI Platform; staff desktops never contact billing | Decided |
| All clinics share one remotely hosted Supabase project owned by the developer | Decided |
| The shared backend talks only to the desktop app; it never calls, and is never called by, the ABO or the AI Platform | Decided |
| Every grant traces to a payment or an attributed vendor grant; no exceptions | Decided |
| A full reversal of the current term's payment ends service immediately, with no grace | Decided |
| Initial grace period is 7 days after a term's end date | Decided |
| No provider SDK or card data in the app; hosted checkout in the system browser | Decided |
| The AI Platform is the only enforcement point | Decided |
| Duplicate payments become more paid time (follows from no refunds) | Assumed |
| Leftover allowance expires at the term's end date; no carry-over | Assumed |
| Cost-safety limits stay separate from the allowance and never end a subscription | Assumed |
| A prepaid term starts immediately when the current term's allowance runs out | Assumed |
| Pilot clinics get a 30-day complimentary grant from launch; no other carry-over | Assumed |

## 10. Design parameters

No product questions are open. The design sets these values:

- Renewal notice lead time before a term's end date.
- Low-allowance warning threshold (FR-34).
- Freshness bound for the flag and status (FR-63).
- Complimentary-grant ceilings (SR-24).
- Values for the cost-safety limits (FR-09).
- Maximum allowance overshoot when concurrent requests use the last of it (A34).

## 11. Acceptance scenarios

The design must answer every scenario below with a defined, tested outcome. Passing all of them in
staging is the launch gate (FR-90).

| # | Scenario | Required outcome |
|---|----------|------------------|
| A1 | First purchase, happy path, for each of monthly, quarterly and annual | AI on within about a minute of payment; payment in history; the full term allowance is available |
| A2 | Owner pays, then closes the app before confirmation | Provisioned anyway; every desktop shows active on next open |
| A3 | Provider notification lost or delayed | Payment found and provisioned automatically within minutes |
| A4 | Platform down for 4 days after a payment | Provisioned automatically when the platform returns; developer alerted meanwhile |
| A5 | Card declined, then retried successfully on the same page | Granted once; no cancelled order |
| A6 | Owner pays twice for the same term | Both recorded; the second becomes the next term; owner and developer told |
| A7 | Owner opens a monthly checkout, switches to annual, then pays the stale monthly tab | Monthly granted at the monthly price; nothing misattributed |
| A8 | Price changes between opening a checkout and paying | The price shown in that checkout is what gets charged and granted |
| A9 | Renewal paid 5 days early | No lost days; the current term's allowance is unchanged; the new allowance starts with the new term |
| A10 | Term reaches its end date unpaid | Grace applies; AI stops at grace end even if the ABO is down |
| A11 | Lapsed clinic pays 2 months later | Reactivated automatically; new term from the payment date |
| A12 | Owner renews from a different branch desktop or after reinstall | Works with no vendor contact; same clinic identity |
| A13 | The credentials the shared backend uses for a clinic were rotated since the first purchase | Renewal works |
| A14 | A clinic's platform identity must be re-created while it has paid time | Operator moves the remaining time and allowance to the new identity; attributed; old one loses it |
| A15 | Chargeback on the payment funding the current term | Recorded; access ends now; developer alerted |
| A16 | Someone refunds a payment from the provider dashboard despite the no-refund policy | Recognised as a reversal, never as a payment; handled as in FR-43; developer alerted |
| A17 | Chargeback on an old payment | Recorded; no service effect |
| A18 | Chargeback found only in the payout report | Recorded manually by the operator; access ends; reconciliation clean |
| A19 | Trial clinic converts to paid | Self-service; no gap and no double coverage |
| A20 | Operator grants a 2-week extension to a paying clinic | Applied; attributed; out-of-band alert sent; visible in reconciliation |
| A21 | Plan retired while clinics are on it | They keep it until their term ends; must choose a current offer to renew |
| A22 | Someone who knows a clinic's identifier tries to order for it | Cannot block or hijack the clinic's billing |
| A23 | Provider changes a notification field and verification starts failing | Developer alerted within the hour; payments recovered by inquiry |
| A24 | Clinic deleted on the platform while it still has paid time | Developer alerted; records retained; paid time movable per FR-72 |
| A25 | A credential the shared backend uses for a clinic reaches its expiry while the clinic is paying | No paid-but-broken state; rotated automatically or the developer is warned in time |
| A26 | A deploy secret or CI token leaks | It cannot issue a complimentary grant or extend service |
| A27 | Operator session is hijacked and used to grant a year of access | Stopped by the grant ceiling or surfaced within minutes by the out-of-band alert; grants listable and voidable |
| A28 | Term nears its end date while only staff use the app | Staff see "AI ends in N days, ask your administrator"; no prices or purchase actions; after lapse, AI shows unavailable within the FR-63 bound; no staff desktop contacts billing |
| A29 | Annual buyer uses 90% of the allowance by month 3 | Low-allowance warning shown to owners, administrators and staff; service continues |
| A30 | Annual buyer with allowance left tries to upgrade at month 5 | Offered only as a change for the next term; nothing charged or changed now |
| A31 | Annual buyer uses up the allowance at month 4, with no prepaid term | AI stops on that request; subscription ends; no grace; owner buys any current offer; new term and allowance start at payment; the remaining 8 months are forfeited |
| A32 | Monthly buyer prepaid next month, then uses up the allowance on day 20 | Prepaid term starts immediately with its full allowance; its end date is 1 month from day 20 |
| A33 | Clinic on a retired plan uses up its allowance | Retired plan not offered; owner picks from current offers |
| A34 | Allowance is used up by two concurrent requests near the limit | Exhaustion recorded once; overshoot within the design bound; no double early end |
| A35 | The ABO or the AI Platform is compromised | The attacker gains no read or write access to the shared database |
| A36 | A bug or crafted request in clinic A's session targets clinic B's billing | Rejected; clinic B's status, allowance and payments are unchanged and not visible |

## 12. Glossary

| Term | Meaning |
|------|---------|
| Clinic | A tenant in the shared backend; the billing and entitlement subject; may have several branches and desktops |
| Offer | A sellable combination of plan, term length, price, allowance and grace policy |
| Plan | The AI Platform's definition of what AI a clinic gets (capabilities, cost class, limits) |
| Term / coverage | The paid (or complimentary) span during which a clinic is entitled to AI; ends at its end date or when its allowance is used up, whichever comes first |
| Allowance | The usage a term includes, available from the term's first day |
| Exhaustion | The allowance being fully used; ends the term early with no grace |
| Grace | Time after a term's end date during which service continues unpaid |
| Lapse | The state after grace ends with no new term |
| Complimentary grant | A vendor-issued, attributed, zero-price term (trial, goodwill, correction, pilot) |
| Reversal | A chargeback, void or refund applied to a specific payment; at launch, never initiated by the vendor |
| Developer | The vendor: sole owner and operator of the shared backend, the ABO and the AI Platform |
