# R8 coverage and escalation closure

**Complete with findings**, 2026-10-17 Africa/Cairo. Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`. Workspace start/end HEAD `a2545299b82fd0c22f92d316fb4790ce47c159c9` is newer; all production/reference source reads were pinned git objects. [Canonical report](R8-operator-control-configuration.md), [exact aggregate](R8-coverage.json), [checkpoint](R8-checkpoint.md).

The completed tuple multiset equals the manifest exactly: **239 unique/disjoint tuples, 4,469 final + 1,951 deleted lines, zero unread**. Assignments were partitioned before source review; only narrow targeted confirmation overlaps supporting reads. The extra deleted bootstrap script (247 B lines) corrects the packet/inventory scope discrepancy as a supporting expansion, not extra primary tuple credit. No R9/R10 work claimed.

| Reviewer / primary assignment | Actual setting | Tuples | Lines | Evidence |
| --- | --- | ---: | ---: | --- |
| console | GPT-6.1 Sol / medium | 46 | 1753 | [Assignment](R8-console-assignment.json) · [Completed exact ranges](R8-console-coverage.json) |
| configuration | GPT-6.1 Sol / medium | 63 | 1502 | [Assignment](R8-configuration-assignment.json) · [Completed exact ranges](R8-configuration-coverage.json) |
| legacy | GPT-6.1 Sol / medium | 68 | 1951 | [Assignment](R8-legacy-assignment.json) · [Completed exact ranges](R8-legacy-coverage.json) |
| lead | GPT-6.1 Sol / high | 62 | 1214 | [Assignment](R8-lead-assignment.json) · [Completed exact ranges](R8-lead-coverage.json) |

Supporting sources and revision/ranges are retained in each exact slice log; these include final issuer/service/plan methods and verifiers, current-key re-signing/last-seen consumers, policy routing/cache consumers, sale readers, schema constraints and deleted bootstrap replacement. Metadata-only excluded path searches were navigation. No whole-file test/fixture/harness/viewer credit is claimed.

## Escalation dispositions (24)

| ID | Disposition | Amended producer → consumer / qualification |
| --- | --- | --- |
| 066:1 | checked; inherited R1-C3 | registerIssuerKey raw32 base64url and immutable kid/key -> row/list -> platform verifier and ABO pins. Missing/different public key errors preserved; malformed issuer validity remains R1-C3. |
| 066:4 | checked; R8-KEY1 | retireIssuerKey alone writes retiring; register preserves state; revoke terminal intent, violated by stale retire update. Active/retiring verifier acceptance traced. |
| 066:5 | reference-only transcription; production checked | No new runtime rule; amended 066:1/4 registry fields/statuses checked at entrypoint, identity consumer and ops field allowlists. |
| 066:6 | checked final replacement | Transitional entitlement/tier behavior superseded; final removed control and dropped plan/entitlement traced to plan_version/coverage, miss-only legacy cache readers and no HTTP authority. |
| 066:7 | excluded harness effect; final runtime context checked | No harness implementation read. Later 074:2 explicit no-ver/current2 begin semantics governs final production, preserving pending credential activation. |
| 066:8 | excluded harness effect | No seed/vector/case implementation reviewed. Final issuer token version and binding replacement inherited R1/R2; later 074:2 rotation rule controls. |
| 066:9 | excluded harness effect; runtime boundary checked | Existing registry requires assertion on second operator registration; issuer kid replacement is distinct from credential registration. No bypass borrowed from harness. |
| 067:2 | checked | HP service registry raw32 active/revoked validity -> listServiceKeys -> ABO signing gate, and grant verifier unknown transient/revoked invalid. Original stored envelope is re-signed with current key. |
| 067:3 | checked | HP plan immutable content/same-content replay preserving retired -> R4 snapshotted grant consumer. Ops relays exact content field allowlist and retire identity. |
| 067:5 | checked; inherited R4-PG4 | listGrants filter/ledger order contract retained; console views and containment depend on verified credential attribution. R4-PG4 remains canonical, not another R8 finding. |
| 067:9 | checked | Published capability string array -> plan snapshot -> cohort published-plan parser and mirror capability parser/discovery; no legacy allowed_capabilities economics authority restored. |
| 067:12 | reference-only transcription | No independent runtime amendment. Amended service/plan/list/event rules checked through relevant producers/consumers and prior canonical ownership. |
| 070:1 | checked; R8-CEILING1; inherited R2-P2/R4-D5 | All seven ceiling inputs -> stored version/greatest row -> grant/DO limits. Version allocation races; rolling per-org history and separate override binding remain prior roots. |
| 071:1 | checked inherited R4/R6 | Void list inclusive required window, credential even revoked, source/evidence and exact signed original reversal retained by canonical R6; console dispatch/containment propagation checked. No partial/retry redesign inferred. |
| 074:1 | excluded test migration effect; semantic removal checked | Mutable plan/entitle/override and legacy quota behavior intentionally not ported. Actual final HTTP removal/replacement established without reading cases. |
| 074:2 | excluded cases; explicit runtime amendment checked | Final no-ver beginTokenContractRotation current2 idempotence checked in producer/entrypoint/handler; removed control validation/quota bodies intentionally not restored. Supersedes earlier harness-only future-ver narrative. |
| 081:1 | checked; inherited R6-O1 | ABO insertOperatorAction -> recordPlatformOperatorAction -> platform H recordOperatorAction; exact action/id mapping; durable delivery remains canonical O1, new ID content collision is R8-CONSOLE3. |
| 081:2 | checked | Real platform entrypoint owns and exposes recordOperatorAction; Access checked, control_audit only, duplicate action_id returns ok. No invented alternate write path. |
| 081:3 | checked explicit exception | Clinic handler forwards Access to inspectCoverage and displays returned ledger. No platform audit/email echo required by amended exception; support is separately audited by AUDIT1 remedy. |
| 082:1 | checked inherited R2 | Local HP refetches active-only registry; missing pending/revoked/unknown credential maps credential_not_active; platform retains credential_revoked distinction. |
| 086:2 | checked producer/consumer seam | Successful operator registration detail -> rememberOperatorCredential triples -> seen_operator_credential -> hourly active triple comparison. Pending known rows remain recognized after promotion; no email intake invented; R9 owns job/alert liveness. |
| 087:1 | checked inherited R1 custody | Backend next/signing/retired privileged switch differs from verifier active/retiring/revoked. Console only platform registry relay; pins + signer switch deployment order retained. |
| 087:2 | excluded harness-only effect | No mockFetch/testkit/local seed reviewed; no production activation or Access bypass inferred. Platform 24-hour registration remains. |
| 093:1 | reference-only guard-scope amendment; actual removal checked | Narrow dependent-tree guard is not removal proof; T source tree/HTTP dispatch and exact deleted bootstrap replacement inspected. Guard implementation remains R9, viewer excluded. |

## Completion and limits

0 P0, 3 P1, 11 P2. Canonical IDs supersede colliding provisional C labels in console/configuration slice evidence. All forward R8 recipes are implementation-ready; historical unknown text/configuration/predecessor/actor/signers require explicit maintainer/frontier adjudication and safe stop. Earlier R1–R7 findings and R2-P4 browser/bootstrap decision remain canonical/unfixed; no repeated common authorization root is counted by method. Full method/class/policy/audit and key/configuration lifecycle matrices are in the report; legacy reachability matrix is in the legacy evidence.

Application unchanged relative to start HEAD; only R8 review artifacts and its tracker row changed, preserving prior R7 artifacts. No tests/build/lint/services/live research/source changes/commits/pushes/branches/account-usage calls. Narrow incidental embedded fixture helper declarations/body displayed in one append.ts supporting read were not analyzed or used. Static review cannot attest live permissions, deployed keys/buckets/Access, cache timing, external providers, alarms or operational ceremonies. R9/R10 remain not started; overall review remains in progress.

Final targeted R6 handoff confirmation established R8-RETRY1 (P2): grant-only retry excludes parked reverse work. Exact original-command recovery recipe is canonical; no remaining seam. Adjacent R9 payout/finding code incidentally displayed during navigation was not analyzed or credited.
