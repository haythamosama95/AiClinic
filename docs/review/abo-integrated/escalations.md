# R0 escalation routing index

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`.

Inventory: **75 entries in 30 files**, IDs `<spec>:<entry>` (including `088b:1`). All entries have a question, exact recorded resolution, amended spans, producer/consumer trace, phase routing and disposition in [escalations.json](escalations.json). This inventory makes no source-correctness or successful-propagation claim.

Escalation reference text was read at the pinned target. Excluded implementation/test content was not read or run. `reference-only / excluded effect` means the entry changes only arrangement, assertions, grouping or historical workflow; runtime facts mentioned in its rationale remain context for the ordinary phase manifest. `reference-propagation` retains a spec/document re-transcription or provenance amendment and routes any named runtime obligations to their final consumers. Mixed entries preserve the executable production guard while excluding viewer/test scan effects.

Each JSON record preserves the source heading line at T and the original **Amended** text. `amended_paths` extracts explicitly named file paths; `amended_paths_sections` is authoritative for sections and entries reporting no architecture change. A spec-only amendment is retained as recorded, without silently upgrading it to an architecture amendment.

Future phases must trace both ends listed below; these are obligations to verify against final source. In particular, read 067:11 with 079:1/6 for paid approvals, 071:1/2/3 for pre-grant void receipts, 088:1–6 with 088b:1 and desktop consumers, and 067:1 with 095:1 for version rollout. 077:2 remains an external provider assumption; static source cannot establish that Paymob honors the expiry field.

## Count reconciliation

| Spec | Entries |
| --- | ---: |
| 066 | 10 |
| 067 | 12 |
| 068 | 1 |
| 069 | 1 |
| 070 | 1 |
| 071 | 3 |
| 072 | 1 |
| 073 | 2 |
| 074 | 2 |
| 075 | 2 |
| 076 | 2 |
| 077 | 2 |
| 078 | 1 |
| 079 | 6 |
| 080 | 3 |
| 081 | 3 |
| 082 | 1 |
| 083 | 1 |
| 085 | 1 |
| 086 | 2 |
| 087 | 2 |
| 088 | 7 |
| 088b | 1 |
| 089 | 1 |
| 091 | 1 |
| 092 | 1 |
| 093 | 1 |
| 094 | 1 |
| 095 | 2 |
| 097 | 1 |
| **Total** | **75** |

No escalation record exists at T for specs 061–065, 084, 090, 096 or 098. Their source remains subject to the main ownership inventory.

## Entry routing

| ID | Question/topic | Disposition | Owners | Producer → downstream consumers |
| --- | --- | --- | --- | --- |
| [066:1](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L5) | Issuer-key envelope and `public_key` | source-contract | R1, R2, R8 | Issuer registry register/revoke/list producers → backend key pins and ABO issuer-key console decoders |
| [066:2](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L15) | First installation row and the creation cap | source-contract | R1, R9 | Identity first-token insertion → tenant-binding epoch lookup, creation-cap count and rebuild records |
| [066:3](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L25) | Refusal of the 51st new-org creation | source-contract | R1, R7, R9 | Identity creation limiter → clinic HTTP unauthenticated mapping, desktop denial handling and AL-20 |
| [066:4](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L35) | Writer of `issuer_key.status = retiring` | source-contract | R1, R2, R8, R9 | Issuer-key retirement method → token verifier, ABO rotation relay and AL-13 audit/alert |
| [066:5](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L45) | Spec re-transcription | reference-propagation | R1, R2, R8 | Spec re-transcription of 066:1–4 → same registry, verifier and console consumers; no new design rule |
| [066:6](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L55) | Admission, capability, and entitlement after the cache and tier-helper rows | source-contract | R1, R5, R8 | Temporary cache/tier retention → final P3.4 admission/capability coverage readers and P3.10 table/control removals; review final replacements |
| [066:7](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L65) | E2e issuer credential cache and the version 2 seed | reference-only / excluded effect | R1, R2, R8 | Harness credential reset and assertion-seed expectations only; runtime rules are context, no new source amendment |
| [066:8](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L75) | Remaining e2e assertion values after the version 2 seed | reference-only / excluded effect | R1, R5, R8 | Harness/assertion repairs for version seed and platform-assigned installation IDs only |
| [066:9](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L103) | Replacement issuer kid reuses the operator credential | reference-only / excluded effect | R1, R2, R8 | Harness replacement signer uses existing credential; second-registration runtime policy remains unchanged |
| [066:10](../../../specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/escalations.md#L113) | SX-032 settled payload object | reference-only / excluded effect | R5, R9 | Harness waits for existing asynchronous R2 payload write; no production write rule changed |
| [067:1](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L5) | Worker → DO contract-version scenarios | source-contract | R2, R5 | Worker RPC version producer → DO accept/echo gate → Worker coverage_unknown refusal mapping |
| [067:2](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L15) | Service-key status, validity, and envelope | source-contract | R2, R4, R8 | Service registry register/revoke/list → ABO signer usability check and platform paid-envelope signature verification |
| [067:3](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L25) | Plan-version publish and retire | source-contract | R4, R8 | Plan publish/retire method → immutable plan snapshots, grant placement and console decoders |
| [067:4](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L35) | getCoverage queued and recent terms | source-contract | R4, R7 | getCoverage DO/state producer → platform coverage HTTP and ABO subscription/desktop queued/recent-term consumers |
| [067:5](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L45) | listGrants window and success envelope | source-contract | R4, R6, R8, R9 | listGrants query/envelope → console grant lookup, credential void workflows and reconciliation receipt reader |
| [067:6](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L55) | R2 grant-ledger object | source-contract | R4, R6, R9 | Grant/void ledger object writers → D1 grant_ledger/grant_void rebuild readers; grant and void objects remain distinct |
| [067:7](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L65) | coverage_event.kind | source-contract | R4, R5, R6, R7 | Grant/lifecycle/usage event producers → ordered feed, backend projection, ABO coverage view and desktop status |
| [067:8](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L75) | Receipt signature and ledger_seq | source-contract | R2, R4, R6, R7, R9 | Platform receipt signing and event clinic_seq → ABO verification/outcome, void handling and reconciliation/rebuild |
| [067:9](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L85) | Plan capabilities shape | source-contract | R4, R5, R7, R8 | Plan capabilities publisher → term.plan_snapshot copy → admission/capability and coverage-display readers |
| [067:10](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L95) | readCoverageEvents limit above 200 | source-contract | R2, R7, R9 | readCoverageEvents limit gate → feed pull pagination/refusal and cursor recovery consumers |
| [067:11](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L105) | Approvals minimum on every grant | source-contract | R2, R4, R6 | Grant approvals field producers → shared validator and platform validation step 1; read with later paid exception 079:1/6 |
| [067:12](../../../specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/escalations.md#L115) | Spec sentences that still contradict the amended spans | reference-propagation | R2, R4, R6, R7, R8, R9 | Spec re-transcription of 067:2–11 → same affected source consumers; no new design decision |
| [068:1](../../../specs/068-abo-p3-4-admission-settlement-against-terms/escalations.md#L5) | Missing `calendar.ts` before the T001 harness | source-contract | R4, R5, R9 | coverage/calendar.ts addDuration restoration → vendor paid placement and DO lifecycle consumers; staging scale production exposure belongs R9 |
| [069:1](../../../specs/069-abo-p3-5-term-boundaries-grace-renewal/escalations.md#L5) | First coverClinic clock and AAT expiry | reference-only / excluded effect | R4 | Test-clock setup and assertion expiry arrangement only; no production clock behavior amendment |
| [070:1](../../../specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/escalations.md#L5) | ceiling_policy columns, setCeilingPolicy, and the 90-day window | source-contract | R4, R6, R8 | setCeilingPolicy versioned writer → complimentary/adjustment rolling-window validation and paid grace-cap validation |
| [071:1](../../../specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/escalations.md#L5) | Void listing window, partial rejection, operator evidence, and the R2 void object | source-contract | R2, R6, R8, R9 | ABO reversal/console void arguments → platform partial/window/evidence validation → void ledger/R2 rebuild and list consumers |
| [071:2](../../../specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/escalations.md#L15) | Spec re-transcription of the amended void contract | reference-propagation | R2, R6, R9 | Void spec re-transcription including replay argument equality → same reversal, tombstone and rebuild consumers as 071:1 |
| [071:3](../../../specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/escalations.md#L25) | Tombstone receipt clinic ids and coverage event | source-contract | R2, R6, R7, R9 | Pre-grant tombstone receipt with nil clinic IDs and ledger_seq 0 → ABO reversal receipt consumer and rebuild; no coverage-event emission |
| [072:1](../../../specs/072-abo-p3-8-transfer-deletion-with-coverage-left/escalations.md#L5) | Transfer success results, package columns, and the early transferIn detail | source-contract | R2, R6, R7, R9 | beginTransfer/deleteInstallation/transferOut/In producers → saga retry, package import, receipt verification, binding/feed and rebuild consumers |
| [073:1](../../../specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/escalations.md#L5) | Fields of queued terms and the last 12 terms on `GET /v1/coverage` | source-contract | R4, R7 | getCoverage queued/recent terms → GET /v1/coverage → Flutter administrator coverage presentation |
| [073:2](../../../specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/escalations.md#L15) | Form of `subscription_ref` on `GET /v1/coverage` | source-contract | R7 | Platform org-derived subscription_ref → coverage HTTP, ABO subscription and desktop reference display consistency |
| [074:1](../../../specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/escalations.md#L5) | Plan catalogue behaviours in `plan-catalogue.test.ts` | reference-only / excluded effect | R8 | Plan-catalogue test remapping/deletion only; publish/retire result rules explicitly unchanged |
| [074:2](../../../specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/escalations.md#L15) | T027 e2e cases that stay versus cases that leave | reference-only / excluded effect | R8 | E2E case retention/remapping only; frozen platform method rules remain unchanged |
| [075:1](../../../specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/escalations.md#L5) | Dirty `.cursor/skills/abo-workflow/SKILL.md` during specify | reference-only / excluded effect | R9 | Historical dirty-tree workflow exception only; no runtime consumer |
| [075:2](../../../specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/escalations.md#L15) | Live entry point for the D1 `grant_ledger` / `grant_void` rebuild | source-contract | R2, R9 | Class-H ledger rebuild service-binding entry → R2 grant/void object reader → D1 rebuild, then separate snapshot refresh |
| [076:1](../../../specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/escalations.md#L5) | Unsupported-version body, cross-host rejection, and the ledger object key | source-contract | R1, R2, R3, R9 | Host/version gates and record exporter → clinic error/header decoders, cross-host callers and ledger replay reader |
| [076:2](../../../specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/escalations.md#L15) | How the daily cron observes a missing R2 bucket lock | source-contract | R9 | Daily lock check configured Cloudflare read API → enabled Indefinite ledger/ lock predicate → AL-16; failed API is explicit operational limit |
| [077:1](../../../specs/077-abo-p4-2-checkout-paymob-intention/escalations.md#L5) | Checkout billing-token jti and the Paymob return `v` | source-contract | R1, R2, R3, R9 | Billing JWT jti and checkout producer → immutable billing_token_jti fact; return URL v → browser-return version receiver and replay |
| [077:2](../../../specs/077-abo-p4-2-checkout-paymob-intention/escalations.md#L15) | R-2 intention expiry without a Paymob test account | external-assumption | R3, R9 | Paymob intention expiration=1800 sender → provider expiry assumed honored; checkout expiry and operational spike/launch limits. No live-provider verification in R0 |
| [078:1](../../../specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/escalations.md#L5) | Notify body cap, rate limit, and work-row lease | source-contract | R2, R3, R9 | Paymob notify ingress body/IP gate → evidence/work enqueue; runner lease take → retry/sweep recovery consumers |
| [079:1](../../../specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/escalations.md#L5) | Paid grant approvals element | source-contract | R2, R4 | abo/src/work/grant.ts paid operation-object approval producer → packages/vendor-contracts/src/grant-envelope.ts validateApproval → platform grant validation; no paid WebAuthn ceremony |
| [079:2](../../../specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/escalations.md#L15) | Subscription and payments response shape | source-contract | R3, R4, R6, R7, R9 | ABO subscription/payment response producers and live/fallback coverage readers → Flutter subscription/history/notices pagination; reversal producer supplies notices |
| [079:3](../../../specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/escalations.md#L25) | Subscription notice closed set | reference-propagation | R6, R7 | Spec closed-set notice re-transcription → ABO subscription notice producer and desktop notice consumer, retaining reversal workflow ownership |
| [079:4](../../../specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/escalations.md#L35) | Unverified grant receipt | source-contract | R2, R4, R9 | Platform grant receipt signer → ABO verifier → no grant_outcome on unverified receipt, parked work and AL-07 |
| [079:5](../../../specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/escalations.md#L45) | Subscription snapshot when the view row is missing | source-contract | R7 | ABO subscription live/fallback miss → successful null snapshot response → desktop null handling and omitted terms_held |
| [079:6](../../../specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/escalations.md#L55) | Paid operation-object approval validation | source-contract | R2, R4, R6 | Paid grant operation-object producer → shared validateApproval acceptance → platform paid grant; complimentary/transfer assertion consumers retain credential/assertion requirement |
| [080:1](../../../specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/escalations.md#L5) | FM-01 callback crash sweep | reference-propagation | R3, R9 | Failure-mode scenario reference added; underlying callback/work/sweep crash-recovery source remains R3/R9, no new scenario content inspected |
| [080:2](../../../specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/escalations.md#L15) | Full versus partial, and the reversal dedupe key | source-contract | R3, R6, R9 | Provider child/parent reversal normalization → cumulative fullness/dedupe key → reversal insertion and void eligibility consumers |
| [080:3](../../../specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/escalations.md#L25) | Per-minute provider-inquiry budget | source-contract | R3, R6, R9 | Shared inquiry-budget producer → confirmation/grant work, sweep and reversal inquiry callers; due work retained outside cap |
| [081:1](../../../specs/081-abo-p4-6-operator-console-access-perimeter-lookup/escalations.md#L5) | Class-H ABO `control_audit` write | source-contract | R2, R3, R8, R9 | ABO operator_action commit → recordOperatorAction class-H relay → platform control_audit; cancel/retry callers, auth and action_id dedupe |
| [081:2](../../../specs/081-abo-p4-6-operator-console-access-perimeter-lookup/escalations.md#L15) | Which unit implements and freezes `recordOperatorAction` | source-contract | R2, R8, R9 | P4.6 thin platform recordOperatorAction implementation → ABO console relay; preserve source ownership despite originating ABO-only unit |
| [081:3](../../../specs/081-abo-p4-6-operator-console-access-perimeter-lookup/escalations.md#L25) | `inspectCoverage` relay keeps the frozen actor check | source-contract | R2, R8 | ABO inspectCoverage Access JWT forwarding → platform frozen email authentication → clinic page terms/grants/reservations; no audit write |
| [082:1](../../../specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/escalations.md#L5) | Refusal code when the credential id is absent from the active list | source-contract | R2, R6, R8 | Platform active-only credential list → ABO HP credential lookup/refusal → operator value-change and transfer relay; platform own revoked code stays distinct |
| [083:1](../../../specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/escalations.md#L5) | Transfer `grant_id` index n | source-contract | R4, R6, R9 | Ordered transfer package → ABO zero-based deterministic per-term grant IDs/grant_request rows → platform transfer/grant lineage and recovery |
| [085:1](../../../specs/085-abo-p4-10-reconciliation-payout-import-findings/escalations.md#L5) | Receipt mismatch finding kind | source-contract | R4, R9 | ABO applied grant_outcome receipt and platform listGrants receipt → field-equality reconciliation → receipt_mismatch finding and AL-10 |
| [086:1](../../../specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/escalations.md#L5) | Housekeeping scheduled job | source-contract | R9 | 06:00 UTC scheduled handler → housekeeping retention deletes; commercial fact retention consumers remain untouched |
| [086:2](../../../specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/escalations.md#L15) | AL-13 operator-credential list | source-contract | R2, R8, R9 | ABO successful credential registration detail → stored last-seen credential triples → hourly active list comparison and AL-22; AL-13 announcement path |
| [087:1](../../../specs/087-abo-p5-1-issuer-key-custody-token-issuance/escalations.md#L5) | Backend issuer-key status and switch signing | source-contract | R1, R2, R8 | Backend private generate/switch issuer signing key → token minting signer → platform verifier registry statuses and ABO rotation console; no public switch RPC |
| [087:2](../../../specs/087-abo-p5-1-issuer-key-custody-token-issuance/escalations.md#L15) | Full-stack registerIssuerKey without the Vitest clock | reference-only / excluded effect | R1, R8 | Local full-stack Access/key bootstrap only; source/config/24-hour pending semantics explicitly unchanged |
| [088:1](../../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md#L5) | Per-tenant refresh clock and status RPC refusals | source-contract | R1, R2, R7, R9 | Role-checked status_refresh RPC clock/upsert → immediate pull and projection → desktop success/rate/role handling; singleton feed cursor remains separate |
| [088:2](../../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md#L15) | Notice record fields | source-contract | R7 | Status RPC notice objects and floored grace days → Flutter member and billing-status notice decoders/presentation |
| [088:3](../../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md#L25) | Term days_left | source-contract | R7 | Projection ends_at and PostgreSQL read-time now → days_left/null computation → desktop ends-soon display; grace days separate |
| [088:4](../../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md#L35) | Status reason | source-contract | R7 | Feed snapshot.reason → clinic_ai_coverage upsert → read-time suspension/clock reason mapping → desktop reason decoder |
| [088:5](../../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md#L45) | Billing status plan, dates, and allowance figures | source-contract | R7 | get_ai_billing_status flattened projection fields → Flutter billing state and allowance-minus-used display including null/negative result |
| [088:6](../../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md#L55) | Snapshot contract_version on the projection | source-contract | R2, R7, R9 | Accepted versioned snapshot → flattened versionless backend projection → request-version RPC result; platform mirror/ABO coverage_view retain version |
| [088:7](../../../specs/088-abo-p5-2-coverage-feed-puller-status-projection/escalations.md#L65) | Task-cap split into P5.2a and P5.2b | reference-propagation | R7, R9 | Delivery split provenance only: P5.2a feed/refresh → P5.2b read-time status/notices → P6.1 desktop; preserve combined final ownership |
| [088b:1](../../../specs/088b-abo-p5-2b-read-time-status-notices/escalations.md#L5) | Status view as_of | source-contract | R7 | PostgreSQL status read-time now() → shared status/billing as_of field → Flutter freshness/time presentation, including missing projection |
| [089:1](../../../specs/089-abo-p6-1-desktop-contract-versions-token-minting/escalations.md#L5) | Coverage codes that refresh status | source-contract | R5, R7 | AI allowance_exhausted/coverage_lapsed/coverage_unknown denial producer → Flutter get_ai_status refresh trigger and refreshed status consumer |
| [091:1](../../../specs/091-abo-p6-3-administrator-billing-offers-contact-checkout/escalations.md#L5) | Checkout read JSON fields | source-contract | R3, R7 | ABO checkout detail/open-list JSON producer → Flutter checkout polling/resume/reference parsing and shown-state display |
| [092:1](../../../specs/092-abo-p6-4-administrator-subscription-payment-history-notices/escalations.md#L5) | H-FS late payment and thirty payments | reference-only / excluded effect | R7 | Local checkout fixture backdating/cancellation and 30-payment arrangement only; production limit and classification rules unchanged |
| [093:1](../../../specs/093-abo-p7-1-clean-up-dependent-paths-control-residue/escalations.md#L5) | Residue guard scan roots | mixed source guard / excluded scan effects | R8, R9 | Executable residue guard bounded roots → operational evidence limits; actual platform/backend/frontend removed-route replacement ownership remains R1/R5/R7/R8. Viewer/test/doc scan effects excluded |
| [094:1](../../../specs/094-abo-p7-2-cross-system-security-isolation-suite/escalations.md#L5) | Story grouping under rule S3 | reference-only / excluded effect | R2 | Security-suite story grouping only; no production contract amendment |
| [095:1](../../../specs/095-abo-p7-3-contract-version-matrix/escalations.md#L5) | Worker N with DO N+1 | source-contract | R2, R5, R7 | Worker N sender → DO N+1 accepts and echoes N → Worker coverage/refusal mapping and downstream desktop safe status |
| [095:2](../../../specs/095-abo-p7-3-contract-version-matrix/escalations.md#L15) | RPC receiver current version | reference-only / excluded effect | R2, R7 | Backend receiver-version test variant only; published RPC hardcoded accepted versions unchanged |
| [097:1](../../../specs/097-abo-p8-2-staging-acceptance-a1-a36/escalations.md#L5) | Untracked local noise does not block specify | reference-only / excluded effect | R9 | Historical local-noise workflow exception only; no runtime consumer |

## Exact questions, resolutions and amended spans

The machine-readable index contains the complete recorded wording, including multi-paragraph answers. Use the stable ID to join this routing table to a phase packet. The originating escalation file is reference authority; runtime source is evaluated separately in R1–R9. All 75 records remain `routed; source correctness and propagation not yet reviewed`.
