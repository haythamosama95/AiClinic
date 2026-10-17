# R8 console slice — operator routes, catalogue and audit

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e` (T), 2026-10-17 Africa/Cairo. Reviewer: explicitly GPT-6.1 Sol / medium. **Complete with findings: 1 P1, 5 P2.** All 46 assigned tuples / 1,753 lines were read directly from `git show T:path`; exact tuples and supporting ranges are in [coverage](R8-console-coverage.json). This is a bounded slice, not completion of platform method ownership. No source edits, fixes, tests/builds/lint, services, research, commits or branches.

Inherited canonical findings remain unfixed and are not counted here: R2-P1 target binding, P2 second ceiling approval, P3 bootstrap, P4 missing browser ceremony, C1/C2/C3 canonicalization/version handling; R4-PG1 global identity, PG3 accepted-command recovery, PG4 signer attribution and A2 receipt linkage; R6-O1 local acceptance/transfer handoff and DM/PT durable replay. There is no shipped browser form/ceremony producer whose rendered intent can be verified; the trace begins with actual HTTP handlers and supplied JSON, as R2-P4 already establishes.

## Source traces and method coverage

| Surface at `abo/src/ops/index.ts` | Established trace and boundary |
| --- | --- |
| `/ops/lookup`, clinic, parked, registries (297–398, 1404–1630, 1929–1964, 3316–3364) | `handleOps` verifies Access before all dispatch. Lookup returns org; clinic queries org-linked commercial facts and forwards the Access JWT to `inspectCoverage`. Registry reads use machine binding, then decode detail. Platform/version refusal silently becoming an empty array remains inherited R2-C3, not proof of an empty registry. |
| Publish/retire/reinstate (789–1078, 3372–3409) | Local HP verifies actor/op/freshness/active credential/replay, then consumes assertion and audits accepted before catalogue mutation. Published copies inherit plan/economics from latest existing offer row; body supplies price/text/copy. Terms R2 write precedes D1 terms, offer and event batches. Platform audit is called last. R2-P1 and R6-O1 apply here too. |
| Plan publish/retire; ceiling; issuer register/retire/revoke; service register/revoke (2479–2611, 3556–3676) | Field allowlists plus URL `kid` overrides construct final platform args; original operation/assertion/signer are forwarded unchanged. Platform HP, not ABO body type checks, establishes authorization. `action_id` is used for ABO audit only. Platform receiver policy review belongs to the configuration slice. The forwarded Access JWT supplies the platform actor; a body actor cannot replace it, while HP separately binds operation.actor_email under the inherited R2 checks. |
| Routing publish/canary/promote/rollback; arm switch; cohort activate/promote; capability deprecate/retire; token begin/retire (3678–3817) | Class-H relay forwards Access and exact allowlisted args through binding. No local HP requirement is added to H methods. `beginTokenContractRotation` intentionally takes no version under 074:2; earlier harness wording does not override that final amendment. Disarm is missing (C3). |
| Support reference (2612–2652, 3819–3822) | Access-authenticated GET forwards `reference` to platform H lookup, then writes random-ID ABO audit and returns the envelope. Sensitive payload visibility for live operator sessions is explicitly permitted by amended AD-8; no additional privacy bypass is established. |
| Other dispatch (3330–3355, 3362–3370, 3411–3554) | Findings/payouts/cancel/retry/coverage/credential routes call their named handlers without alternate unauthenticated dispatch. R6 owns lifecycle execution, lead owns credential/cancel/retry policy, R9 owns payout/finding recovery; route coverage does not claim those bodies as primary here. |
| SQL 0006/0007 | `operator_action`, `assertion_used` and `payment_release` have primary identities and update/delete abort triggers. Append-only identity is not a request-content binding or proof that subsequent effects finished. |

## Findings

### R8-C1 — P1: overlapping publications can replace previously published terms text

High confidence; implementation-ready. `nextTermsVersionNumber` reads global MAX+1 (815–819). Publication then writes `terms/en/<N>.txt` (934–939) before the unique `(terms_version,locale)` insertion (949–968; `abo/migrations/0001_records.sql:37–45`). Two separately approved publications, including different offers, can both select N. A writes text A and inserts its terms; B writes text B to the same key, then loses D1 uniqueness. A's immutable terms row now has A's hash but B's body. `clinic-api/offers.ts:52–71` reads that body without checking its hash and presents it as version N. The failed publication can therefore change the terms displayed for a successful sale. Ledger locking covers `ledger/`, not this terms key (03 §2.1). This is independent of the inherited consumed-touch crash window and R3-M3's current-versus-historical terms choice.

**Fix steps**
1. In `handleHpCatalogueAction`, store terms under a content-addressed key containing `textSha256`, rather than the allocated number. Every terms record must retain the exact key/hash pair; distinct text must never share a writable key.
2. Allocate the next terms and offer versions with uniqueness-conflict retry before exposing publication. Batch terms row+fact, offer row+fact and publication event+fact together; on collision reread both versions and retry the same accepted payload, retaining its content key.
3. Resume publication stages through R6-O1's accepted command keyed to the exact operation; a lost reply must not publish a fresh commercial version. Preserve historical immutable facts and flag existing hash/body discrepancies for maintainer adjudication rather than replacing signed history.
4. Verify the terms body against stored `text_sha256` in `termsText` before returning it. Completion: overlapping different/same-offer publications either commit coherent independent versions or fail without changing any published text; interruption cannot leave an offer pointing at another operation's terms.

### R8-C2 — P2: successful reinstatement never restores an offer for sale

High confidence; implementation-ready. The route invokes `reinstate_offer`; the handler appends `kind='reinstated'` (1030–1050). `listOffers` only includes latest `published` events (`clinic-api/offers.ts:74–98`), and checkout requires that same kind (`clinic-api/checkouts.ts:135–153`). A retired offer reinstated with a valid touch still disappears from selection and rejects new checkout. Spec 082 FR-007 explicitly supplies reinstatement; 03 §2.2's latest-published predicate and the reinstated event enum are inconsistent. Recommended resolution: reinstatement is publication of the existing previously published commercial version, never a new price/terms selection.

**Fix steps**
1. In `handleHpCatalogueAction`, append a `published` event for `reinstate_offer`, using the latest published version already resolved, while preserving `reinstate_offer` in the operator audit.
2. In both sale readers, recognize historical latest `reinstated` as the same activation alias, with the last published version. Clarify 03 §2.2 and spec 082 accordingly; do not mutate historical events or create new commercial content.
3. Completion: publish→retire→reinstate restores the same version/price/terms to offers and checkout; a later retirement hides it again; an offer never published remains refused.

### R8-C3 — P2: console can arm a kill switch but cannot lift it

High confidence; implementation-ready. `OpsEnv`, `RelayPlatformMethod` and the complete `handleOps` dispatcher expose only `armKillSwitch` (134–136, 176, 3726–3735). There is no disarm route; every unmatched path returns 404 (3824). Platform `VendorEntrypoint.disarmKillSwitch` exists and verifies H (`entrypoint.ts:4866–4881`); its action is the writer restoring `active=0` (`control/kill-switch.ts:157–196`). Once armed through the console, normal operator recovery requires a new deploy/custom binding caller or SQL despite the no-routine-SQL console goal (05 §3). This is a missing operational path, not an authorization bypass or a claim that the platform cannot recover.

**Fix steps**
1. Add `disarmKillSwitch` to the ABO binding interface and relay union. Add `POST /ops/kill-switches/disarm` through `handlePostConfigurationClassHRelay`, forwarding only `scope,target`, with `killSwitchSubject` and original Access identity.
2. Reuse the platform's existing disarm validation/audit/AL-19 behavior; do not implement a local switch-table write. Include the arm/disarm selection in the R2-P4 console producer once implemented.
3. Completion: each supported scope can be armed and lifted through Access-authenticated console routes; missing/expired Access refuses both, unknown/inactive transitions retain existing platform errors, and each action has ABO and platform audit.

### R8-C4 — P2: a reused relay action ID suppresses audit for a different operation

High confidence; implementation-ready. HP/H configuration handlers accept any string `action_id` (2542–2545, 2588–2591). `forwardPlatformRelay` executes the platform call first (2335), then `insertRelayOperatorAction` skips all recording when that ID already exists (2199–2216), without comparing actor/method/subject/params. An operator client reusing its last ID can successfully arm switch A and switch B, or perform distinct configuration writes, while ABO stores only the first action. Platform audit still exists; this bounded finding is the loss of required ABO lineage, not total audit evasion. It differs from R6-O1's interruption/recovery root.

**Fix steps**
1. Bind a relay command ID before dispatch to actor, method, subject, negotiated platform version and canonical final arguments; add a dedicated mutable command record rather than updating append-only `operator_action`.
2. An existing ID with different bound content returns conflict before any platform invocation. An exact retry resumes/returns the same command/result through durable acceptance, then writes its immutable audit once; remove the ID-only skip as a substitute for content verification.
3. Completion: changed target/method/actor/args under one ID never executes; exact retries retain one logical audit/result; fresh IDs preserve distinct actions even when the platform returns an idempotent success.

### R8-C5 — P2: clinic history omits payment and grant actions

High confidence; implementation-ready. Clinic operator query includes org, checkout IDs and payment-related work IDs, but not payment or grant IDs (1539–1553). Local release/manual chargeback explicitly audit subject `paymentId` (1113, 1267–1273), and the void/release-held relay audits subject `grantId` (2857–2916, especially 2905). Those direct actions are absent from the clinic's `operator_actions`, despite 05 §3.1 requiring this clinic's action history. Facts are retained, but the main recovery view hides why payment/coverage changed.

**Fix steps**
1. Extend `handleGetClinic` action membership with this org's payment IDs and `grant_request.grant_id` IDs using exact subqueries and bound org; include reverse-work subjects through reversal→payment linkage.
2. Add exact platform/lineage association for transferred/imported grants when no ABO grant_request exists, using validated coverage grant IDs from the already fetched inspection; do not use substring matching or global grant association.
3. Completion: release, chargeback, void/release-held and parked reversal retry appear for their owning clinic; another org's actions remain absent and org/checkout/work history remains visible.

### R8-C6 — P2: malformed published copy breaks catalogue reads for every buyer

High confidence; implementation-ready. Publish checks `copy` only with `isRecord` and price only with `typeof number` (893–900), then makes that offer sellable. A correctly approved `{copy:{}, price_minor:100}` is persisted. `listOffers` trusts its JSON type and dereferences `copy.en.name` (`offers.ts:47–49,114–119`), throwing for that sellable offer and aborting the entire catalogue response. There is no SQL shape constraint (`0001_records.sql:14,19`). One operator payload can therefore make every offer unavailable until corrected. Numeric fractional/negative price is also accepted despite integer-minor-unit conventions, but no provider acceptance is assumed.

**Fix steps**
1. Validate the signed publish params before `commitAcceptedHp`: `price_minor` must be a positive safe integer; require `copy.en` object and nonempty string `name` plus string `summary`; require nonempty terms text. Preserve additional supported locale entries only when each matches the same shape.
2. Reuse that validator in the catalogue reader for existing rows. Exclude/quarantine a malformed offer with an operational error/alert keyed to offer/version, allowing other valid offers to load; do not synthesize replacement commercial text.
3. Completion: malformed copy/price refuses without consuming authorization or publishing; one historical bad offer cannot abort the valid catalogue; accepted content round-trips unchanged.

## Escalation dispositions and handoff

Console-propagation checked: 066:1/4/5 issuer field/status relay; 067:2/3/9/12 service/plan fields; 070:1 ceiling field allowlist; 081:1/2 operator audit forwarding (R6-O1 recovery remains inherited); 081:3 actual JWT-forwarding inspection; 082:1 active-registry refusal inherited from R2. 067:5 grant-list audit/receipt semantics remain R4 canonical, and the lead's grant-list view owns grouping. 071:1 void-list policy remains R6/R4 canonical with exact dispatch checked here. 086:2 credential last-seen persistence belongs to lead's registration handler, not this slice. 087:1 backend custody remains R1 canonical and console exposes platform retire separately. 066:6 final legacy replacement, 093:1 residue guard are legacy-slice/lead closure. 066:7/8/9, 074:1/2 and 087:2 have excluded harness effects; no implementation inspected. 074:2's explicit no-version begin-rotation rule is retained as runtime context, not escalated as a new defect.

R9 must preserve coherent catalogue facts/terms hashes, accepted relay commands and audit delivery across export/rebuild; lead retains R3's cancel/retry recovery handoff. Historical terms-body hash disagreement needs maintainer/frontier adjudication of original text from authoritative retained evidence; stop sale of the affected offer until resolved, never guess legal text. That historical-data stop is explicit; forward source remedies are implementation-ready. R2-P4's browser/bootstrap decision remains unresolved and canonical. Platform-specific policy and switch propagation belong to the other R8 slices and lead synthesis.

Coverage note: a supporting read of `records/append.ts` intended for `insertFactLog:14–27` also displayed fixture helper declarations/body afterward; these were not analyzed or used as review evidence. Reference specs displayed campaign row labels during keyword navigation; no excluded tests, harnesses or campaign implementations were reviewed.
