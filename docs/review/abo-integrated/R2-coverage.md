# R2 aggregate source coverage and escalation closure

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. 2026-10-16 Africa/Cairo. **R2 complete with findings — 0 P0, 4 P1, 3 P2.** Canonical [report](R2-contracts-perimeter-human-approval.md). All findings and remedies in that report supersede inconsistent exploratory wording in delegated reports. No unread R2 primary region; no later phase completion claimed.

## Exact read coverage

The [R0 manifest](manifest-R2.md) assigns 3,885 physical primary lines in 22 paths, represented by 243 symbol ranges. Actual read records, including supporting functions and partial-body limits:

- [Contracts/SQL/Dart coverage](R2-contracts-coverage.md): complete 1,925-line production package (15 modules), production exports/config; actual SQL billing/feed and custom AI wire producers and verifiers, paid/reversal signature callers, backend feed version consumer, five public RPC channels and Dart adapters.
- [Platform coverage](R2-platform-coverage.md): all entrypoint owned regions, common crypto/assertion/bootstrap/replay, actual every-method entrance/dispatch authority, Worker public/DO version dispatch and named supporting transports/state boundaries. Includes actual full M/H/HP map and precise limited business-body reads.
- [ABO coverage](R2-abo-coverage.md): all host/version/Access/HP/credential-relay owned regions; actual six local action receiver/dispatch bodies and active credential registry consumer; replay schema and runtime exposure.
- [Coordinator supporting coverage](R2-coordinator-coverage.md): independently checked finding-critical source, additional actual frontend transport consumers and public/DO request/response paths.
- [Machine closure](R2-coverage.json): each exact manifest range mapped to its primary read-evidence artifact. Assignment mapping alone is not proof; the inclusive ranges in the four linked manifests are the evidence.

All 15 production package modules were read in full; testkit was excluded. Whole-file claims are confined to explicitly listed full modules. Supporting source belonging to R3–R9 was read only to establish R2 contracts/authority/version consequences. Searches are distinguished from full-body reads. No test, fixture, vector, harness/campaign or viewer implementation was opened or executed. Production runtime clock/override guards are in scope. No build/lint/service/provider operation occurred.

Extra coordinator source after its initial log: entrypoint1874–2005 and registry/replay migration full (bootstrap predicate/uniqueness), public billing gate1311–1335 and canonical billing94–165; entrypoint83–130,150–167,240–262 and result-envelope full supporting map/schema checks; worker1674–1699,1719–1753,1799–1819,2004–2024 plus coverage/transfer87–117; credit70–165/admission280–325/quota coverage4110–4145,4280–4316 transport follow-up; ABO ops870–948,2358–2444; checkout110–125,588–620 and notify516–end for return version/authority only (notify410–490 and grant270–313 surfaced as context and are not full R3/R4 review). Package grant75–112 and ABO grant446–478 confirm paid operation-shape propagation; entrypoint3200–3275 supporting grant class branch. Complete spec082 FR001 and spec081 page requirement read as references; bounded production search confirms no WebAuthn browser producer.

Revision gate: HEAD remains T; B/H objects exist; T/H differing names are workflow/captured artifacts only. Initial/final tracked worktree diffs empty; existing untracked user review artifacts preserved. Only R2 report/coverage/supporting docs and R2 tracker row written.

## Escalation dispositions

All **33 IDs** from [R2 escalation subset](escalations-R2.json) were reconciled against their amended rules. “R2 closed” means the contract/perimeter obligation is checked or explicitly routed outside its owned business concern; it does not certify later-phase state effects. Reference-only effects were read as escalation prose, never as excluded implementation.

| IDs | R2 disposition / exact continuation owner |
| --- | --- |
| 066:1, 066:4 | Raw Ed25519 key representation, registry envelope/status relay and common bound HP inputs traced. R1 canonical registry review retained; C1/C3 remain canonical. R8 owns complete lifecycle/audit policy. |
| 066:5 | Re-transcription only; amended registry rules above govern. No independent runtime amendment. |
| 066:7, 066:9 | Reference-only harness effects excluded. Actual pending promotion and nonempty-registry assertion requirement independently read; P3 identifies the real concurrent empty-registry exception defect. |
| 067:1, 095:1 | Actual Worker/DO negotiated accept/echo/refusal ordering read. N Worker with N+1 DO accepts in N; unsupported or unknown reply handling has C2/C3 defects. No campaign inference. |
| 067:2 | Service-key exact bound fields and active-key paid/reversal signature consumers traced; date validation remains R1-C3. ABO signing-key gate/ops relay are actual consumers. R8/R9 retain lifecycle/deployment operational effects. |
| 067:8 | Shared receipt canonical signing/verification and actual grant/void/transfer producer shape read. ledger_seq meaning and receipt-to-state binding remain R4/R6. No signature success treated as payment/coverage proof. |
| 067:10 | Actual readCoverageEvents validates limit1..200, including missing/outside refusal, before DB read; actual authority M. R7 owns event projection semantics. |
| 067:11 | Package evidence minimum and actual grant class/signature boundary checked. Paid operation approval is permitted by 079; complimentary stays HP. R4 owns every business branch/minimum refusal ordering and transfer lineage. |
| 067:12 | Re-transcription only; no additional runtime rule. |
| 071:1, 071:2 | Actual H listGrantsForVoid window/filter envelope and HP operator-void challenge evidence boundary, M signed reversal fields traced. Full partial/tombstone/idempotency/R2-object effects are R6, with explicit continuation rather than a false R2 business-completion claim. |
| 071:3 | Shared receipt accepts nil UUID, zero sequence and empty term list for tombstone shape; signature helper binds those bytes. R6 must prove nil IDs apply only before grant and no event emitted. |
| 072:1 | Actual begin/delete HP and transferOut/In M guards and receipt-id wire shape traced. Full saga/package state/recovery belongs R6; see dynamic-binding and existing-assertion seams below. |
| 075:2 | Actual rebuildGrantLedger uses class-H invoke wrapper over named binding; no new public HTTP route. R9 owns ledger/snapshot rebuild order and implementation. |
| 076:1 | ABO unsupported response current/header/accepted list and empty cross-host404 order verified. Startup key-check writes qualify the literal no-write rule. Ledger object key is R9, outside R2 perimeter. |
| 077:1 | paymobReturnUrl uses package paymobReturn v; actual canonical checkout stores claims.jti. Return handler ignores unknown v and schedules inquiry, never authorizes payment. R3 owns provider safety and public-return work bounds. |
| 078:1 | Provider notify path is host-separated and intentionally outside clinic-header gate. Body cap/rate/lease effects remain R3/R9 and are not inferred from the R2 route read. |
| 079:1, 079:6 | Actual ABO paid approval `{op:grant,params:base,actor_email:'',issued_at:paid_at,nonce:grantId,contract_version}` reaches package paid-operation acceptance/minimum; paid signed envelope is M, not HP. R4 owns exact approval/business-evidence correspondence. |
| 079:4 | Actual ABO grant receipt verification failure refuses durable outcome and parks (read476–494); R4 must prove full outcome ordering and matching grant/hash/tenant, beyond cryptographic validity. |
| 081:1, 081:2 | Actual local action helper→class-H recordOperatorAction forwards JWT/action/subject/action_id; platform verifies actor and uses action_id idempotency. R8/R9 own audit recovery after local/remote commit separation. |
| 081:3 | Actual inspectCoverage remains H and forwards verified JWT; no new audit-write obligation invented. Missing browser page/ceremony is P4; full data views R8. |
| 082:1 | Active-only fresh credential list and credential_not_active collapse implemented; platform revoked-specific code stays distinct. Local target binding P1 and missing ceremony P4 qualify the flow. |
| 086:2 | Actual successful registration relay decodes `{credential_id,public_key_cose,alg}` and remembers it, including pending/bootstrap. No email-alert intake invented. Hourly comparison and alert durability R9. |
| 087:1 | R1 canonical private signing/next/retired backend lifecycle preserved; verifier-side states remain separate. R2 confirms actual token-byte profiles and no vendor backend secret requirement. |
| 088:1 | Status/refresh accepted-version/refusal propagation read; SELECT/check/upsert throttle concurrency and unawaited desktop refresh error are explicit R7/R9 handoffs. No separate SQL finding duplicated here. |
| 088:6 | Flattened backend projection intentionally omits stored snapshot version; feed version and request RPC version remain independently checked/returned. R7 owns event application. |
| 094:1 | Reference-only scenario grouping excluded; runtime authority boundaries reviewed independently. |
| 095:2 | Reference-only override variant excluded; published five RPC gates remain hardcoded0/1, which is the actual T contract. No test variant source consulted. |

## Inherited and forward seam register

| Owner | Required proof / checkpoint |
| --- | --- |
| R1 canonical | C1 clock required at actual billing+feed callers. Preserve AI JSONB wire and deliberately choose strict equality-at-expiry alignment. C2 first-binding cap and C3 date validity remain their existing IDs; no duplicate findings. SQL authority findings retained. |
| R3 | Token C1 governs checkout authority lifetime. Return handler516–532 scans/schedules every open checkout on an unauthenticated return; assess provider/intake resource and inquiry-budget effects in R3 rather than infer them from this bounded R2 read. |
| R4 | Actual signed receipt vs org/installation/grant/hash/result and durable outcomes; exact paid approval semantics; complimentary main/override claims precede apply and can be consumed before a no-apply failure. Actual ABO complimentary relay is inline, so no automatic stored-HP retry assertion was made. |
| R6 | Transfer existing-assertion shortcut, DO initialization loss after durable transfer, delete dynamic binding across epochs; partial/tombstone and operator void evidence; transfer receipt shape validator currently lacks transfer_id but has no rejecting production caller, so do not install it unchanged. |
| R7 | Usage client expects top-level term vs coverage receiver snapshot; refresh throttle concurrent select/upsert and unawaited error/version UX; decoder integration after C2/C3; flattened projection exception retained. |
| R8 | Full operator forms/usable UI and each business method policy/audit; P4 initial shell decision must be approved before implementing exception. Stale METHOD_CLASS constant is descriptive, not an authority bypass. |
| R9 | Access/binding/environment deployment facts; startup key-gate/unsupported telemetry bookkeeping vs literal no-write wording; replay/audit/mutation split recovery; key registry announcements, hourly comparisons, stored-version rebuilds and strict decoder failure propagation. |

No unresolved R2 source coverage. P4 has the one explicit unresolved remedy decision (maintainer/architecture browser bootstrap contract); implementation stops before routing changes. All other canonical recipes are ready in the report. Overall remains review in progress; R0/R1 preserved; R3–R10 not started.
