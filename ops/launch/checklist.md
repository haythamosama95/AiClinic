# Launch checklist (section 5 D3)

## 1. Legal and tenancy

**Owner:** developer

RC-06 legal confirmation of the no-refund policy, and R-9 advice on payer contact data and erasure timing (01 §7). These are launch conditions (05 §6.2). The tenancy retrofit (01 R-1) is live, and RC-06 legal confirmation is recorded (01 R-9). R-9 advice on payer contact data is recorded, and the erasure action (§3.2) has been run once in staging.

## 2. Operating policy

**Owner:** developer

02 §4.4 operating policy: production deploys and secret changes only from an interactive session with hardware-key MFA; no stored token with production rights. This checklist is the P8.3 check. The audit watcher (P8.1) detects breaches. A26 stays Partial.

## 3. IdP and Access

**Owner:** developer

IdP hardware-key MFA and 1-hour Access sessions (TB-7, K-8): Access configuration is in P8.1, verified by this checklist.

## 4. Launch runbooks

**Owner:** developer

Production key generation and registration, bootstrap and second credential, pilot grant (FR-92), and deletion of pre-launch installations: the P8.3 runbooks, run at launch.

## 5. Paymob dashboard

**Owner:** developer

Paymob dashboard settings (callback URLs, integration ids) and HMAC/API key rotation in the dashboard: P8.1/P8.3 runbooks. HMAC and API key rotation follow FR-007 and FR-008 (K-5, K-6).

## 6. Plan allowance and D1 Time Travel

**Owner:** developer

NFR-08 plan-allowance confirmation (05 §7) and D1 Time Travel (a built-in feature): recorded in P8.1.

## 7. Monthly payout CSV import

**Owner:** developer

FR-80 monthly payout CSV import: a routine operator action (05 §10), supported by P4.10.
