# R1 — Tenant identity, token issuance and clinic authorization

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; ABO baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; historical provenance `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. Date: 2026-10-16 Africa/Cairo. Reviewer: fresh GPT-6.1 Sol contexts for SQL producers, non-backend consumers and bounded inherited SQL dependencies, with coordinator source verification and synthesis.

**Status: complete with findings.** The final report consolidates **0 P0, 5 P1 and 4 P2** source findings. Severity of SQL-04 is intentionally reduced from its subreport because its unequal-membership-role setup is schema-supported but lacks an independently demonstrated ordinary provisioning producer. Findings are not runtime reproductions. The SQL-02 multi-membership data-repair decision remains explicitly unresolved; no automatic flattening of roles is authorized. **Decision 2026-10-18:** resolved by [01 §3.8 D-1](../../architecture/ai-billing-orchestration/01-abo-design-decisions.md#38-decisions-from-the-integrated-review-r10); roles are still never flattened.

## Verified scope and traces

R0 prepared [exhaustive ownership](packet-index.md). Preparation ownership is not read coverage. [R1 aggregate coverage](R1-coverage.md) links actual inclusive read ranges in three source-review manifests. All six primary SQL files (5,261 physical lines), final billing/feed overrides, non-backend identity/registry/Dart regions, and named supporting callers/receivers were read. The completed inherited dependency coverage closes all five former continuation items. No unresolved source-coverage item remains within the bounded R1 assignment.

The review follows active-org choice → session refresh/hook → current-org and current-role helpers → token claims/signing → desktop adapter → actual verifier → tenant-bound receiver. The session claim selects the org; stored preference affects the next session, while live membership is rechecked per SQL request. Empty/malformed active_org fails closed and never falls back to legacy organization_id when the active claim is present. Private issuer key generation/switching, final integer RPC signatures and grants, Vault lookup, canonical billing/feed bytes, legacy installation RPC removal and actual remaining production consumers were traced in migration order.

| Boundary | Source-visible authority and result |
| --- | --- |
| Backend tenant context | `current_org_id()` checks signed sub/org against stored membership; it does **not** check live staff active/deleted state (SQL-03). `current_membership_role()` reads that association; staff lifecycle does **not** synchronize its role (SQL-02). |
| AI issuance | Active/nondeleted staff + org membership + active assigned branch + org-local AI scopes; backend-only signing key; staff id sub, org, branch, membership role; 600s. Final issuer lost its audience throttle (SQL-06). |
| Billing issuance | Same staff/branch checks, membership administrator, canonical EdDSA token, 300s, no scopes; 20/staff/audience/10min serialized count/insert. |
| Feed issuance | Private backend caller; canonical EdDSA token, `sub=backend-feed`, no org, audience feed, 120s; public/clinic execution explicitly revoked. |
| AI receiver | Signature, configured issuer/audience, registered key state/window, token contract, current-time skew and lifetime; current D1 live/held binding then installation state; immutable org/installation/role/scope principal. |
| Billing/feed receivers | Signature/profile/audience accepted, but no current-time comparison: expiration does not revoke these tokens (C1). Billing lookups use signed org/sub/JTI; feed is deliberately cross-tenant coverage metadata. |
| Registry lifecycle | Backend signing/next/retired and platform active/retiring/revoked are distinct amended states. Platform key cache bounds revocation delay; ABO pins require config rollout. Malformed platform issuer dates fail open (C3). |
| Tenant binding | First verified AI identity creates installation/binding atomically; same-org uniqueness resolves races; epoch increases on recreation. Global first-creation cap is not atomic and also blocks higher epochs (C2). |

No vendor source in these traced channels receives a Supabase user/session credential or clinic-domain write path. This does not attest deployed secrets. An already-issued AI token intentionally survives a membership change for at most its 600s plus allowed skew; vendor services do not have live membership access. New SQL issuance after a change is a different question, and SQL-02 defeats that authority update. C1 defeats the corresponding bounded billing/feed lifetime. Inherited tenant restrictive RLS generally confines rows to the current org, while direct staff UPDATE and unscoped permission readers break permission enforcement inside that org.

## Findings and remediation

All SQL paths below are relative to `backend/supabase/migrations/`; source line references are at T. Use **forward migrations**, not historical-file edits alone. Close SQL-01 before synchronizing authority rows; deploy common role-reader and lifecycle fixes together; repair data only through the explicit decision gate. C1 is independent and restores the intended stale-token bound. These recipes and severity assignments are canonical for R1 and supersede stale subreport recommendations, including SQL-03 association deletion and SQL-04 severity; subreports preserve investigation evidence.

## R1-C1 — P1: expired billing and feed tokens remain accepted

**Implementation-ready; high confidence; source defect.** Requirements 02 §3.2 and 04 §2.1 require signature **and times**, with billing reusable within its life and feed limited to 120 seconds. `packages/vendor-contracts/src/token-claims.ts:103–126,188–244` checks only `exp-iat`, with no current clock argument or comparison. `abo/src/clinic-api/auth.ts:261–277` returns authenticated claims directly after this success. `ai-platform/src/worker.ts:2234–2245` similarly authenticates the feed without comparing either token timestamp to `nowSeconds`, already available in that function before key lookup.

A former administrator retains an earlier authentic billing token and uses it after membership removal and expiry: contact reads/edits, billing history or checkout creation remain authorized while its pin exists and its 60 uses are not exhausted (`abo/src/worker.ts:217–299`, `clinic-api/rate.ts:29–64`). The desktop normally renews but an attacker need not use that client. A captured authentic feed token can continue reading the cross-tenant coverage feed until issuer-key expiry/revocation, potentially months beyond its intended 120 seconds. Future-issued but otherwise valid tokens also pass. The defect requires possession of an authentic token, not a signing-key leak; P1, not P0, because billing stays tenant-bound and use-limited, feed contains coverage metadata rather than clinic records, and key revocation can stop it.

**Fix steps**

1. In `packages/vendor-contracts/src/token-claims.ts`, extend `validateTokenClaims` input with required `nowSeconds` and `clockSkewSeconds`; reject nonfinite clocks/negative skew, and require `iat <= nowSeconds + skew`, `exp > nowSeconds - skew`, and existing finite `0 <= exp-iat <= audience maximum` predicates before success.
2. In `abo/src/clinic-api/auth.ts.authenticateBilling`, pass `floor(await clockNowMs(env)/1000)` using the existing ABO clock helper and explicit skew 60; in `ai-platform/src/worker.ts.verifyFeedBearerToken`, pass its existing `nowSeconds` and skew 60. These are the two production shared-helper callers found. Keep profile/audience/signature validation and role-specific error ordering; no fallback may authenticate a rejected timestamp.
3. Keep the custom AI verifier's current JSONB compatibility; normalize its equality-at-expiry behavior separately only if R2 deliberately aligns all profiles. No SQL claims change is needed for this fix.
4. Completion: canonical freshly minted billing/feed tokens succeed; expired by more than 60 seconds and future-issued by more than 60 seconds fail 401 before dispatch/feed reads; boundary at `exp+60` fails; wrong role/audience, missing claims and excessive lifetime remain rejected. Removed members cannot reuse captured billing tokens beyond the short expiration window. These are future acceptance criteria, not test results.

## R1-SQL-01 — P1: Any tenant member can modify staff authority directly

**High confidence; implementation-ready.** `20261002150000_tenant_scoping.sql:841–858` permits UPDATE of any non-deleted staff row whose auth user is a member of the caller's org, with the same membership predicate as WITH CHECK. It has no caller permission or protected-column predicate. The inherited authenticated table-wide UPDATE grant remains (`20260516100200_auth_rbac_rls.sql:28`); the final SELECT policy permits one's own row (`20261009120000_fix_staff_membership_session_rls.sql:58–76`). Staff `role`, `is_active`, and `is_bootstrap_admin` are ordinary writable columns (`20260516100000_auth_rbac_schema.sql:116–133`). The only identified staff triggers stamp audit fields, not authority.

A doctor can PATCH their own `role='administrator'` (or bootstrap flag); `assert_owner_or_administrator` then reads that modified live row (`20260611150000_remove_owner_role.sql:58–90`) and authorizes administrative RPCs. They can also disable colleagues without the last-administrator checks. No JWT refresh is needed for definer checks. This is an inherited flaw retained by a newly rewritten P1 security surface, within this review's explicit inherited-authority scope. It is tenant-level privilege escalation, not demonstrated cross-tenant compromise; P1, not P0.

**Fix steps:**
1. Add a forward migration revoking table-level UPDATE on `public.staff_members` from authenticated/PUBLIC/anon and removing the permissive `staff_members_update` policy. Keep profile/settings changes through guarded existing RPCs; do not grant individual authority columns.
2. Retain the existing `StaffAdminRepositoryImpl` RPC callers (`update_staff_member`, `set_staff_active`, `delete_staff_member`); the coordinator checked production frontend callers and found staff table SELECTs plus these RPC writes, with no direct staff UPDATE caller. No new profile endpoint is needed.
3. Preserve existing administrator-count, org/branch and permission checks in RPC bodies. Apply this grant closure **before** membership lifecycle synchronization, so a direct role edit cannot promote membership.
4. Completion: an ordinary member cannot directly update any staff authority/status column or another person's profile; authorized RPC updates still work; denied direct calls leave staff, memberships and audit facts unchanged.

## R1-SQL-02 — P1: Staff demotion never updates membership billing authority

**High confidence. Code remedy implementation-ready, depends on 01; existing multi-membership data repair is not implementation-ready pending per-row maintainer/clinic administrator role decisions.** Provisioning writes `ai_internal.membership.role` (`20261009120000_fix_staff_membership_session_rls.sql:436,676`), but final `auth_internal.update_staff_member` changes only `staff_members.role` and assignments (`20260611170000_restore_last_administrator_guard.sql:51–214`). No later membership synchronization trigger/write exists. Final billing mint checks membership role and only checks staff active/deleted, not its role (`canonical_billing_jwt_json.sql:104–136`). Thus an administrator legitimately demoted to doctor remains able to mint fresh administrator billing tokens forever; promotion fails inversely. AI token roles/scopes also remain stale. This exceeds the accepted short cached-token lifetime.

**Fix steps:**
1. After 01, add a forward override of `auth_internal.update_staff_member` that locks and verifies the target membership for `current_org_id()` and atomically updates that row's role with the authorized staff change. Do not overwrite roles of that user in other orgs.
2. Treat membership role as authorization authority throughout (04 below); retain `staff_members.role` only for the existing compatibility/profile representation, never as a substitute for the target org membership. Do not infer role from branch assignment creation.
3. Before deployment signoff, run a read-only reconciliation joining membership to staff by auth user, grouping membership count and listing `(user_id, organization_id, membership.role, staff.role)` where roles differ. Reconcile pre-existing mismatch rows: only auto-copy legacy staff role when a user has exactly one membership; flag multi-membership mismatches for the maintainer/clinic administrator to approve each intended per-org role rather than flattening their roles. Stop before changing those rows until the decision arrives; do not infer intention from the legacy global role. A repair migration must abort on any unresolved multi-membership mismatch instead of guessing or silently continuing; the maintainer and the affected clinic administrator must supply an explicit approved per-org mapping (including a decision to preserve a valid difference). Apply the approved mapping transactionally, then proceed with rollout. This row-specific data decision remains **not implementation-ready**; the bounded code/migration guard recipe is ready.

   **Decision 2026-10-18 ([01 §3.8 D-1](../../architecture/ai-billing-orchestration/01-abo-design-decisions.md#38-decisions-from-the-integrated-review-r10)) — step 3 is now implementation-ready.** Keep the read-only reconciliation and the single-membership copy. For multi-membership mismatches, decide each org's row alone: when exactly one of the two roles is `administrator`, write the non-administrator role. Hold the row when both roles are non-administrator and differ, or when the result would leave that org with no active `administrator` membership. The repair migration still aborts while any held row lacks an approved mapping from that clinic's administrator and the maintainer. This replaces per-row approval of every multi-membership mismatch; it never adds administrator authority or flattens roles across orgs.
4. Completion: demotion denies all new billing mints immediately after commit and emits reduced AI scopes; promotion permits new billing mints; a user with different roles in A/B keeps B unchanged. Already-minted tokens retain only the separately enforced 300/600s window.

## R1-SQL-03 — P1: Deactivated/deleted staff retain tenant membership on backend reads

**High confidence; implementation-ready, depends on 01.** Final deactivate (`20260611170000_restore_last_administrator_guard.sql:216–284`) and delete (`20260614100000_settings_code_review_fixes.sql:299–385`) never alter membership. `current_org_id`/`current_membership_role` (`20261002120000_membership_active_org.sql:201–317`) read membership only. Direct patient SELECT checks org but no live staff state (`20260523140000_patient_management.sql:50–56`); appointments additionally rely on JWT branch IDs whose helper does not recheck live assignments/staff (`tenant_scoping.sql:1918–1946`). A staff member deactivated or soft-deleted while their session is live can continue reading clinic records. `get_ai_billing_status` and refresh also authorize membership role without active staff checks. Minting itself does check staff and is blocked after deactivation; this does not close direct reads.

**Fix steps:**
1. In a forward migration make `current_org_id` require a non-deleted, active `staff_members` row for the JWT sub in addition to its existing membership check. Preserve bootstrap-only setup paths explicitly; do not restore an org fallback for a removed member.
2. Apply the same live-staff predicate to `sync_active_organization` and `set_active_organization`, so disabled users neither receive nor select tenant context. `current_membership_role` will then fail closed through current_org_id.
3. Preserve membership and active-preference rows for audit/authorized reactivation. Do not introduce a hard delete: the common predicate makes every retained association ineffective while `staff_members.is_active=false OR is_deleted=true`. Have `sync_active_organization` return NULL immediately for that state without selecting another tenant; `set_active_organization` returns forbidden without a write. Keep final staff update/deactivate/delete RPCs and last-administrator guards; their status transaction now revokes effective authority through the shared predicate.
4. Completion: existing sessions receive no tenant context or patient/appointment/billing-status data immediately after disable/delete; reactivation restores preserved memberships only for non-deleted staff; token mints remain blocked. Fix receiver expiry separately so cached vendor tokens cannot survive their intended lifetime.

## R1-SQL-05 — P1: Inherited permission helpers borrow another tenant's grants

**High confidence; implementation-ready after SQL-01/03/04.** Final definer permission readers omit the org predicate and use global staff role. A grant for the same role in B can satisfy A's explicit denial. Tenant/branch guards still confine rows to A, but A's administrator's permission matrix is bypassed for appointment, patient duplicate/safety/visit summaries, billing/insurance and service reads. The completed [dependency review](R1-sql-dependencies-review.md) establishes these exact final targets and absence of later overrides. Shift impact is incorrect editability indication, not proven mutation authority.

**Fix steps:**
1. Close direct staff mutation (SQL-01), establish live-staff context (SQL-03) and membership-role readers (SQL-04). Forward-override all five shared helpers and nine inline readers below. Every permission lookup must require `rp.organization_id=public.current_org_id()` and `rp.role=public.current_membership_role()` with active/nondeleted caller staff; NULL context/role denies. Retain `is_granted=true`, `is_deleted=false` and each existing permission-key OR set.

| Final migration | Exact override targets and locations at T |
| --- | --- |
| `20260601180000_appointment_medium_severity_fixes.sql` | `assert_appointment_access`, 23–62 |
| `20260605180300_billing_rls_permission_gate.sql` | `staff_has_invoices_view_access`, `staff_has_payments_read_access`, 3–35 |
| `20260712090000_service_catalog.sql` | `staff_has_services_read_access`, 122–138 |
| `20260606180000_shift_management.sql` | `staff_has_shifts_manage`, 164–181; `get_shift.is_read_only` consumer at 578 |
| `20260605181000_billing_us2_payment_rpcs.sql` | `get_billing_settings`, 368–410 (`payments.record` fallback) |
| `20260605230000_billing_us4_insurance_rpcs.sql` | `list_insurance_providers`, 309–359 (`invoices.create OR insurance.manage`) |
| `20260523150000_patient_registration_fields.sql` | `check_patient_duplicates`, 237–294 (`patients.create OR patients.edit`) |
| `20260704120000_simplify_vital_signs.sql` | `get_patient_safety_context`, 4–134 (`patients.view` fallback) |
| `20260707120000_delete_visit_attachment.sql` | `get_visit`, 104–EOF (`patients.view` fallback) |
| `20260712091000_service_catalog_pricing_rpcs.sql` | `get_service` (9), `resolve_effective_service_price_rpc` (198), `search_eligible_services` (285), `list_services` (399); checks22–32/214–224/304–314/422–432 |

2. Keep existing tenant/branch guards, restrictive RLS, invoker wrappers, signatures, ACLs and response shapes. Preserve `get_visit` clinical-child gating through its scoped helper. Private `resolve_effective_service_price` stays guarded implementation context; no pricing algorithm change.
3. Completion: A's denial wins even when B grants the same role for every listed reader; A's exact grant permits the corresponding read; global staff role cannot substitute for A's membership role; no B records return. Shift read-only indication must agree with A.

## R1-SQL-04 — P2: Backend administrative permission checks use global staff role

**High confidence in the reader mismatch; implementation-ready; dependent on SQL-01/02. P2:** ordinary provisioning inspected here does not independently establish unequal per-org roles. This is a concrete authority/compatibility barrier for the supported membership model and the required lifecycle repair, rather than a demonstrated ordinary provisioning escalation. `auth_internal.assert_permission` uses `rp.role=v_staff.role` (`tenant_scoping.sql:1948–1994`), while `assert_owner_or_administrator` trusts that same global role (`remove_owner_role.sql:58–90`). For a dual-membership database state with global staff role administrator, membership administrator in A and doctor in B (the per-membership schema permits this; ordinary provisioning creates new auth users and does not itself establish this unequal-role state), that user can switch to B and call `update_role_permission(s)`; their first check sees global administrator and writes B's permission matrix. AI/billing token issuers correctly use B's membership role, so the backend and vendors disagree on current authority. Clinical/upload permission helpers at `tenant_scoping.sql:2113–2148` also join the global role.

**Fix steps:**
1. Add forward overrides of `assert_permission`, `assert_owner_or_administrator`, `staff_has_visit_clinical_access` and `staff_has_visit_upload_access` (`tenant_scoping.sql:2113–2148`), plus `staff_can_access_branch` (`remove_owner_role.sql:820–844`), resolving role from `current_membership_role()` once current org is non-NULL. A NULL membership role must deny. In `staff_can_access_branch`, require live staff and replace JWT/global administrator fallback with `current_membership_role()='administrator'` plus active branch in current org; preserve the current-org assigned-branch path. Assignment-revocation semantics remain a separate lifecycle question.
2. Retain bootstrap exception only when active bootstrap staff exists **and no organization exists**. A bootstrap flag must not bypass an existing org's membership role.
3. Coordinate final inherited appointment/billing/services helpers with 05: every org-local permission lookup uses `(current_org_id(), current_membership_role())`; keep existing active staff checks.
4. Completion: global administrator/member doctor B cannot edit B role permissions or invoke B administrator-only provisioning, even with fresh/stale staff-role JWT claims. Member administrator B remains authorized independently of the global compatibility role; A remains unchanged. R7 handoff: the auth hook/`build_staff_claims`, JWT `staff_role` and session-context loader still use the global compatibility role for display; align org-specific role presentation with these authority changes without treating that UI as the enforcement boundary.

## R1-SQL-06 — P2: Final AI issuer drops its issuance rate limit

**High confidence; implementation-ready.** Previous final text[] issuer serialized per-staff ledger count and enforced configured rate ceiling/window (`tenant_scoping.sql:701–723`). The custody integer replacement `964–1114` signs and inserts on every permitted call with no lock/count/refusal. Billing retains a separate throttle. `03-abo-data-model-and-lifecycle.md:255` and spec 087 FR-007 preserve per-audience rate limits. An authenticated AI member can now incur unbounded signing and issuance-ledger writes; platform admission rate limits do not protect this backend endpoint. This is bounded resource/contract regression, not demonstrated uncontrolled coverage creation, hence P2.

**Fix steps:**
1. Add a forward override of `auth_internal.issue_ai_token(integer)` restoring the prior per-staff advisory transaction lock and configured ceiling/window, filtering ledger `aud='ai-platform'` and `is_deleted=false`.
2. Count and reject `RATE_LIMITED` before key secret loading/signing/insertion; leave 600s lifetime and membership/branch/scope validation unchanged. Billing's 20/10min counter remains independent.
3. Completion: the configured AI ceiling's next call fails without a new ledger row; concurrent mints cannot overshoot; billing mints do not consume AI quota and vice versa.

## R1-C2 — P2: first-tenant admission cap races and blocks higher epochs

**Implementation-ready; high confidence.** `identity/index.ts:328–355` reads the global epoch-1 count before a separately awaited insert batch, and checks the cap before discovering the new epoch. With 49 recent first bindings, concurrent valid tokens for two distinct new orgs both see 49 and both insert, exceeding the specified 50. At 50, an existing org with only retired bindings is denied even though its replacement would be epoch >1. 066:2 and 03 §3.2 define first creations by epoch 1; higher-epoch replacements neither count nor consume that cap. The partial unique index only serializes a single org, not the global limit. This weakens the leaked-issuer-key junk bound and temporarily blocks supported identity re-creation, without granting unpaid coverage.

**Fix steps**

1. Add an ordered platform D1 migration after existing migrations defining a `BEFORE INSERT ON tenant_binding` trigger, `WHEN NEW.epoch = 1`, which aborts with sentinel `tenant_creation_cap` if `COUNT(epoch=1 AND created_at > strftime('%Y-%m-%dT%H:%M:%fZ', NEW.created_at, '-24 hours')) >= 50`. Match the code's normalized UTC millisecond timestamps; keep the strict `>` cutoff.
2. In `identity/index.ts.resolveInstallationId`, compute `nextEpoch` first; remove the non-atomic cap as authority (an optional fast refusal is allowed only for `nextEpoch===1`). Retain installation+binding in the existing D1 atomic batch, so trigger abort rolls back the installation too. The recipe relies on the existing D1 batch transaction contract, not independent writes.
3. Distinguish that sentinel in the catch: raise AL-20 and return unauthenticated for cap abort; for other insertion conflicts retain reread of a competing live same-org binding. Do not swallow the cap into success or leave an orphan installation.
4. Completion: with 49 first bindings and concurrent distinct-org admissions, exactly one more succeeds; rejected attempts leave no installation/binding. At 50, valid higher-epoch re-creation succeeds; competing same-org first tokens resolve one installation; exactly 24-hour-old epoch-1 rows no longer count. R4/R6/R9 must apply the same authoritative trigger semantics to their binding writers/rebuild procedure.

## R1-C3 — P2: malformed registered issuer validity fails open

**Implementation-ready; high confidence.** `vendor/entrypoint.ts:2236–2255,2289–2305` accepts arbitrary nonempty `not_before/not_after` strings. `20261003130000_issuer_key_tenant_binding.sql:1–10` has only NOT NULL constraints. Both `identity/index.ts:199–224` and `worker.ts:2152–2186` skip a time restriction when `Date.parse` is NaN. An authorized operator accidentally registering `not_after='2030-13-01'` creates an active issuer key whose end restriction is silently absent for AI and feed; typo in start also removes delayed activation. This is bounded operator/configuration error, not an outsider registration bypass, hence P2. ABO pins intentionally have their separate config-removal lifecycle.

**Fix steps**

1. In `vendor/entrypoint.ts.registerIssuerKey` and `registerServiceKey`, validate both timestamps as canonical UTC ISO-8601 strings and require finite parsed values with `not_before < not_after` before consuming the assertion or inserting. Reject invalid input with the existing argument-invalid envelope (`assertion_invalid`) and audit it; preserve same-kid/key replay semantics for valid requests.
2. Change both issuer acceptance helpers (`identity.isIssuerKeyWithinValidityWindow`, `worker.issuerKeyUsable`) to fail closed for missing, nonstring or nonfinite dates; require `now>=start && now<end`. Keep the service helper's current explicit rejection of invalid dates.
3. Add a migration revoking any active/retiring issuer row with `julianday(not_before) IS NULL OR julianday(not_after) IS NULL OR julianday(not_before)>=julianday(not_after)`. Do not guess replacement dates or revive revoked kids. Before deploying this cleanup, operator inventories affected rows and registers a replacement kid with valid bounds if continuity requires it; rotate backend signing/pins via the established K-2 order.
4. Completion: malformed/reversed windows cannot be registered; legacy malformed rows fail closed even before cleanup; valid future/expired issuer rows fail; valid overlapping keys and retiring keys work only within their explicit windows. No code path treats an invalid date as unlimited.

## Escalation dispositions

All 14 R1-routed entries have a bounded disposition; their other phases remain unreviewed.

| IDs | R1 result and remaining propagation |
| --- | --- |
| 066:1, 066:4 | Registry encoding/results/statuses traced through platform verifiers and ABO relay/pin comparison. C3 qualifies date enforcement. R2/R8 retain common HP ceremony and method-policy review. |
| 066:2, 066:3 | First-install defaults, epochs and refusal path traced; C2 owns cap defects. R7 owns desktop refusal presentation; R9 owns rebuild consistency. |
| 066:5 | Re-transcription of 066:1–4; no independent runtime rule. |
| 066:6 | Final identity no longer derives authority from installation keys/plan/tier. Coverage/admission and removed control paths remain R5/R8. |
| 066:7, 066:8, 066:9, 087:2 | Reference-only/excluded harness effects; no harness/testkit/vector implementation inspected. |
| 076:1 | Host-before-version inspected as identity context; full version/error/export propagation remains R2/R3/R9. |
| 077:1 | SQL UUID JTI reaches billing authentication and checkout fact. Return-version/payment/replay propagation remains R2/R3/R9. |
| 087:1 | Private generation/switch and signing/next/retired traced through signer and distinct platform registry/pins; named grants/revokes checked. No public switch RPC. |
| 088:1 | Membership-role status authorization traced, qualified by SQL-02/03/04. Exact refresh throttling/projection/UI/error-version propagation remains R2/R7/R9. |

## Caller-to-receiver handoffs

- **R2:** carry C1's required clock through `validateTokenClaims` and both actual billing/feed callers. Preserve AI JSONB compatibility while reviewing strict wire profiles. Registry wrappers/helpers here are supporting reads; common HP assertion/replay/actor binding remains R2.
- **R3:** contact/checkout/payment must use authenticated billing `org/sub/jti`; C1 permits expired authority until fixed. Review the separate per-JTI read/check/update counter for concurrency against the 60-use contract; no additional finding asserted here.
- **R4/R6/R9:** all binding writers/rebuilds must preserve C2's epoch-1-only authoritative cap and atomic insertion. Held/deleted identity can authenticate so coverage reports transfer pending; identity success does not establish coverage/accounting correctness.
- **R5:** frozen AI principal is not a live membership oracle. SQL fixes govern new issuance; existing AI tokens last up to 600s plus 60s skew. D1 live binding resolves identity; review coverage/admission separately.
- **R7:** C1 owns feed authentication, while projection/event ordering remains open. Auth hook/`build_staff_claims`, JWT `staff_role` and session loader display global compatibility role; align presentation with org-specific authority. Review billing/AI composition invalidation for supported refresh/org switching; no production switch caller or surviving disposed consumer was established, so no speculative cache finding. Inspect `usage_summary_client.dart:63–77` top-level `term` expectation against `coverage-read/index.ts:139–145` `snapshot`/queued/recent response and actual gauge consumers.
- **R8/R9:** carry date cleanup and K-2 rotation ordering; ABO pin removal requires deployment, platform registry caches bound revocation delay. Runtime installed dispatch is registry-bound/parameterized and reaches guarded domain RPCs; removed installation enrollment/rotation/revocation signatures have no remaining production callers in searched frontend/platform/ABO source.

## Limits, unresolved decision and final gate

Completed [SQL](R1-sql-coverage.md), [consumer](R1-consumer-coverage.md) and [dependency](R1-sql-dependencies-coverage.md) manifests establish actual coverage. Searches/partial guard reads are distinct from full-body reads. Final patient overloads, appointment callees, billing lock guards, fifteen-table schema/RLS lineage, storage helper, public wrappers and installed dispatch reachability are closed for R1 authority. Unrelated domain algorithms were not audited.

**Only unresolved remedy decision:** SQL-02 existing multi-membership reconciliation requires an explicit per-org mapping approved by the maintainer and affected clinic administrator, including valid differences to preserve. Code/abort-guard recipe is ready; data repair and rollout signoff stop until that mapping exists. This does not leave review coverage incomplete. **Decision 2026-10-18:** the mapping rule is decided in [01 §3.8 D-1](../../architecture/ai-billing-orchestration/01-abo-design-decisions.md#38-decisions-from-the-integrated-review-r10); only the held rows it defines still need a clinic administrator's mapping.

Static source cannot attest deployed migration-executor ownership, Supabase global/default function ACLs, schema CREATE privileges, Vault/Access/service-binding permissions, secrets/key registrations/pin deployment, production environment values or runtime ceremonies. R9 owns these operational handoffs. No explicit source ALTER OWNER/FORCE RLS was found; definer owner/table-owner bypass assumptions remain deployment facts. Per-schema default revokes cannot remove globally inherited PUBLIC EXECUTE; explicit named issuer/feed/key/switch/dispatch revokes remain effective. Internal schema is not REST-exposed in source config and reviewed public entries enforce guards; no concrete bypass was established from the default-ACL caveat. Do not infer blanket internal-function inaccessibility or invent an infrastructure finding.

**Final result: complete with findings — 0 P0, 5 P1, 4 P2.** Major findings: C1 and SQL-01/02/03/05. Moderate: SQL-04/06 and C2/C3. R0 remains complete; R2–R10 not started; overall review in progress. Application source unchanged. No fixes, tests reviewed/run, builds, lint, services, campaigns or viewer review performed.
