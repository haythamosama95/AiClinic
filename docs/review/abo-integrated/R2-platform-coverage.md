# R2 platform coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e` (HEAD independently checked); 2026-10-16. Delegated platform common perimeter slice. All assigned platform primary manifest ranges read. Supporting source coverage below is bounded and does not claim business algorithms owned by R4/R6/R8/R9. [Report](R2-platform-review.md).

## Primary manifest regions read

| Path | Inclusive ranges read |
| --- | --- |
| `ai-platform/src/vendor/contract-version.ts` | 1–49, complete |
| `ai-platform/src/vendor/entrypoint.ts` | 1–308 (includes owned 1–78,81–128,135–136,231–308); 451–531; 689–747; 765–1047; 1077–1305; 1334–1451; 1858–1928 |
| `ai-platform/src/quota-do/index.ts` | 88–98; 220–235; 805–818 (contains owned 92–93,226–230,809–814) |

## Supporting complete functions / bounded regions

- `entrypoint.ts`: complete `registerOperatorCredential`, `revokeOperatorCredential`, `listOperatorCredentials` 1930–2192; complete `setCeilingPolicy` 2999–3112; complete complimentary branch plus paid signature boundary 3113–3550 (remaining paid grant business validation not read); complete `beginTransfer`, `transferOut`, `transferIn`, `deleteInstallation` 3705–3931; signed reversal boundary 3932–4065 (remaining reversal business implementation not read); complete HP void/release and H void-list 4154–4454; complete H/M reads/dispatch/control wrappers 4455–5147.
- Registry and plan wrappers: guard/argument boundary reads only 2193–2240,2350–2398,2445–2494,2529–2577,2651–2699,2766–2813,2907–2954. R1's canonical full registry coverage is preserved; R8 retains detailed policy. `rg` navigation inspected every `finishHpAssertion` call to establish common invocation topology, not unread business bodies.
- `entrypoint.ts` complete `callCoverageDo` 603–625; `durationScaleFromEnv` 627–634; `tryComplimentaryGrantIdempotency` 1452–1528.
- `worker.ts` complete DO request parser/refusal/dispatch 1674–1697,1719–2023, HTTP route dispatcher 2343–2513; bounded production-only harness-access guard 1699–1717,1764–1798 (the runtime test override accessibility is in scope; no harness implementation inspected). Complete feed version parser 2081–2093. Business handlers called by the dispatcher are outside this slice except coverage read below.
- `coverage/transfer.ts` 1–340: imports/types/key import, transport, receipt, source/epoch/replay lookups and complete executeBeginTransfer; 617–722 complete executeDeleteInstallation. Remaining transfer algorithms not reviewed. `quota-do/coverage.ts` 1220–1315 grant receipt/outbox effect; 1320–1375 complimentary ceiling branch;1490–1532 adjustment ceiling branch;2315–2353 and2425–2450 replay serialization guards only;4100–4142 and4280–4315 rebuild/refresh transports only.
- `admission/index.ts` 280–330 complete callAdmissionDo plus boundaries,645–690 actual request construction; `credit/index.ts`1–170 actual credit and fallback transports; `coverage-read/index.ts`1–155 complete file. These reads establish response-version interpretation, not accounting algorithm correctness.
- `abo/src/ops/index.ts`2219–2335 complete recordComplimentaryGrantRows and relay boundary;2600–2785 complimentary relay and suspend boundary. No claim to ABO-side common HP review (sibling owner).
- `clock.ts`1–46 complete production gating. `ai-platform/wrangler.toml`1–145 plus targeted production clock/cert/bypass search; `abo/wrangler.toml` binding/exposure searches at4–5,47–50,54–55,88–91,127–130. Actual deployed secrets, Access app and binding access cannot be established statically.
- Complete schema `20261003120000_operator_credential_and_platform_alert.sql` and `20261006150000_transfer.sql`; tenant-binding unique partial index in `20261003130000_issuer_key_tenant_binding.sql`. Searches across production migrations for later credential/replay/transfer uniqueness changes found none. No migration execution.
- `packages/vendor-contracts/src/version.ts` complete supporting read; package implementation ownership remains sibling. Other package crypto verification internals are not claimed as re-reviewed here.

## Method-authority / replay matrix

Version = numeric `contract_version` negotiated before listed auth or mutation. M = service binding, H = Access JWT verified by platform, HP = H plus common bound assertion. `METHOD_CLASS` is descriptive only: actual methods enforce their own guards. Its stale entries omit suspend/resume/inspectCoverage, call grant M regardless of source, and label listGrantsForVoid M; actual source enforces the correct classes below. No runtime authorization is derived from the constant.

| Actual method family | Authority established in actual source | Replay/mutation boundary and next owner |
| --- | --- | --- |
| register/revoke operator credential | HP; first registration permits H while registry empty | Bootstrap race PF2. Normal claim before registry mutation; pending 24 h; active read promotion. |
| registerIssuerKey/retireIssuerKey/revokeIssuerKey; registerServiceKey/revokeServiceKey; publishPlanVersion/retirePlanVersion | Version → verified Access → common HP check at actual method entrances | Common claim helper used by bodies (call navigation); R1 registry full-body evidence, R8 policy. |
| setCeilingPolicy | HP; existing operation digest returns old row after Access | Claim before policy INSERT; version allocation/rollback durability remains R8. |
| grant complimentary / term_adjustment | HP at3324; additional override if present | Main/override claims before apply; PF1 override context failure. Exact completed grant peek precedes HP re-verification; R4 effects/recovery. |
| grant paid | M + active registered ABO key signature on exact envelope bytes | ABO signature at3486–3541; no human touch by approved paid-approval amendment. R4 owns full envelope/business rules. |
| voidForReversal | M + active registered ABO key signature binds version/grant/reversal/reason/evidence/partial | Full signed-body verification3932–4015; R6 owns tombstone/reversal effects. |
| transferOut / transferIn | M; pre-existing authorized transfer ID | Actual wrappers3799–3862; helper business effects R6. Exception to fresh signature is durable authorized transfer lineage. |
| beginTransfer | HP; Access + common check, existing digest lookup short circuit | D1 batch before assertion insertion; partial unique live-binding constraint prevents simultaneous duplicate live targets; R6 recovery. |
| deleteInstallation | HP | Dynamic current binding deletion before replay insertion; R6 target/race seam. |
| releaseHeld / voidGrant | HP; Access + common check; exact DO receipt peek | DO challenge-key serialized receipt before global replay claim; R6 business semantics. |
| listGrantsForVoid | H (despite stale METHOD_CLASS M) | Actual Access check4401; no mutation, policy R8. |
| suspend / resume / inspectCoverage | H | Actual Access4474/4526 before target/DO; mutation effects R8/R6. |
| routing-policy publish/canary/promote/rollback; kill-switch arm/disarm; capability deprecate/retire; token-contract begin/retire; cohort activate/promote; rebuildClinicDo/rebuildGrantLedger/refreshCoverageSnapshot; recordOperatorAction; supportLookup | H via complete invokeClassH4746–4763 and actual wrappers4765–5125 | Access actor passed where signatures require it; no HP by catalogue. Business policy/audit R8, rebuild/support effects R9. |
| listOperatorCredentials/listIssuerKeys/listServiceKeys/getCoverage/listGrants/readCoverageEvents/feedConsumerHealth | M | Binding-only reads; credential list may promote due pending rows after version gate. readCoverageEvents checks limit1..200; R7 event payload correctness. |

## Escalation subset disposition

Read packet R2, machine primary manifest, R1 canonical report/handoffs, R1 consumer coverage, AGENTS.md, system map, review-plan scope/phase/reporting rules, amended architecture 02 surfaces/hostnames/credentials/authorization/threat boundaries and 04 transport/method catalogue/assertion/receipt/version rules. Full source read never inferred from a clipped large output; primary functions were loaded again in bounded groups. Architecture is reference, not reviewed implementation. The coordinator owns full packet and all 33 routed IDs.

| IDs / effect | Disposition within this slice |
| --- | --- |
| 066:1,:4,:5 | Registry common guard and operation binding checked; existing R1 raw key/status/date findings retained. Registry business envelopes remain R1/R8 full-body ownership. |
| 067:1;095:1 | DO gate precedes writes; accepted success echoes request version; error/consumer drift sent to common R2 version finding. Gradual rollout checks unknown reply version are missing at actual consumers. |
| 067:2 | Service registration common HP bound fields; actual paid/reversal active-key signature boundaries read. Full validity data issue remains canonical R1-C3. |
| 067:8 | Receipt construction supporting transfer sign and grant signing reads; package sibling owns canonical signature verification; business matching R4/R6. |
| 067:10 | Complete readCoverageEvents checks missing/under1/over200 before DB read, limit200 accepted. |
| 067:11;079:1,:6 | Paid signature boundary counts minimum approvals, no WebAuthn ceremony, consistent with paid exception; full validators/package sibling/R4; complimentary common HP verification retained. |
| 067:12;071:2 | Re-transcription adds no independent runtime rule. |
| 071:1,:3 | H listing authority, HP void evidence/replay boundary and signed reversal boundary traced. R6 retains full partial/tombstone/state/evidence semantics; not falsely closed here. |
| 079:4 | Receipt-result business effect belongs ABO/package/R4 siblings; no statement of completion from platform production alone. |
| 095:2 | Reference-only excluded variant effect; no variant/test source read. Published SQL version receiver belongs coordinator's cross-channel synthesis. |

No unread assigned platform primary range. Open business seams explicitly belong R4/R6/R8/R9; no later-phase completion implied. Reports only were written; overall tracker unchanged.
