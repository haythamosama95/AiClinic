# R4 platform explicit-high coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. 2026-10-17 Africa/Cairo. GPT-6.1 Sol, explicitly configured **high** reasoning effort.

**Bounded status: complete with findings.** No owned source region remains unread. All finding recipes are saved; coordinator integration/deduplication is the only remaining handoff. Prior unpinned R4 reports were not used as completed read evidence. This does not claim whole-R4 completion.

Assigned primary source actually read: **1227 inclusive lines**. Supporting intervals are dependencies, not additional primary ownership. See [machine coverage](R4-platform-high-coverage.json).

## Primary actual read ranges

| Path | Inclusive lines at T |
| --- | --- |
| `ai-platform/src/vendor/entrypoint.ts` | 157–170, 370–450, 532–547, 603–675, 1452–1518, 1594–1638, 1842–1857, 2766–2998, 3113–3704 |
| `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql` | 1–90 |

## Supporting actual read ranges

| Path | Inclusive lines at T |
| --- | --- |
| `ai-platform/src/vendor/entrypoint.ts` | 1–145, 174–229, 451–531, 548–602, 676–710, 765–854, 865–1451, 4391–4453, 4597–4665 |
| `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` | 1–41 |
| `packages/vendor-contracts/src/grant-envelope.ts` | 1–372 |
| `packages/vendor-contracts/src/receipt.ts` | 1–182 |
| `packages/vendor-contracts/src/operation.ts` | 1–65 |
| `packages/vendor-contracts/src/version.ts` | 1–43 |
| `packages/vendor-contracts/src/identifiers.ts` | 70–97 |
| `ai-platform/src/quota-do/coverage.ts` | 512–542, 1207–1327, 1575–1668, 1825–1858, 2007–2034, 2664–2753, 2790–2820, 3000–3035, 3140–3260 |
| `ai-platform/src/quota-do/index.ts` | 1922–1980 |
| `ai-platform/src/worker.ts` | 1785–1905, 2515–2603 |
| `ai-platform/src/coverage/transfer.ts` | 617–718 |
| `abo/src/work/grant.ts` | 400–495, 650–925 |
| `abo/src/ops/index.ts` | 2653–2723 |

These supporting reads establish the source effects used in the four findings; they do not claim full lifecycle, transfer/delete, scheduler, package/perimeter or ABO review. Migration-name searches found no later plan_version/grant_ledger/coverage_event/coverage_mirror definition overrides. HEAD matched T and the owned production paths had no diff from T. Reference reads: complete AGENTS.md and constitution, complete integrated review plan, R4 packet/manifest, R0 system map, complete R4 escalation entries, canonical R1/R2/R3 handoffs and inherited root recipes. Current amended architecture 03 §§1,2.8–2.9,3.1–3.3,5.3–5.4,5.7,6.1,6.3–6.4,6.7–6.8,7–8; 04 §§1.1–1.4,1.6; 05 grant failure modes; 02 authority/AD-8/AD-12/SR-25 supporting excerpts.

## Escalation dispositions (20)

| ID | Bounded producer/consumer result |
| --- | --- |
| 067:2 | Platform grant consumes named active, finite service-key validity and verifies exact signed payload; unknown kid transient. Producer/rotation registry canonical R2/R8; ABO signing gate coordinator. |
| 067:3 | Owned publish/retire paths fully read: content idempotence, conflict, status-only retirement, snapshot copy. Completed replay versus retirement conflict captured in PG1. |
| 067:4 | No additional vendor write-side rule; DO queued/recent producer lifecycle sibling and API/display consumers R7. Assigned platform write path closed. |
| 067:5 | Supporting listGrants filters and row/receipt output read; credential filter qualified by PG4; DO mirror identity qualified by PG1. |
| 067:6 | Actual D1-to-R2 shipping row shape read, grant object unchanged. PG1 captures silent duplicate identity masking. Rebuild consumer remains R9. |
| 067:7 | Vendor dispatch established; exact event ordering/application transaction sibling ownership. No lifecycle completion inferred here. |
| 067:8 | Actual DO signer fields/JWS receipt bytes and grant ledger-sequence source read; exact ordering sibling. ABO signature/outcome equality coordinator. No new crypto finding. |
| 067:9 | Owned plan snapshot object and capabilities copy checked at both grant branches; DO stores supplied JSON, later uses sibling/R5. |
| 067:11 | Shared validator and both vendor paths enforce nonempty approvals; paid exact approvals_required. Complimentary generic validator failure maps to unit_not_allowed; noted as bounded error-code mismatch, no value bypass. Exact absence case not a new major root. |
| 067:12 | Reference-only transcription instruction; no independent source effect or excluded implementation inspected. |
| 068:1 | Source calendar restore/import behavior is lifecycle sibling ownership; harness instructions excluded. No calendar coverage claimed by this subreview. |
| 069:1 | Reference-only test-clock sequencing; excluded test/harness implementation not inspected. |
| 070:1 | Vendor greatest-version policy read and fields passed to DO; rolling-window calculation/adjustment effects sibling/R6; second override remains canonical R2-P2. |
| 073:1 | Write-side plan snapshot stable; queued/recent payload producer lifecycle sibling and API/display R7; not inferred reviewed here. |
| 079:1 | Actual ABO paid operation approval builder400–475 read, shared acceptance and paid vendor consumer traced. No WebAuthn required; exact builder shape matches amendment. |
| 079:2 | No new vendor write-side rule. Subscription/payment live/fallback and payment-history consumer work coordinator/R7; source response shape not claimed by this subreview. |
| 079:4 | ABO actual unverifiable signature branch789–800 parks without outcome; signer/receipt handoff read. Receipt identity checking is coordinator finding; platform transport classification PG2. |
| 079:6 | Full shared grant-envelope validator read; paid operation-object approvals accepted; complimentary generic credential/assertion shape retained. Actual signer lineage mismatch PG4. |
| 083:1 | Identifier helper and DO transfer import zero-based loop/read supporting lineage confirm per-package deterministic IDs distinct from original grant; PG1 global replay consequence. ABO transfer request rows R6/coordinator. |
| 085:1 | listGrants original receipt mirror/source checked and PG1 discrepancy consequence. Actual receipt_mismatch reconciliation consumer R9; no reconciliation algorithm review claimed. |

## Closure and limits

Four independent major roots: PG1 global identity/routing and completed receipt replay; PG2 transport classified permanent; PG3 consumed approval without durable accepted command; PG4 unverified credential attribution. No P0 supported. R1-C2 and R2-P2/C2/C3 retain canonical ownership; R3-C5/C6 remain inherited input defects. Report contains exact ordered implementation-ready fixes, including pending-route sealing/CAS, original-receipt replay, durable accepted-command scheduling and historical attribution limits.

No owned coverage blockers. Parent owns aggregation and ABO receipt/action lineage; lifecycle sibling owns placement/calendar/grace/event atomicity. R6 must integrate global claim routing/seals with transfer/delete; R9 owns rebuild/retention and operational limits. No tests/builds/lint/services/provider research, source edits, commits or checkout operations were performed. Excluded implementation was not reviewed.
