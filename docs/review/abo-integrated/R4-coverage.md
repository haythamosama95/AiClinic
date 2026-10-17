# R4 source coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. 2026-10-17 Africa/Cairo.

**Complete with findings: all 148 manifest regions / 4,011 primary inclusive lines covered; zero unread R4 regions.** Every source reviewer and synthesis context was explicitly GPT-6.1 Sol/high. Initial unpinned work receives no credit.

| Reviewer | Explicit setting | Ownership / actual coverage |
| --- | --- | --- |
| abo_r4_high (coordinator/synthesis) | gpt-6.1-sol / high | ABO 1,286 primary lines; [actual ranges](R4-abo-high-coverage.md) / [JSON](R4-abo-high-coverage.json) |
| platform_grants_high | gpt-6.1-sol / high | Platform entrypoint/schema 1,227 primary lines; [actual ranges](R4-platform-high-coverage.md) / [JSON](R4-platform-high-coverage.json) |
| do_lifecycle_high | gpt-6.1-sol / high | DO/calendar 1,498 primary lines; [actual ranges](R4-do-high-coverage.md) / [JSON](R4-do-high-coverage.json) |

Each manifest row was checked against its named reviewer’s actual source intervals. [Aggregate JSON](R4-coverage.json) retains every exact row, owner, setting and status. Supporting interval reads are listed separately in those records and do not complete future-phase algorithms. Reports: [canonical](R4-grants-coverage-term-lifecycle.md), [ABO](R4-abo-high-review.md), [platform](R4-platform-high-review.md), [DO](R4-do-high-review.md).

## Escalation dispositions (20)

| ID | Source producer/consumer disposition |
| --- | --- |
| 067:2 | Closed R4 producer/receiver: ABO finite active-key gate and signed current key; platform registry/validity/JWS verification. Registry administration remains R2/R8; deployment rotation R9. |
| 067:3 | Publish content immutable and same-content idempotent; retire status only; DO immutable snapshot copied. Completed replay blocked by retirement is included PG1; new retired-plan application remains refused. |
| 067:4 | DO queued ascending unheld+undated, recent descending max12 and live hot.used versus used_final verified. Full read/display freshness R7, with named readCoverage seam. |
| 067:5 | Actual listGrants inclusive filters/order/row receipt object and ABO grouping read. PG4 falsifies credential attribution and PG1 can mask duplicate application; no full R8 query UX review claimed. |
| 067:6 | Outbox writes D1 then distinct per-grant R2 NDJSON before row deletion; shape matches. PG1 duplicate-key silence and D4 lost wakeup qualify durability. Rebuild/lock attestation R9. |
| 067:7 | Paid event order term_ended→term_activated→grant_applied established; receipt uses last sequence. Current per-event snapshots reflect intermediate states rather than required final post-grant state: D1 pure final-plan recipe explicitly covers final-state snapshots with each event sequence. R7 validates consumers/page boundaries. |
| 067:8 | Actual canonical JWS signer and ledger_seq=grant_applied clinic_seq; DO stores original receipt and copies it verbatim. ABO signature-only acceptance and complimentary context mismatch are A2. D1/D4 qualify receipt-to-state durability. |
| 067:9 | Published capability array copied into entrypoint snapshot; DO stores JSON and term/admission consumer reads capability/cost/concurrency. No reinterpretation at activation; full admission R5. |
| 067:11 | Nonempty approvals enforced by shared validator and paid receiver. Paid empty list returns approvals_required; complimentary generic invalid-envelope path currently returns unit_not_allowed. The rejection prevents value; bounded error-code deviation retained for R8 contract consistency, not an additional major/moderate finding. |
| 067:12 | Reference-only transcription instruction; amended current rule used. No test/workflow correctness analysis. |
| 068:1 | Complete calendar and grant/boundary callers verified: UTC month clamp/leap behavior, exact day units, staging replacement lengths. Harness instructions excluded. |
| 069:1 | Reference-only test-clock/harness instruction; no excluded test/harness source analyzed. Production override isolation remains R9. |
| 070:1 | Greatest policy version passed to DO, per-grant arithmetic and strict-lower/inclusive-upper 90-day window source traced; D5 installation-local history violates per-org ceiling. R2-P2 owns second-assertion binding; full policy administration R8. |
| 073:1 | Actual queued/recent field mapping matches amended lists and hot/used_final selection; API-to-desktop freshness stays R7. No new grant mutation rule. |
| 079:1 | ABO constructs one paid grant operation with base envelope sans approvals, empty actor, paid_at, deterministic nonce/version; shared acceptance and machine signature receiver traced; no WebAuthn requirement applied to paid path. |
| 079:2 | Live getCoverage snapshot/fallback and notice producers read; checkout outcome maps success to Active. Upstream R3 has payment DTO lineage coverage; complete payment-history/desktop business semantics remain R7. No inferred full R7 review. |
| 079:4 | Paid unverifiable signature parks+AL07 without outcome; complimentary receipt path lacks matching/verification, A2. Missing object paid response currently retries; selected identity/receipt fix routes unverifiable/missing success to parked recovery. |
| 079:6 | Shared validator accepts paid operation-object shape without credential/assertion and complimentary string-shaped evidence. Actual HP signer remains distinct; PG4 owns false credential lineage. Exact paid producer shape verified. |
| 083:1 | Identifier helper, bounded ABO package loop and DO import loop use index0..k-1 and one deterministic request/import per element. Full transfer recovery R6; PG1 global original-grant replay boundary is established here. |
| 085:1 | Bounded checkReceiptMismatch reads every successful nontransfer outcome, flags absent listGrants row, canonical-compares full receipt including signature. DO→D1/R2 copies traced; complete reconciliation scheduling/rebuild remains R9. |

## Closure and limits

All assigned primary source, directly necessary callers/receivers and shared grant/receipt business uses are closed. No tests/testkit/vectors/harness/campaign/viewer correctness review, tests/builds/lint/service operations, provider research or application source edits. Coordinator accidentally displayed append.ts fixture-helper declarations 35–80 while reading1–80; only production insertFactLog 1–27 was analyzed and excluded declarations were not evidence. Old R4-platform-subreport/coverage are retained, explicitly superseded and not credited.

Static source cannot attest deployment credentials, account permissions, bucket locks, actual alarms or live provider behavior. Existing ambiguous/corrupt historical rows require authoritative receipt/audit reconciliation; code recipes fail closed rather than selecting a winner. R5–R10 remain not started. R0–R3 canonical states preserved without retrospective effort assertions.
