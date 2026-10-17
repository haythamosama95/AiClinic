# R2 ABO actual read coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; HEAD verified identical. 2026-10-16. This is actual inclusive source reading, not manifest inventory. Delegated report: [review](R2-abo-review.md). No tracker change; no application edits or execution.

| Source | Actual read ranges | Purpose / limit |
| --- | --- | --- |
| abo/src/clinic-api/version.ts | 1–142 | Full module, owned version parsing/gates/errors/telemetry. |
| abo/src/worker.ts | 1–380 | Full fetch perimeter and actual billing/ops callers; scheduled beginning context only. Scheduled remainder unreviewed/R9. |
| abo/src/ops/index.ts | 1–300; 390–790; 790–1403; 1929–1965; 2330–2640; 3290–3825 | All assigned constants/types/Access/assertion/replay/HP handler/credential relays, plus actual local mutations to prove signed-argument use; dispatch read whole 3303–EOF. Ranges 2330–2357 and 3290–3302 begin within earlier functions and are context only. No whole-file claim. |
| abo/src/clock.ts | 1–46 | Full production clock override gate (not harness implementation). |
| abo/wrangler.toml | 1–EOF | Runtime binding/host/exposure/env evidence. |
| abo/migrations/0007_hp_actions.sql | 1–EOF | assertion PK/append-only and payment_release PK. |
| ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql | 1–EOF | Registry/replay schema supporting read; platform sibling owns findings. |
| ai-platform/src/vendor/entrypoint.ts | 813–865; 1874–2145; 2165–2210 | Count/read/promotion/bootstrap/register/revoke partial end/list consumer supporting reads. Platform sibling owns canonical ceremony/bootstrap/concurrency. 2130–2145 partial revoke mutation tail, not whole-method completion. |
| packages/vendor-contracts/src/operation.ts | 1–65 | Supporting actual canonical operation schema/challenge use. |
| packages/vendor-contracts/src/access-jwt.ts | 1–146 | Supporting Access verification consumed by ABO; package sibling owns canonical review. |
| packages/vendor-contracts/src/webauthn.ts | 136–210 | verifyAssertion body; package sibling owns other functions. |
| packages/vendor-contracts/src/version.ts | 1–43 | Supporting N/N−1 behavior and constants. |
| frontend/lib/core/contract_versions.dart | 1–13 | Constant comparison only; actual desktop request handling owned coordinator/consumer follow-up. |

Reference reads: repository AGENTS.md and complete constitution; R2 packet and manifest; system map; review-plan sections 1–4 (through R5 opening) and 5–8, with earlier combined output truncation explicitly not treated as extra read coverage; R1 final checkpoint and canonical report excerpts including handoffs (not independently re-audited source); current 02 trust-boundary/credential/authority/rotation sections; current 04 §§1.1–1.6, 2.3, 7; complete 081 and 082 escalation records. R2 escalation JSON header and 066 initial entries read only; coordinator/sibling closes remaining entries. No excluded source was opened. Search results used only for locating symbols do not imply body coverage.

All ABO-owned R2 manifest regions read. Additional local mutation reads establish exact target use without claiming R8 method-policy completeness. No assigned ABO primary source continuation remains. Canonical R2 completion still depends on siblings and coordinator consumer/escalation closure.

Producer closure: searched only production abo/src, frontend/lib, ai-platform/src and packages/vendor-contracts/src (excluding testkit) for navigator.credentials, credentials.get, webauthn.get, operationChallenge and local operation names. No browser ceremony producer exists in those source roots; results identify only server verifiers and challenge utility. Tracked ABO inventory has no page asset; complete ops dispatch and wrangler confirm no served console page/asset binding. This is bounded search evidence, not full frontend source review. spec 082 FR-001 and FR-005–011 read as reference for exact input obligations; chosen fix schema uses explicit offer_id/payment_id/org_id target fields because no producer mapping can be verified.

Follow-up source conclusion: missing production browser ceremony is recorded separately as R2-ABO-03 (P1). No further application source was read or changed; evidence is the producer search, complete actual dispatch, host/version gates and deployment artifact already listed above. Shell bootstrap remedy deliberately stops pending a maintainer-approved contract exception for initial HTML navigation.
