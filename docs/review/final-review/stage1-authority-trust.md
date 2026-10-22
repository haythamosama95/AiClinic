# Stage 1 Final Review — Authority and Trust (RM00–RM07)

Branch `ai/abo-remediation` (tip `6cae8104`) compared with `master`. This is a second-round, light-pass review.
Each requirement got one targeted spot-check at the branch tip. Deeper reads were done only where a later
phase touched the same code. No `RMxx.todo.md` files exist for RM00–RM07.

## 1. Summary

| Metric | Count |
| --- | --- |
| RMs HANDLED | 8 (RM00–RM07) |
| RMs PARTIAL | 0 |
| RMs NOT HANDLED | 0 |
| RMs REGRESSED | 0 |
| Critical findings | 0 |
| Major findings | 1 (M-1) |

**Verdict: FAIL.** All eight phases are handled at the branch tip. The verdict is FAIL only because of M-1:
the last-administrator guard still reads the global staff role, while RM02 made the per-organization
membership role the authority.

Regression check: after RM07, only two backend migrations were added (`20261022120000_rm35_launch_state_reader.sql`
and `20261022130000_rm36_status_refresh_claim.sql`). Neither redefines any function that RM01, RM02 or RM07
overrode. The RM07 `issue_billing_token` override keeps RM01/RM02's membership-role gate.

## 2. Phase verification

| RM | Requirement | Status | Evidence (branch tip) |
| --- | --- | --- | --- |
| RM00 | CI baseline recorded; baseline failures fixed | HANDLED | `docs/review/abo-remediation/RM00.md` §1–§4; fix `bd0f30ad` is still present: `backend/tests/appointments_patient_mrn_payload_test.sql:59-72` (all-days schedule), `ai-platform/test/system/fallback-feed-coverage.system.test.ts:449,496` (`await clearAdmissionFault()`) |
| RM01 | R1-SQL-01: close direct `staff_members` UPDATE | HANDLED | `backend/supabase/migrations/20261014170200_r1_sql01_staff_update_grant_closure.sql:31-33`; INSERT policy is `WITH CHECK (false)` (`20260516100200_auth_rbac_rls.sql:215-218`) |
| RM01 | R1-SQL-03: disabled or deleted staff get no tenant context | HANDLED | `20261014170300_r1_sql03_live_staff_context.sql:94-102` (`current_org_id`), `:142-150` (`sync_active_organization`), `:226-247` (`set_active_organization`, forbidden with no write) |
| RM01 | R1-SQL-02: membership role synced atomically; D-1 repair | HANDLED | `20261014170400_…membership_sync.sql:105-114` (`FOR UPDATE`, `MEMBERSHIP_NOT_FOUND`), `:161-164` (current-org-only update); `20261014170500_…membership_role_repair.sql:43` (repair can never grant administrator), held-row abort |
| RM01 | R1-SQL-06: AI token rate limit restored | HANDLED | `20261014170600_r1_sql06_issue_ai_token_rate_limit.sql:94-114` (advisory lock, configured ceiling, `RATE_LIMITED` raised before signing) |
| RM02 | R1-SQL-04: authority checks use the membership role; bootstrap only before any org exists | HANDLED | `20261014170700_r1_sql04_membership_role_authority.sql:32-51` (shared predicate), `:83-98` (`assert_permission`), `:131-137` (`assert_owner_or_administrator`), `:146-168` (visit helpers), `:180-205` (`staff_can_access_branch`) |
| RM02 | R1-SQL-05: five helpers and nine inline readers scoped to the org | HANDLED | `20261014170800_r1_sql05_org_scoped_permission_readers.sql:33-840`: 14 overrides and 15 `staff_has_membership_permissions(...)` call sites; none redefined later |
| RM03 | R1-C1: token `iat`/`exp` freshness with skew | HANDLED | `packages/vendor-contracts/src/token-claims.ts:128-131,205-210`; `abo/src/clinic-api/auth.ts:268-269`; `ai-platform/src/worker.ts:1665,2676` |
| RM03 | R1-C3: issuer-key validity checks fail closed; canonical windows; cleanup migration | HANDLED | `ai-platform/src/worker.ts:2586-2615`; `ai-platform/src/identity/index.ts:199`; `ai-platform/src/vendor/entrypoint.ts:429,3538,4014`; `ai-platform/migrations/20261018120000_r1_c3_malformed_issuer_key_cleanup.sql` |
| RM03 | R8-KEY1: guarded retire transition batched with audit | HANDLED | `ai-platform/src/vendor/entrypoint.ts:3824-3852` (`… WHERE kid=? AND status='active'` in one `DB.batch`, then re-read and refuse on `revoked`) |
| RM03 | R1-C2: tenant creation cap enforced in D1 | HANDLED | `ai-platform/migrations/20261018120100_r1_c2_tenant_creation_cap_trigger.sql`; `ai-platform/src/identity/index.ts:273,368` |
| RM04 | R2-C1: canonical HP param comparison | HANDLED | `ai-platform/src/vendor/entrypoint.ts:1925,2030` (`canonicalParamsEqual`) |
| RM04 | R2-P2: ceiling-override approval bound to the call; timestamp-search fallback removed | HANDLED | `ai-platform/src/vendor/entrypoint.ts:2772-2842` (version, params, actor, freshness, active signer and digest checks; derives only the exact grant form) |
| RM04 | R2-P3: atomic bootstrap insert | HANDLED | `ai-platform/src/vendor/entrypoint.ts:3135-3156` (`INSERT … WHERE NOT EXISTS`, decided by `meta.changes`) |
| RM05 | R2-P1: signed params bound to the route subject before replay reservation | HANDLED | `abo/src/ops/index.ts:1079-1092`; `abo/src/ops/browser/ceremony.ts:274-294` |
| RM05 | R2-P4 / R2-ABO-03: Access-gated `GET /ops` shell, ceremony context, bootstrap page | HANDLED | `abo/src/worker.ts:480-482`; `abo/src/ops/browser/shell.ts:26-41` (`verifyOpsAccess` runs first); `abo/src/ops/index.ts:5495` |
| RM05 | R8-CONSOLE2: kill-switch disarm relay | HANDLED | `abo/src/ops/index.ts:5908-5918` (Class-H relay to `disarmKillSwitch`) |
| RM05 | R8-LEGACY1: dead bootstrap-routing script alias removed | HANDLED | No `bootstrap-routing` match in `ai-platform/package.json` |
| RM06 | R9-RT3: no private key outside development; published key rejected | HANDLED | `ai-platform/wrangler.toml:47` (only the development section has `PLATFORM_SIGNING_KEY`); `ai-platform/src/quota-do/coverage.ts:402-465` (rejects the published bytes and the published public key outside development; an unknown environment counts as non-development); `ai-platform/src/worker.ts:2027-2030` (runtime `ENVIRONMENT` injected) |
| RM07 | R2-C2: version metadata preserved on errors; `accepted_versions` allowed | HANDLED | `20261014170900_r2_c2_billing_token_error_versions.sql:31-168` (every `rpc_error` passes `p_contract_version`; membership-role gate kept); `abo/src/ops/index.ts:317-330`; `packages/vendor-contracts/src/result-envelope.ts:58-80` |
| RM07 | R2-C3 steps 1 and 3: strict DO response decoding | HANDLED | `ai-platform/src/quota-do/response-decoder.ts:2-17`; used in `ai-platform/src/vendor/entrypoint.ts:1469,1518`, `ai-platform/src/coverage/transfer.ts:118` (still in place after RM20/RM27 edits), `coverage-read/index.ts:77`, `credit/index.ts`, `admission/index.ts`, `quota-do/coverage.ts`. Step 2 (Dart) was deferred to RM37 as the plan directs |

## 3. Critical findings

None.

## 4. Major findings

### 4.1 M-1 — The last-administrator guard checks the global staff role, not the membership role

- **Location:** `backend/supabase/migrations/20261014170400_r1_sql02_update_staff_member_membership_sync.sql:116-128`
  sets `v_old_role := v_target.role` (the global `staff_members.role`) and calls
  `auth_internal.assert_not_last_administrator`, which is unchanged from
  `20260613210000_delete_staff_member.sql:54-82`. That guard also counts administrators by
  `staff_members.role`. Since RM02, the authority is the per-organization membership role
  (`20261014170700_…:32-51,135`).
- **Failure scenario:** a multi-org user Y holds the `administrator` membership in org A but has global
  `staff_members.role = doctor`. This mismatch is allowed: the D-1 repair keeps different per-org roles, and
  `update_staff_member` called from org B rewrites the global role. Y is A's only administrator membership.
  1. Y (or the RPC acting on Y) changes Y to `receptionist` in A. Because `v_old_role = doctor`, the guard
     is skipped. Line 161 sets A's membership to `receptionist`, so A has no administrator.
  2. Alternatively, the guard counts a user Z whose global role is `administrator` but whose A membership is
     `doctor`. The guard passes even though nobody keeps administrator authority in A.

  Afterwards, nobody in A can manage staff, edit permissions or mint billing tokens (all of these now require
  `current_membership_role() = 'administrator'`). Recovery needs a database repair by the maintainer.
  `set_staff_active` and `delete_staff_member` share the same guard and likely have the same gap; I did not
  read their bodies.
- **Blast radius:** only users who belong to more than one organization. Single-membership users keep the
  global and membership roles in sync through the D-1 copy and line 151/161.
- **Confidence:** medium. The code path is confirmed. How common multi-org administrators are in production
  is unknown.
- **Proposed fix:** add a forward migration that makes `assert_not_last_administrator` org-scoped and
  membership-based. It should take `(p_target_user_id, p_org_id)`, read the target's
  `ai_internal.membership.role` for that org, and count other `ai_internal.membership` rows with
  `role = 'administrator'` in that org that belong to live staff. Then override `update_staff_member`
  (old role taken from the locked membership row), `set_staff_active` and `delete_staff_member` to call it
  with `current_org_id()`. Add a test for a multi-org user whose membership role and global role differ.

## 5. Could not verify

- CI results: taken from the RMxx records. No CI was re-run. RM06 was accepted on two complementary
  partial runs (a user-directed exception recorded in `RM06.md`), not on one green run.
- Operator-only steps (staging/production D-1 reconciliation, malformed issuer-key inventory, K-2/K-3 key
  rotation, Access app provisioning): code seams exist, but these steps can't be verified from the repo.
- RM05 browser ceremony (`abo/src/ops/browser/shell.ts`, `ceremony.ts`): checked only for the Access gate and
  subject binding. The full client WebAuthn flow was not read.
- R1-SQL-05 inline readers: I confirmed the overrides exist and use the shared predicate. Each of the 14
  bodies was not compared line by line with its pre-RM02 definition.
- RM03 discovered issue (the grant-path `resolveOrInsertGrantBinding` returns an unclassified error at the
  cap): it fails closed and was handed to later phases, so it is out of Stage 1 scope.
