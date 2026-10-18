# R8 — Operator control and configuration

**Complete with findings: 0 P0, 3 P1, 11 P2.** Completed **2026-10-17 Africa/Cairo**. Target **`db9244fddfddc1905335fb8c7105328c15a0cc5e`**; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f` is provenance only. Workspace HEAD remained the newer **`a2545299b82fd0c22f92d316fb4790ce47c159c9`**; later source changes are excluded. Conclusions concern T, not whether HEAD has repaired earlier findings.

Lead/synthesis `/root/abo_r8_review` was explicitly **GPT-6.1 Sol/high**; bounded reviewers `/console`, `/configuration`, `/legacy` were each explicitly **GPT-6.1 Sol/medium**. [Coverage and all 24 escalation dispositions](R8-coverage.md), [exact JSON](R8-coverage.json), [checkpoint](R8-checkpoint.md) close **239 disjoint tuples: 4,469 final + 1,951 deleted lines**. The deleted 247-line bootstrap script was additionally reviewed: R0 excluded it despite R8 explicitly requiring it. This expansion is recorded without changing R0 ownership. Minimal evidence: [console](R8-console-review.md), [configuration](R8-configuration-review.md), [legacy](R8-legacy-review.md), [lead](R8-lead-review.md). Their locally repeated C-number labels are slice evidence only; **the distinct IDs and severities below are canonical and supersede provisional slice counts**.

## Established intent, policy and result trace

There is no shipped browser form/passkey producer at T: **R2-P4 remains canonical**. Actual review starts at authenticated HTTP lookup/JSON dispatch, so no rendered target/intent guarantee is claimed. Lookup resolves a clinic by exact commercial references or billing identity; its clinic view forwards Access to live `inspectCoverage` and combines commercial facts, events, actions and findings. Configuration HP relays allowlist fields, override URL key targets, and preserve the supplied operation/assertion. Platform HP checks the exact final argument map, actor, freshness, active credential and challenge before dispatch. H methods independently verify Access. Common R2-P1/P2/C1–C3 deficiencies remain inherited; no missing common gate is counted once per method.

Successful configuration relays call the platform before append-only ABO action recording. Local catalogue actions consume authorization before publication stages. **R6-O1 and R4-PG3 own accepted-command/durable replay**, with the new publication and action-ID causes below kept distinct. Parked reversal recovery must retain the original accepted bytes/identity; RETRY1 establishes its missing retry route; list-and-void remains dependent on canonical **R4-PG4** verified signer attribution. R4-PG1/A1/A2 and R6 mutation/transfer/deletion roots remain canonical. Source does not establish a fresh-value mutation as a substitute for recovery.

| Methods / surface | Actual class, policy and durable result at T |
| --- | --- |
| `registerOperatorCredential`, `revokeOperatorCredential`; `listOperatorCredentials` | HP, with first empty-registry H bootstrap; M list. Registration stores pending +24h, immutable ID/key replay; guarded HP/list promotion yields active; revoke terminal. HP claim/audit precede write; AL-13 follows. R2-P3 bootstrap race and accepted-command recovery inherited. |
| `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`; `listIssuerKeys` | HP mutations, M list. Raw 32-byte base64url key, immutable kid/key, configured issuer; register active, retire retiring, revoke revoked. List active/retiring for pins/expiry. KEY1 and inherited R1-C3 qualify safety. |
| `registerServiceKey`, `revokeServiceKey`; `listServiceKeys` | HP mutations, M list of all states. Fixed service=abo; no retiring. Same kid/key preserves validity/status. Unknown grant kid transient; revoked/outside finite validity rejected. ABO signing gate requires active validity and retries sign original stored bytes with current key. |
| `publishPlanVersion`, `retirePlanVersion`, `setCeilingPolicy` | HP. Immutable plan-content comparison; same-content replay preserves retired status; retirement only changes status. Ceiling greatest version effective; field mapping reaches grant checks. HP audit precedes D1 mutation; CEILING1 below. R4 owns term snapshots/ceiling enforcement, R2-P2 extra approval. |
| `publishRoutingPolicy`, `canaryRoutingPolicy`, `promoteRoutingPolicy`, `rollbackRoutingPolicy` | H. Publication identity check → R2 → D1+audit batch. Canary checks installations/status; promote supersedes active and other canaries; rollback selects superseded. Runtime cache consumes selected R2 bytes. PUB1, ROUTE1, ROLLBACK1, AUDIT1 qualify integrity. |
| `activateCohort`, `promoteCohort`, `deprecateCapability`, `retireCapability` | H. Registry/version/existence checks; plan string-array and mirror membership; no coverage creation. Installation/plan grants and global overlays feed discovery/invocation. Deprecation successor +90-day overlap before retirement; AUDIT1 qualifies trace. |
| `armKillSwitch`, `disarmKillSwitch` | H platform methods. Four validated scopes; integer switch normalized for capability/admission and provider routing through short-TTL config. Local mutation then audit, AL-19 afterward. Console exposes arm only (CONSOLE2). No live propagation time attested. |
| `beginTokenContractRotation`, `retireTokenContract` | H. Final amended no-ver begin ensures current 2; does not expose arbitrary future rotation. Retire requires another live version and atomically conditions update/audit. Identity rejects retired ver; actor audit gap below. 074:2 supersedes earlier harness narratives. |
| `supportLookup`, `recordOperatorAction` | H. Support exact reference or org/subscription resolves request/attempts and retention-gated envelope; missing lookup returns rejection. Live Access payload visibility is expressly permitted by AD-8. Record validates action/subject/id and deduplicates by target action_id; no domain changes. AUDIT1/SUPPORT1/CONSOLE3 qualify trace. |
| Console publish/retire/reinstate offer; plan/key/config relays | Local HP catalogue; platform H/HP relay classes above. Catalogue inherits immutable economics from existing offer, supplies text/copy/price, then facts/events; malformed/reinstated states below. No routine SQL fallback is established. |
| `grant` | M for paid, HP for complimentary/adjustment; exact stored envelope/receipt authority and grant audit under canonical R4/R2. R8 traces configuration/signing inputs only; no duplicate grant body review. |
| `voidForReversal`, `transferOut`, `transferIn` | M, signed reversal or existing authorized transfer; immutable receipt/step lineage under canonical R6. R8 checks route/intent propagation; no new body credit. |
| `beginTransfer`, `deleteInstallation`, `releaseHeld`, `voidGrant` | HP; exact operation/target/reason and durable receipt/transfer runner under canonical R6, with R2/R4 dependencies. R8 dispatch preserves evidence; accepted recovery cannot change value/identity. |
| `suspend`, `resume`, `inspectCoverage`, `listGrantsForVoid` | H. Suspension DO/D1 and containment window semantics under R6; installation helper audit under AUDIT1. Inspect explicitly has no platform audit (081:3); list filter attribution inherits R4-PG4. |
| `getCoverage`, `listGrants`, `readCoverageEvents` | M reads: coverage snapshot, filtered immutable ledger, bounded feed page; canonical R4/R7 producer/consumer review. No human-action audit requirement inferred for machine reads. |
| `rebuildClinicDo`, `rebuildGrantLedger`, `refreshCoverageSnapshot`; `feedConsumerHealth` | H rebuild/refresh, M health classification inherited from R2. Their method bodies/durable recovery and execution remain R9, not started. No R8 correctness/coverage credit for these R9 bodies. |
| Clinic/parked/registry/support lookup; cancel/retry; payout/finding console dispatch | Access precedes dispatch. Cancel/retry platform audit is recordOperatorAction after ABO commit; R6-O1 owns recovery. Payout/finding bodies remain R9. Routing coverage does not claim their execution review. |

| Lifecycle | Cross-action consistency / limit |
| --- | --- |
| Operator bootstrap → second credential → revoke | Second registration requires a current credential; 24-hour activation not bypassed. Pending/revoked/unknown absent from local active list → credential_not_active. ABO remembers successful registered triples before later hourly comparison (086:2); remote delivery/liveness remains R9. |
| Backend issuer rotation → platform acceptance → ABO pins | `next`→`signing`/old→`retired` backend switch is privileged R1-reviewed custody; platform retiring is verifier acceptance until validity, independently from backend signing. ABO pin addition/removal requires deployment. KEY1 can reverse revocation; R1-C3 date fix remains required. |
| Service-key rotation → delayed grant/reversal | Register next before secret switch; revoke old; stored request payload/version preserved and each grant attempt re-signs with current secret. Gate pauses invalid current key; R4/R6 exact identity/receipt and R9 wake-up/alert recovery still apply. |
| Plan publish/retire; ceiling append | Existing term content stays snapshotted. New grants recheck current plan/ceilings; completed receipts replay original accepted facts per R4 recipes. Policy changes do not silently rewrite terms/history. |
| Routing/cohort/capability/switch/contract | Runtime follows actual D1 states with cache TTL, not filenames. Audit/configuration batches and distinct control-flow defects below need repair; retired legacy plan/entitlement and bearer control authority do not survive. |

## Major findings and exact fixes

All diagnoses are high-confidence static source defects, not runtime reproductions. Forward code recipes are implementation-ready, with historical evidence stops stated separately.

### R8-KEY1 — P1: retirement can restore a revoked issuer key

`ai-platform/src/vendor/entrypoint.ts:2393–2428` reads active, awaits approval consumption/audit, then unconditionally writes retiring. Concurrent revoke `2507–2512` can complete in between and be overwritten. `identity/index.ts:226–237,470–482` then accepts the restored compromised key until validity expires, defeating emergency revocation beyond the cache TTL. [Evidence](R8-lead-review.md).

**Fix steps**
1. Guard retirement with `WHERE kid=? AND status='active'`; re-read and return kid_revoked for revoked, success for retiring, not-found for absent. Never derive the write solely from a prior read.
2. Batch actual transition/audit via AUDIT1; retain terminal revocation and same-key registration's no-reset behavior.
3. Complete when either retire/revoke interleaving ends revoked and refreshed verifiers reject. Historical resurrection needs audit review and explicit re-revocation, never guessed restoration.

### R8-PUB1 — P1: rejected publications overwrite accepted immutable R2 content

Console `abo/src/ops/index.ts:934–968` chooses global MAX+1 then writes `terms/en/N.txt` before D1 uniqueness; concurrent different publications can leave the winner's hash pointing to the loser's legal text. `clinic-api/offers.ts:52–71` serves it unchecked. Routing similarly writes shared identity/version key before D1 arbitration (`control/routing-policy.ts:155–189`); runtime `config-cache/index.ts:185–203` reads the rejected writer's bytes under the winner's audit. One invariant/root, two exact sites; independent of approval durability. [Console evidence](R8-console-review.md), [routing evidence](R8-configuration-review.md).

**Fix steps**
1. Store each terms/policy blob under its exact content digest; retain terms text_sha256 and forward-migrate nullable routing_policy.content_sha256. Distinct bytes never share a mutable key. Validate routing content via ROUTE1 first.
2. Keep routing row+audit atomic; losing publication cannot delete/replace winner content. For offers, retry terms/offer numeric uniqueness allocation using the same R6-O1 accepted payload and digest, batching terms+offer+events+facts; exact retry cannot mint another commercial version.
3. Verify content hashes in `termsText` and `loadRoutingPolicyDocument`. Deploy digest-writing producers before strict readers; backfill legacy routing digests only from verified original content, quarantine unverified legacy rows and republish a new version before enabling strict serving. Quarantine historical disagreements: maintainer/frontier must establish original text/document from retained evidence, stop affected sales/policy activation meanwhile, and never rewrite immutable history by guessing.
4. Complete when overlapping publications cannot affect each other's accepted bytes; rejected writes have no serving effect and hash mismatch fails explicitly.

### R8-ROUTE1 — P1: malformed routing configuration can be promoted globally

`control/routing-policy.ts:140–149` accepts identity-only documents; promotion `278–321` verifies status only and supersedes working routing. The runtime later requires schema/rules/catch-all and overrides (`router/index.ts:243–270,617–624`), so a routine incomplete publish/promote returns success then breaks AI routing for every clinic on that policy. [Evidence](R8-configuration-review.md).

**Fix steps**
1. Export a shared pure parser from `router/index.ts`; use it before publication writes and at runtime. Require schema_version=1, matching nonempty identity/positive integer version, defaults object, nonempty rules ending catch-all, rules/targets/requires objects and optional match objects with correctly typed arrays; required provider/model/rule IDs nonempty; cost class ∈ economy/standard/premium, tier ∈ standard/degraded, booleans exact, context sizes finite ≥0, attempts/timeouts positive safe integers. Validate overrides' installation ID, string-array exclusions and optional pin/known forced class. Preserve schema-retained fields with their typed positive integer bounds; do not add arbitrary provider restrictions.
2. Load and parse stored bytes before canary/promote changes state, protecting historical malformed rows; pass R2 into those wrappers. Invalid/missing content returns invalid_policy_document and leaves working serving state unchanged.
3. Complete when identity-only, unsupported schema and missing rules/overrides never become serving; valid documents retain current sequential routing/feature filtering. Full shape validation precedes PUB1 persistence.

## Moderate findings

### R8-ROLLBACK1 — P2: rollback can activate a never-promoted canary

Publication time is reused as active_from; promotion supersedes other canaries; rollback picks newest superseded by publication (`routing-policy.ts:154,306–321,378–384`). Publish A/B/C, promote A, canary C, promote B, rollback B restores C instead of A. [Evidence/recipe](R8-configuration-review.md).

**Fix steps**
1. Add per-policy activation generation and durable target/actual-predecessor record; historical predecessor stays explicitly unknown.
2. Fence promotion/rollback against expected generation in one D1 transaction with state updates, predecessor and audit; losing stale transitions commit nothing. Rollback uses that record, parses bytes per ROUTE1 and preserves scoped canary cancellation.
3. Complete when that sequence restores A irrespective of publication order; unknown history returns conflict requiring an explicit chosen promotion, never a guessed rollback.

### R8-AUDIT1 — P2: configuration and sensitive support audits are incomplete

Capability/switch/begin-rotation/installation handlers mutate D1 then separately audit; retries skip or reject the already-effective transition. Routing/cohort/token-retire omit new actor; cohort audit omits selected new memberships. Support `entrypoint.ts:5072–5125` ignores verified email and returns sensitive envelopes without platform audit. The explicit no-audit inspect exception 081:3 does not apply to support. [Configuration evidence](R8-configuration-review.md), [support confirmation](R8-lead-review.md).

**Fix steps**
1. Make `control/audit.ts` construct prepared statements with both actor/operator_id = verified email, assertion hash where applicable, and exact before/after target membership.
2. Batch local configuration transition and audit, guarded by actual expected state; route/cohort/token-retire use the same helper. Record complete selected installations/scopes, including new grants. Same-state retries do not duplicate transitions.
3. In supportLookup, use invokeClassH's email; persist a read audit with exact normalized selector before releasing successful diagnostic data. On audit failure return failure without payload; never store payload/Access JWT in audit. Preserve inspect's explicit exception.
4. Complete when local D1 effects cannot commit without their audit, every new actor/target is reconstructable and support reads are attributable. R9 owns remote DO/AL-19 delivery recovery; do not fabricate historical actors or claim cross-store atomicity.

### R8-CONSOLE1 — P2: reinstatement succeeds but leaves an offer unsellable

Producer writes reinstated (`ops/index.ts:1046`); offers and checkout accept latest published only (`offers.ts:74–98`, `checkouts.ts:135–153`). [Evidence](R8-console-review.md).

**Fix steps**
1. Emit published for reinstatement of the already resolved last published version, retaining reinstate_offer in audit.
2. Both readers accept historical reinstated as that activation alias; clarify amended lifecycle reference without mutating old facts or changing commercial content.
3. Complete when publish→retire→reinstate restores exact prior price/terms and later retirement hides it; never-published stays refused.

### R8-CONSOLE2 — P2: console can arm a switch but cannot disarm it

Complete ops interface/dispatcher exposes arm only (`134–136,176,3726–3735`), while platform disarm exists (`entrypoint.ts:4866–4884`). Operator recovery otherwise needs custom binding code or SQL. [Evidence](R8-console-review.md).

**Fix steps**
1. Add disarmKillSwitch to OpsEnv/relay union and POST /ops/kill-switches/disarm via existing H relay, allowlisting scope/target and killSwitchSubject.
2. Reuse platform validation/audit/AL-19, including future R2-P4 producer; never write switch state locally.
3. Complete when each scope can be lifted with Access and retains inactive/unknown errors and both audits.

### R8-CONSOLE3 — P2: reused action ID hides a different executed relay

Relay calls platform before ID-only local audit suppression (`ops/index.ts:2335,2199–2216`); caller-supplied ID can group two different successful mutations into one ABO action. Platform audit remains. [Evidence](R8-console-review.md).

**Fix steps**
1. Before dispatch, bind command ID to actor/method/subject/version/canonical final args in R6-O1's command store, distinct from append-only audit.
2. Changed content under an existing ID returns conflict before invocation; exact retries resume/return same result and one immutable audit.
3. Complete when switch A then B with reused ID cannot execute B; new IDs preserve distinct mutations and exact retries remain recoverable.

### R8-CONSOLE4 — P2: clinic action history omits payment/grant actions

Org/checkout/work-only query (`ops/index.ts:1539–1553`) excludes payment subjects used by release/chargeback and grant subjects used by void/release. [Evidence](R8-console-review.md).

**Fix steps**
1. Add exact org-scoped payment IDs, grant_request grant IDs and reversal→payment work linkage to query membership.
2. For imported/transferred grants without local request, use validated grant IDs from the already obtained platform inspection; never substring/global matching.
3. Complete when the owning clinic sees these actions and another org does not, preserving prior org/checkout/work entries.

### R8-CONSOLE5 — P2: malformed offer copy breaks the entire catalogue

Publish validates copy only as object (`ops/index.ts:893–900`); consumer dereferences copy.en.name (`offers.ts:47–49,114–119`). Approved copy={} makes every buyer's catalogue read throw. [Evidence](R8-console-review.md).

**Fix steps**
1. Before consuming approval require positive safe-integer price_minor, nonempty terms, copy.en object with nonempty string name and string summary; validate supported extra locales similarly.
2. Reuse validation for stored rows; quarantine/alert keyed malformed offer/version while other valid offers load. Never invent commercial copy.
3. Complete when malformed input consumes no approval/publication and one historical bad offer cannot abort the catalogue.

### R8-CEILING1 — P2: concurrent ceiling updates allocate the same version

`entrypoint.ts:3071–3100` computes MAX+1 before either write; distinct approvals collide, one fails after consumption. [Evidence](R8-lead-review.md).

**Fix steps**
1. Allocate within serialized `INSERT ... SELECT COALESCE(MAX(version),0)+1,... FROM ceiling_policy`.
2. Integrate insert/claim/audit into the accepted-command transaction from R4-PG3/AUDIT1. Forward-migrate ceiling_policy_command with challenge_sha256 primary key, unique policy_version, actor, operation_json, contract_version and result_json; leave historical policy rows/empty seed challenge untouched. New command allocation and policy insertion share one batch; exact retry checks canonical bytes/actor then returns its recorded row. Ambiguous historical replay remains read-only/refused pending evidence, never backfilled by guess.
3. Complete when concurrent updates get consecutive versions and no exact retry creates another policy or strands a touch. Shared consume-before-effect is inherited, not a second finding.

### R8-SUPPORT1 — P2: clinic support lookup has no resource bound

`support/index.ts:114–124,314–343` loads all journal requests/attempts and sequentially fetches every retained envelope. Ordinary accumulated clinic history makes one diagnostic request proportional to all retained history and payloads; no measured provider limit is claimed. [Evidence](R8-lead-review.md).

**Fix steps**
1. Page request IDs first using descending (created_at,request_id), default limit50/range1–100, cursor+has_more, then join their attempts.
2. Org/subscription pages return metadata; retain envelopes only for exact-reference lookup with existing Access/retention. Deploy additive receiver pagination before consumers; no T console org-list consumer exists.
3. Complete when list reads one bounded page and zero payload objects; exact-reference diagnostics still work and equal timestamps page without gaps/duplicates.

### R8-RETRY1 — P2: parked reversals have no operator retry path

`abo/src/ops/index.ts:1971–1977` rejects every retry whose work kind is not grant. Reversal processing parks reverse rows after rejected/conflict or unverified receipts (`work/reversal.ts:771–795,824–853`); its lease accepts open only (`914–921`). Even after correcting a signing/receipt configuration problem, the operator sees parked reverse work but retry returns not_found. This closes the explicit R6 handoff; it is distinct from R4's successful-grant outcome conflict and R6's accepted-action durability.

**Fix steps**
1. In handlePostRetry allow existing parked grant or reverse work, preserving work_id, kind, subject_id and dedupe identity. Use a guarded parked→open update and batch its ABO action/accepted-command fact; concurrent/finished work must not be reopened from a stale SELECT. Preserve the existing Access H check and platform audit delivery through R6-O1.
2. For reverse dispatch persist the exact canonical accepted void request bytes/version before first send in a new reversal_request row keyed by reversal_id (grant_id,reason,evidence_sha256,partial,contract_version,canonical_body,body_sha256). Reuse those bytes on retry, re-signing only with the current key; accept no replacement value/target/evidence fields from the retry request. Inherit R6/R4 receipt identity validation. Legacy parked rows without recoverable original bytes require maintainer/frontier evidence or explicit refusal, never recomputation from changed values.
3. Complete when an authorized retry of a recoverable parked reversal resumes its original mutation or obtains its original receipt, changed-payload recovery is impossible, partial/conflicting evidence stays review-only, and finished/leased work cannot be silently reopened. No new reversal or grant identity is generated.

### R8-LEGACY1 — P2: bootstrap package command references a deleted script

`ai-platform/package.json:10` executes absent scripts/bootstrap-routing-policy.sh. Supported replacement is existing Access-checked routing relays; missing browser launcher remains R2-P4. [Evidence](R8-legacy-review.md).

**Fix steps**
1. Remove the obsolete package alias; do not restore shared bearer/bootstrap HTTP.
2. Retain authenticated publication/promotion relays, without advertising a working browser launcher before R2-P4 decision.
3. Complete when no executable metadata points to the absent script and removed routes remain unreachable.

## Handoffs and static limits

All 24 escalation dispositions are closed in [coverage](R8-coverage.md), including the final 074:2 rotation semantics, 081:3 inspect audit exception, 086:2 successful-registration last-seen producer/consumer, and 087:1 backend/platform status distinction. Excluded harness/workflow effects were referenced without implementation review.

**R9:** finish audit/alert delivery and reconstruction of accepted commands, new immutable object hashes/pointers, activation predecessors and audit membership; retain original signed versions/bytes and exact receipts during recovery. Do not infer historical terms, actor, signer or predecessor from current state. Existing historical ambiguous data decisions require maintainer/frontier evidence; affected sales/mutations/rollback fail closed until adjudicated. **R10:** integrate key revocation with in-flight approval/rotation, config promotion/cache refresh with active requests, and R4/R6 accepted-command conservation. This phase executes neither R9 nor R10.

No new unresolved forward architecture choice remains in the recommended R8 source recipes. Inherited R2-P4 browser/bootstrap contract and prior R1/R3/provider/historical adjudication decisions remain explicit and unresolved; completion does not approve launch. **Decision 2026-10-18:** all of these are decided in [01 §3.8](../../architecture/ai-billing-orchestration/01-abo-design-decisions.md#38-decisions-from-the-integrated-review-r10). Historical terms-text disagreement follows D-5: the affected offer stays unsellable until the original text is adjudicated from retained evidence. No deployed permissions/keys/buckets/clock overrides/cache timing/cron/monitor availability or operational ceremonies were attested. Application unchanged relative to starting HEAD; existing R7 artifacts preserved. No tests/builds/lint/services/live research/source fixes/commits/pushes/branches/account-usage actions. Tests/testkit/viewer/harness/campaign/fixture correctness excluded; a narrow supporting append.ts read incidentally displayed embedded fixture helpers, not analyzed or used. A navigation range also displayed adjacent R9 payout/finding code; its correctness was not analyzed or credited. Overall review remains in progress; R9/R10 not started.
