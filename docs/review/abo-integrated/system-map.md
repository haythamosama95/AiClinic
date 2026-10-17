# ABO review system map

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. R0 inventory, 2026-10-16 Africa/Cairo. This is reference-derived navigation, not a correctness conclusion.

| Store | Authority | Copies / consumers |
| --- | --- | --- |
| Supabase/PostgreSQL | Tenancy, memberships, token issuance | Desktop sessions; non-exposed `ai_internal` coverage projection is display only |
| ABO D1 | Offers, contacts, checkout/payment/reversal/grant-request facts | Locked R2 NDJSON ledger; contacts stay outside ledger |
| ABO R2 | Raw provider evidence | D1 stores hashes; rebuild/export consumers |
| Platform D1 | Tenant bindings, issuer/operator keys, plan versions; usage events | Usage rollup; registries consumed by token/API verification |
| Per-clinic SQLite DO | Terms, grants, counters, reservations | D1 grant ledger/mirror/events and R2 grant ledger are copies |
| Backend `ai_internal` | Feed-derived display projection | Status RPC, desktop state; never coverage authority |

Credential boundaries: Supabase user sessions stay in the desktop/backend channel; backend Ed25519 issuer keys sign separate AI (600s), billing (300s), and feed (120s) profiles. Platform and ABO keep only registered issuer public keys. ABO has Paymob secrets and its grant key; platform has receipt signing keys. Human control methods verify forwarded Access identity at the platform; HP methods additionally bind a passkey assertion to the canonical operation. Neither vendor service may receive Supabase credentials or a clinic-domain write path.

Principal flows:
1. Active-org/membership -> backend token RPC -> SQL signer -> AI/vendor or ABO verifier -> issuer/org tenant binding (R1).
2. Versioned request -> auth -> canonical operation/assertion -> replay gate -> dispatch (R2).
3. Administrator offer/contact -> checkout -> provider callback evidence -> authenticated inquiry -> confirmed payment (R3).
4. Confirmed payment or authorized grant -> immutable envelope -> platform grant -> DO coverage -> matching receipt (R4).
5. AI principal -> reserve/admit -> provider outcome -> settle/release; mirror fallback -> drain (R5).
6. Reversal/value reduction or transfer/delete -> lineage/epoch changes -> delayed work safety (R6).
7. DO event -> platform feed -> backend cursor/projection -> read-time status -> role-specific desktop (R7).
8. Operator UI -> exact method authority/policy -> audit/config mutation (R8).
9. Durable fact -> export/rebuild/reconciliation/alerts; cron and executable source guards (R9).

Version channels: desktop/ABO clinic and console use `Abo-Contract-Version`; desktop/platform and backend/feed use `Aip-Contract-Version`; RPC uses `p_contract_version`; binding and DO RPC use `contract_version`; tokens use `ver = "2"`; stored signed payloads retain their original version. Receivers must gate before authentication/mutation and echo accepted request versions. Detailed behavioral verification belongs to R2 and each consumer phase.

Dependency order: R0 -> R1 -> R2 -> R3 -> R4 -> R5 -> R6 -> R7 -> R8 -> R9 -> R10. Later phases read preceding compact handoffs and actual source at unresolved seams. No phase after R1 is executed by this assignment.
