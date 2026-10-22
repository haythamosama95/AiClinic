# Supabase inventory (backend/supabase)

Scope: items involved in AI, billing token, AI token, issuer key custody, clinic keypair enrollment (now removed), availability flag (now removed), acceptance recording, coverage feed, status/notices, launch check, identity and tenant context that the tokens depend on.
Source of truth: the migration files, latest state wins. "Source area" names the latest defining migration (short name = file after the timestamp prefix; the timestamp is kept so the file can be found). Assigned group is left empty on purpose.

Overall facts for the whole area:
- No Supabase edge functions exist (there is no functions folder). config.toml has the edge runtime enabled but nothing is deployed in the repo.
- Two internal schemas are used. `ai_internal` (tables, no client access except one SELECT policy) and `auth_internal` (SECURITY DEFINER logic, not exposed through the REST API: config.toml exposes only `public` and `graphql_public`). Public functions in `public` are thin wrappers that clients call.
- Result envelope for almost every RPC is the composite type `public.rpc_result` (success, data, error_code, error_message, contract_version).
- The clinic keypair (installation keys) and the `ai.availability` flag existed in earlier migrations and were DROPPED later. They are listed in the "Dropped" category because they were part of the history the code still shows, but they do not exist in the latest state.

Counts per category are at the end of this file.

---

## 1. Public RPCs and public helper functions (SB-RPC)

Clients call these through PostgREST (`/rpc/<name>`). "Callable by" is the effective EXECUTE grant after all revokes in the latest state.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-RPC-001 | `public.issue_billing_token(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC wrapper, SECURITY DEFINER, search_path public+auth_internal | 20261007180000_issuer_key_custody (wrapper); body in SB-INT-001 | | Callable by `authenticated` only (anon/PUBLIC revoked). Rejects NULL or version not in (0,1) with CONTRACT_VERSION_UNSUPPORTED, data `accepted_versions [0,1]`, contract_version 1. Then calls the internal minter. Only an administrator membership gets a token. |
| SB-RPC-002 | `public.issue_ai_token(p_contract_version integer DEFAULT NULL)` returns text | RPC wrapper, SECURITY DEFINER | 20261007180000_issuer_key_custody (wrapper); body in SB-INT-002 | | Callable by `authenticated` only. Returns the raw signed token text (not rpc_result). Bad version raises exception CONTRACT_VERSION_UNSUPPORTED with DETAIL `{"accepted_versions":[0,1]}`. Other failures are raised exceptions (see error table). |
| SB-RPC-003 | `public.get_ai_status(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC wrapper, SECURITY DEFINER | 20261008010000_read_time_status_notices | | Callable by `authenticated`. Any member of the active org (no role check). Version guard (0,1) as above. Returns read-time status from the coverage projection (SB-INT-011). |
| SB-RPC-004 | `public.get_ai_billing_status(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC, SECURITY DEFINER (no internal twin; logic is in the public function) | 20261008010000_read_time_status_notices | | Callable by `authenticated`. Administrator membership only (FORBIDDEN_ROLE otherwise). Returns the get_ai_status data plus plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, queued_count, held_count, subscription_ref, abo_base_url. subscription_ref = `AIC-` + first 8 chars of a base32 (Crockford alphabet) encoding of sha256('sub-ref:' + org id). |
| SB-RPC-005 | `public.request_ai_status_refresh(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC wrapper, SECURITY DEFINER | 20261007230000_coverage_feed_puller_status (wrapper); body 20261022130000_rm36_status_refresh_claim (SB-INT-012) | | EXECUTE granted to `authenticated` AND `anon` (PUBLIC revoked). Anonymous callers are stopped inside the body by the session check (returns UNAUTHENTICATED). Administrator only. Throttled per org to one accepted request per 10 seconds, then runs the feed pull once. |
| SB-RPC-006 | `public.record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb)` returns rpc_result | RPC wrapper, SECURITY DEFINER | 20260805150000_f2_review_resolution | | Callable by `authenticated`. Records that a clinician accepted an AI output and runs the registered domain RPC in the same transaction. Body in SB-INT-014. |
| SB-RPC-007 | `public.get_visit_chief_complaint(p_visit_id uuid)` returns rpc_result | RPC wrapper, SECURITY INVOKER | 20260805120000_e3_review_recorded_at_created_at; ACL fixed in 20260905120500_revoke_get_visit_chief_complaint_public_anon | | Callable by `authenticated` (PUBLIC and anon revoked). Context provider for the AI (visit chief complaint). Body in SB-INT-016. |
| SB-RPC-008 | `public.set_active_organization(p_organization_id uuid)` returns rpc_result | RPC, SECURITY DEFINER | 20261014170300_r1_sql03_live_staff_context | | Callable by `authenticated`. Writes ai_internal.user_active_organization if the caller holds a membership in that org and is live staff. Error FORBIDDEN otherwise. The next token refresh carries the new `active_org` claim. |
| SB-RPC-009 | `public.current_org_id()` returns uuid | Helper function, SECURITY DEFINER, STABLE | 20261014170300_r1_sql03_live_staff_context | | Callable by `authenticated`. Resolves the tenant: JWT `active_org` claim (if the claim key is present) else `organization_id` claim; must be a membership of the JWT sub and the sub must be live (non-deleted, active) staff; else NULL. Used by every token mint and status read. |
| SB-RPC-010 | `public.current_membership_role()` returns public.staff_role | Helper function, SECURITY DEFINER, STABLE | 20261002120000_membership_active_org | | Callable by `authenticated`. Role from ai_internal.membership for (JWT sub, current_org_id()); NULL if no org. This is the role authority for billing and AI tokens. |
| SB-RPC-011 | `public.get_custom_claims(event jsonb)` returns jsonb | Auth hook function, SECURITY INVOKER | 20261002120000_membership_active_org | | Registered in config.toml as the `custom_access_token` hook (`pg-functions://postgres/public/get_custom_claims`). Merges build_staff_claims output and sets or removes the `active_org` claim from sync_active_organization. An older overload `get_custom_claims(p_user_id uuid)` also exists from 20260521110000_auth_rbac_definer_internal_schema. |
| SB-RPC-012 | `public.jwt_organization_id()` returns uuid | Helper, SECURITY INVOKER, STABLE | 20261002120000_membership_active_org | | Now just returns public.current_org_id(). Used by RLS policies. |
| SB-RPC-013 | `public.jwt_branch_ids()` returns uuid[] | Helper, SECURITY INVOKER, STABLE | 20261002150000_tenant_scoping | | Reads the `branch_ids` claim. Used by the ai_accepted_output policy. |
| SB-RPC-014 | `public.request_jwt_claims()` returns jsonb | Helper, STABLE | 20260516100200_auth_rbac_rls (original) | | Reads `request.jwt.claims` setting; used by current_org_id and set_active_organization. |
| SB-RPC-015 | `public.rpc_success(p_data jsonb DEFAULT '{}', p_contract_version integer DEFAULT NULL)` and `public.rpc_error(p_code text, p_message text, p_contract_version integer DEFAULT NULL)` | Helper constructors for rpc_result, IMMUTABLE | 20261007180000_issuer_key_custody | | The two-argument forms were dropped and replaced by these with an optional contract version. |

---

## 2. Internal functions (SB-INT)

Not reachable by clients. EXECUTE is revoked from PUBLIC, anon, authenticated (and service_role where stated). They run as the migration owner.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-INT-001 | `auth_internal.issue_billing_token(p_contract_version integer)` returns rpc_result | SECURITY DEFINER, internal minter | 20261014170900_r2_c2_billing_token_error_versions | | Steps: valid session; role must be administrator (current_membership_role); org from current_org_id; live active staff row for the caller; primary active branch of the org; the `signing` issuer key and its secret from the vault; per-staff advisory lock (key 87201402, text `<staff id>:abo`); rate limit 20 per 10 minutes counted on ai_token_issuance rows with aud 'abo'; token claims iss (setting ai.issuer_id), aud `abo`, sub staff id, org, branch, role `administrator`, jti, iat, exp = iat+300, ver `2`; header alg EdDSA, kid, typ JWT; both parts canonical JSON (RFC 8785 style) via SB-INT-006; signed with Ed25519; ledger row inserted with aud `abo`. Returns data token, abo_base_url (setting ai.abo_base_url, default http://127.0.0.1:8788), expires_at. Every error carries the negotiated contract_version. |
| SB-INT-002 | `auth_internal.issue_ai_token(p_contract_version integer)` returns text | SECURITY DEFINER, internal minter | 20261014170600_r1_sql06_issue_ai_token_rate_limit | | Steps: valid session; org from current_org_id (else exception FORBIDDEN); live active staff; primary branch of the org; per-staff advisory lock (key 87201401, staff id); rate limit from settings ai.issuer.rate_limit.ceiling (default 100) per ai.issuer.rate_limit.window_seconds (default 3600) counted on rows with aud 'ai-platform'; signing issuer key + vault secret; scopes = all granted `ai.%` permission keys of (org, membership role) from roles_permissions, at least one required (else AI_ACCESS_DENIED). Claims: iss, aud `ai-platform`, sub staff id, org, branch, role (membership role), scopes (sorted array), jti, iat, exp = iat+600, ver `2`. Header alg EdDSA, kid, typ JWT. This token's JSON uses plain jsonb text (NOT the canonical function). Ledger row inserted with aud `ai-platform`. The p_contract_version argument is not used inside the body. |
| SB-INT-003 | `auth_internal.issue_feed_token()` returns text | SECURITY DEFINER, internal minter | 20261014170100_canonical_feed_jwt_json | | Mints a token for the coverage feed pull: aud `ai-platform-feed`, sub `backend-feed`, jti, iat, exp = iat+120, ver `2`, iss from ai.issuer_id, canonical JSON. No ledger row. Raises ISSUER_KEY_NOT_CONFIGURED if no signing key or secret. EXECUTE revoked from everyone including service_role. |
| SB-INT-004 | `auth_internal.insert_issuer_kid()` returns table(kid, public_key, status, not_before, not_after) | SECURITY DEFINER, key generator | 20261007180000_issuer_key_custody | | Returns the existing `next` key if one exists. Otherwise generates an Ed25519 keypair (pgsodium), stores the private key in the vault (secret name `issuer-key-<kid>`, description 'Ed25519 issuer private key'), inserts a row with status `signing` if no signing key yet else `next`, not_before now, not_after now + 13 months. The migration calls it once at install, so a first `signing` key exists after migration. |
| SB-INT-005 | `auth_internal.switch_issuer_signing_kid(p_kid text)` returns void | SECURITY DEFINER, rotation switch | 20261007180000_issuer_key_custody | | If the given kid has status `next`: current `signing` becomes `retired`, the given kid becomes `signing`. Otherwise silently returns. EXECUTE revoked from all client roles and service_role. |
| SB-INT-006 | `auth_internal.canonical_issuer_jwt_json(p_value jsonb)` returns text | IMMUTABLE STRICT helper | 20261014170000_canonical_billing_jwt_json | | Produces RFC 8785 canonical JSON: keys sorted bytewise, no whitespace, ASCII keys only, integers only (safe integer range). Exceptions: 'issuer JWT JSON keys must be ASCII', 'issuer JWT numbers must be safe integers', 'unsupported issuer JWT JSON value: <kind>'. Used by billing and feed tokens, not the AI token. |
| SB-INT-007 | `auth_internal.base64url_encode(bytea)` and `auth_internal.base64url_decode(text)` | IMMUTABLE helpers | 20260801120000_ai_keystore_schema (re-defined 20260801120200) | | Base64url without padding. EXECUTE revoked from client roles. |
| SB-INT-008 | `auth_internal.ai_app_setting_numeric(p_key text, p_default numeric)` and `auth_internal.ai_app_setting_text(p_key text, p_default text)` | STABLE SECURITY DEFINER readers | 20260801120200_ai_token_issuer_rpc | | Read ai_internal.app_settings by key where is_deleted = false, falling back to the default. Text reader strips surrounding double quotes. |
| SB-INT-009 | `auth_internal.assert_valid_ai_session()` returns uuid | STABLE SECURITY DEFINER | 20260801120200_ai_token_issuer_rpc | | Requires auth.uid() and a `sub` claim (else exception UNAUTHENTICATED); if `exp` claim is in the past raises SESSION_EXPIRED. Returns the user id. |
| SB-INT-010 | `auth_internal.verify_aat(p_token text)` returns boolean | STABLE SECURITY DEFINER, self-test verifier | 20261007180000_issuer_key_custody | | Verifies a token's Ed25519 signature against ai_internal.issuer_key by header kid (rejects retired or unknown kid, wrong alg, wrong iss vs ai.issuer_id). Does not check exp. Returns true/false, never raises. EXECUTE revoked from client roles. |
| SB-INT-011 | `auth_internal.get_ai_status(p_contract_version integer)` returns rpc_result | STABLE SECURITY DEFINER | 20261008010000_read_time_status_notices | | Computes at read time from clinic_ai_coverage plus feed_state. Output fields: available, state, reason, days_left, band, notices, next_change_at, as_of, stale, platform_base_url (setting ai.platform_base_url, default http://127.0.0.1:8787). `stale` = feed never succeeded or last success older than 2 minutes. State values produced: none, suspended, active, grace, lapsed, or the stored state text (e.g. exhausted, reversed, others). Notice codes: ends_soon (days_left 7, 3, or <=1 and no queued terms), in_grace (with grace_days_left), allowance_low (band 75 or 90), allowance_exhausted, lapsed, ended_reversed, suspended, status_stale. Each notice has audience `member` and channel `in_app`. No coverage row gives state `none` and reason `none`. Requires an org (FORBIDDEN otherwise). |
| SB-INT-012 | `auth_internal.request_ai_status_refresh(p_contract_version integer)` returns rpc_result | SECURITY DEFINER | 20261022130000_rm36_status_refresh_claim | | Session check, administrator role (FORBIDDEN_ROLE), org (FORBIDDEN). Claims the 10-second window with one conditional insert/upsert on ai_internal.status_refresh (accepts when last request is at least 10 s old). If not claimed, RATE_LIMITED. Then runs pull_coverage_feed once and returns requested_at. UNAUTHENTICATED / SESSION_EXPIRED are returned as rpc_error with the same text as code and message. |
| SB-INT-013 | `auth_internal.pull_coverage_feed()` returns void | SECURITY DEFINER | 20261007230000_coverage_feed_puller_status | | The feed puller. Locks the singleton feed_state row. If a pending HTTP request id exists: reads the response from the pg_net response table (net._http_response); no response and pending under 5 minutes = return; older than 5 minutes = clear pending and add one failure. A valid page needs status 200, JSON body, body contract_version equal to the platformFeed current version from ai.contract_versions, header `aip-contract-version` equal to it, body `after` equal to the stored cursor, and strictly increasing event feed_seq. Valid page: upsert each event's snapshot into clinic_ai_coverage (only if the new binding_epoch is higher, or equal epoch with higher clinic_seq), set cursor to `next_after`, last_success_at now, failures 0. Invalid page or timeout: failures + 1. Then sends a new GET `<ai.platform_base_url>/v1/feed/coverage?after=<cursor>&limit=200` with headers `Authorization: Bearer <feed token>` and `Aip-Contract-Version`; localhost / 127.0.0.1 in the URL is rewritten to host.docker.internal; stores the request id and pending_since. Event fields read: feed_seq, org_id, installation_id, binding_epoch, clinic_seq, at, snapshot{state, reason, term{ref, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, band}, queued_count, held_count, suspended}. For states active and grace the stored reason is NULL. |
| SB-INT-014 | `auth_internal.record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb)` returns rpc_result | SECURITY DEFINER | 20260805150000_f2_review_resolution | | Order: validate reference format (4+4 Crockford characters with a dash, e.g. XXXX-XXXX) else INVALID_INPUT; look up target in acceptance_targets else INVALID_INPUT; reject if the same reference was already accepted for the same table_name (INVALID_INPUT, 'already accepted'); org required (FORBIDDEN); run the domain RPC (SB-INT-015); if it fails return its error; take record id from data record_id, visit_id or id (else raises an exception so the whole transaction rolls back); branch from visits; insert audit_log row (action `ai.acceptance_record`, new_data_json ai_request_reference + acceptance_id); insert ai_accepted_output row. Returns the domain data plus acceptance_id, table_name, record_id, audit_log_id. |
| SB-INT-015 | `auth_internal.invoke_acceptance_domain_rpc(p_domain_function text, p_target_args jsonb)` returns rpc_result | SECURITY DEFINER, dynamic dispatch | 20261007180000_issuer_key_custody | | Only runs a function listed in acceptance_targets.domain_function. Finds the public function by name returning rpc_result, builds a call that pulls each argument by its parameter name from the JSON object and casts to the parameter type, executes it, re-wraps the result with contract_version NULL. INTERNAL_ERROR 'Domain function is not configured.' when not registered, not found, or no arguments. |
| SB-INT-016 | `auth_internal.get_visit_chief_complaint(p_visit_id uuid)` returns rpc_result | SECURITY DEFINER | 20260805120000_e3_review_recorded_at_created_at | | Checks visit branch scope (NOT_FOUND) and clinical access permission (FORBIDDEN). Returns visit_id, complaint (if any), recorded_at (UTC ISO string from visit_clinical_notes.created_at). |
| SB-INT-017 | `ai_internal.launch_state()` returns jsonb | STABLE SECURITY DEFINER, read-only | 20261022120000_rm35_launch_state_reader | | Returns keys database_name, contract_versions (value of ai.contract_versions), set_ai_availability_present (whether any function named set_ai_availability exists). Executable only by role `launch_check_reader`. |
| SB-INT-018 | `auth_internal.sync_active_organization(p_user_id uuid)` returns uuid | VOLATILE SECURITY DEFINER | 20261014170300_r1_sql03_live_staff_context | | Called by the token hook. Returns NULL for non-live staff. Keeps the stored active org while membership exists, else picks the first membership (by created_at, organization_id), else deletes the stored row and returns NULL. EXECUTE granted to `supabase_auth_admin` (if the role exists). |
| SB-INT-019 | `auth_internal.upsert_organization_membership(p_user_id uuid, p_organization_id uuid, p_role public.staff_role)` returns void | SECURITY DEFINER | 20261009120000_fix_staff_membership_session_rls | | Writes ai_internal.membership (conflict updates the role). Called by bootstrap and staff provisioning RPCs. |
| SB-INT-020 | `auth_internal.update_staff_member(...)` | SECURITY DEFINER | 20261014170400_r1_sql02_update_staff_member_membership_sync | | Staff update RPC that also updates ai_internal.membership.role for the current org in the same transaction (so a demoted administrator can no longer mint billing tokens). Error codes seen in it: INVALID_INPUT, STAFF_NOT_FOUND, CROSS_ORG_DENIED, MEMBERSHIP_NOT_FOUND, LAST_ADMINISTRATOR, INVALID_BRANCH, FORBIDDEN. |
| SB-INT-021 | `auth_internal.assert_owner_or_administrator()` returns staff_members row | SECURITY DEFINER | 20261014170700_r1_sql04_membership_role_authority | | Requires live active staff and membership role administrator (a bootstrap admin passes only while no organization exists). Raises FORBIDDEN. |
| SB-INT-022 | `auth_internal.build_staff_claims(p_user_id uuid)` returns jsonb | STABLE SECURITY DEFINER | 20260611150000_remove_owner_role | | Claims for the Supabase session token: staff_member_id, staff_role, organization_id (earliest non-deleted org; omitted while setup is required), branch_ids (comma list), setup_required. Administrators get all active branches of that org, others their assigned branches. |
| SB-INT-023 | `auth_internal.assert_permission(p_permission_key text)` and `auth_internal.staff_has_membership_permissions(...)` | SECURITY DEFINER | 20261014170700_r1_sql04_membership_role_authority | | Permission check against roles_permissions for (current org, membership role). Raises FORBIDDEN. |
| SB-INT-024 | `auth_internal.seed_roles_permissions_defaults(p_organization_id uuid)` and trigger function `auth_internal.trg_seed_roles_permissions_defaults()` | SECURITY DEFINER | 20261002150000_tenant_scoping | | Copies the default permission template (which includes the `ai.access` / `ai.visit_summary` keys) into roles_permissions for a new organization. |
| SB-INT-025 | `auth_internal.update_role_permission(...)` and `auth_internal.update_role_permissions(p_changes jsonb)` | SECURITY DEFINER | 20261002150000_tenant_scoping | | Administrator-facing changes to per-org permission rows; these decide which `ai.*` scopes later appear in the AI token. |
| SB-INT-026 | `auth_internal.user_has_organization_membership(p_user_id uuid, p_organization_id uuid)` | SECURITY DEFINER | 20261002150000_tenant_scoping | | Used by the staff_members select policy. EXECUTE granted to `authenticated`. |
| SB-INT-027 | `auth_internal.delete_clinic_test_fixtures(p_preserve_staff_ids uuid[])` | SECURITY DEFINER, test helper | 20261007180000_issuer_key_custody | | Deletes all ai_token_issuance rows and all ai_accepted_output rows (plus staff, branches, organizations, audit_log, public app_settings, subscription_cache) when present. Not an erasure feature; a test/dev reset helper. |
| SB-INT-028 | `public.save_visit_documentation(p_visit_id uuid, p_expected_updated_at timestamptz, p_complaint text, p_history text, p_examination text, p_diagnosis text, p_plan text)` | Domain RPC used as the only registered acceptance target | 20260711120000_coderabbit_review_fixes | | Registered in acceptance_targets under key `visit_clinical_notes`. Requires permission `visits.edit_soap`. Listed here because record_ai_acceptance dispatches to it by argument names p_visit_id, p_expected_updated_at, p_complaint, p_history, p_examination, p_diagnosis, p_plan. |

---

## 3. Tables (SB-TABLE)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-TABLE-001 | `ai_internal.app_settings` | Table, RLS on, deny-all policy | 20260801120000_ai_keystore_schema | | Global key/value config for AI and billing. No client access. Keys in section 9. |
| SB-TABLE-002 | `ai_internal.ai_token_issuance` | Table, RLS on | 20261007180000_issuer_key_custody (aud added, installation_id dropped); 20261002150000_tenant_scoping (organization_id, select policy) | | One row per minted token (both aud values). Authenticated users may SELECT rows of their own active org (policy SB-RLS-002). No insert/update/delete grant. |
| SB-TABLE-003 | `ai_internal.issuer_key` | Table, RLS on, deny-all policy | 20261007180000_issuer_key_custody | | Issuer signing key registry. Private key is not in the table; secret_ref points to a vault secret. |
| SB-TABLE-004 | `ai_internal.acceptance_targets` | Table (registry), no RLS, all privileges revoked from client roles; SELECT granted to postgres | 20260802150000_ai_acceptance_recording | | One seed row: target_key `visit_clinical_notes`, domain_function `save_visit_documentation`, table_name `visit_clinical_notes`. |
| SB-TABLE-005 | `public.ai_accepted_output` | Table, RLS on | 20260802150000_ai_acceptance_recording | | One row per accepted AI output. Authenticated SELECT only, via policy SB-RLS-003. Rows are written only by record_ai_acceptance. |
| SB-TABLE-006 | `ai_internal.clinic_ai_coverage` | Table, RLS on, deny-all | 20261007230000_coverage_feed_puller_status | | Per-organization projection of the coverage feed; one row per org. |
| SB-TABLE-007 | `ai_internal.feed_state` | Table, RLS on, deny-all, singleton | 20261007230000_coverage_feed_puller_status | | Single row (singleton = true) holding the feed cursor and pending request. Seeded with cursor 0 and 0 failures. |
| SB-TABLE-008 | `ai_internal.status_refresh` | Table, RLS on, deny-all | 20261007230000_coverage_feed_puller_status | | Throttle record, one row per org. |
| SB-TABLE-009 | `ai_internal.membership` | Table, RLS on, deny-all | 20261002120000_membership_active_org | | (user, organization, role). The role authority for tokens. Backfilled from staff_members at creation. |
| SB-TABLE-010 | `ai_internal.user_active_organization` | Table, RLS on, deny-all | 20261002120000_membership_active_org | | The organization the session acts in. |
| SB-TABLE-011 | `ai_internal.membership_role_repair_mapping` | Table, RLS on, deny-all | 20261014170500_r1_sql02_membership_role_repair | | Approved per-org roles used by a one-time data repair; check constraint forbids approved_role administrator. The repair migration raises MEMBERSHIP_ROLE_REPAIR_HELD_ROWS if unresolved rows remain. |
| SB-TABLE-012 | `auth_internal.roles_permissions_default_template` | Table, RLS on, deny-all | 20261002150000_tenant_scoping | | Default permission matrix copied to each new organization. |
| SB-TABLE-013 | `public.roles_permissions` | Table, RLS on | 20261002150000_tenant_scoping | | Per-organization role/permission rows. The `ai.%` keys here become the AI token scopes. |
| SB-TABLE-014 | `public.staff_members` | Table, RLS on | 20260516100000_auth_rbac_schema (+ later column additions) | | The token subject (`sub` = staff_members.id). |
| SB-TABLE-015 | `public.staff_branch_assignments` | Table, RLS on | 20260516100000_auth_rbac_schema | | Source of the token `branch` claim (primary active branch). |
| SB-TABLE-016 | `public.organizations` | Table, RLS on | 20260516100000_auth_rbac_schema | | Token `org` claim comes from here via membership. Has legacy columns subscription_tier and subscription_valid_until. |
| SB-TABLE-017 | `public.branches` | Table, RLS on | 20260516100000_auth_rbac_schema (+ working_schedule) | | Branch must be active and in the org. |
| SB-TABLE-018 | `public.audit_log` | Table, RLS on | 20260516100000_auth_rbac_schema (column renamed in 20260524150000) | | Receives the `ai.acceptance_record` row. Direct INSERT/UPDATE/DELETE denied to clients (20260524140100). |
| SB-TABLE-019 | `public.subscription_cache` | Table, RLS on | 20260516100000_auth_rbac_schema | | Legacy: comment says cached subscription status from an external billing system (future). No function reads it in the latest state; only cleanup helpers delete from it. Select policy by org; client writes denied. |

### Columns (SB-COL), one row per column

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-COL-001 | ai_internal.app_settings.key | text, primary key | SB-TABLE-001 | | Setting name. |
| SB-COL-002 | ai_internal.app_settings.value_json | jsonb, not null | SB-TABLE-001 | | Setting value. |
| SB-COL-003 | ai_internal.app_settings.created_at | timestamptz, default now() | SB-TABLE-001 | | |
| SB-COL-004 | ai_internal.app_settings.created_by | uuid, FK auth.users | SB-TABLE-001 | | |
| SB-COL-005 | ai_internal.app_settings.updated_at | timestamptz | SB-TABLE-001 | | |
| SB-COL-006 | ai_internal.app_settings.updated_by | uuid, FK auth.users | SB-TABLE-001 | | |
| SB-COL-007 | ai_internal.app_settings.is_deleted | boolean, default false | SB-TABLE-001 | | Soft delete; readers filter on it. |
| SB-COL-008 | ai_internal.app_settings.deleted_at | timestamptz | SB-TABLE-001 | | |
| SB-COL-009 | ai_internal.app_settings.deleted_by | uuid, FK auth.users | SB-TABLE-001 | | |
| SB-COL-010 | ai_internal.ai_token_issuance.issuance_id | uuid, primary key, default gen_random_uuid() | SB-TABLE-002 | | |
| SB-COL-011 | ai_internal.ai_token_issuance.jti | uuid, not null, unique | SB-TABLE-002 | | Token id placed in the token. |
| SB-COL-012 | ai_internal.ai_token_issuance.actor_staff_id | uuid, not null, FK staff_members | SB-TABLE-002 | | Who minted. |
| SB-COL-013 | ai_internal.ai_token_issuance.iat | timestamptz, not null | SB-TABLE-002 | | Issued-at; used by the rate-limit count. |
| SB-COL-014 | ai_internal.ai_token_issuance.created_at | timestamptz, default now() | SB-TABLE-002 | | |
| SB-COL-015 | ai_internal.ai_token_issuance.created_by | uuid, FK auth.users | SB-TABLE-002 | | Set to the caller's user id by the minters. |
| SB-COL-016 | ai_internal.ai_token_issuance.updated_at | timestamptz | SB-TABLE-002 | | |
| SB-COL-017 | ai_internal.ai_token_issuance.updated_by | uuid, FK auth.users | SB-TABLE-002 | | |
| SB-COL-018 | ai_internal.ai_token_issuance.is_deleted | boolean, default false | SB-TABLE-002 | | |
| SB-COL-019 | ai_internal.ai_token_issuance.deleted_at | timestamptz | SB-TABLE-002 | | |
| SB-COL-020 | ai_internal.ai_token_issuance.deleted_by | uuid, FK auth.users | SB-TABLE-002 | | |
| SB-COL-021 | ai_internal.ai_token_issuance.aud | text, not null | SB-TABLE-002 | | `ai-platform` or `abo`. Old rows were back-filled to `ai-platform`. |
| SB-COL-022 | ai_internal.ai_token_issuance.organization_id | uuid, not null, FK organizations ON DELETE CASCADE | SB-TABLE-002 | | |
| SB-COL-023 | ai_internal.issuer_key.kid | text, primary key, default gen_random_uuid()::text | SB-TABLE-003 | | |
| SB-COL-024 | ai_internal.issuer_key.public_key | text, not null | SB-TABLE-003 | | Base64url Ed25519 public key. |
| SB-COL-025 | ai_internal.issuer_key.secret_ref | uuid, not null | SB-TABLE-003 | | Id of the vault secret holding the private key (base64). |
| SB-COL-026 | ai_internal.issuer_key.status | text, not null, check in (signing, next, retired) | SB-TABLE-003 | | At most one `signing` and one `next` (partial unique indexes). |
| SB-COL-027 | ai_internal.issuer_key.not_before | timestamptz, not null | SB-TABLE-003 | | |
| SB-COL-028 | ai_internal.issuer_key.not_after | timestamptz, not null | SB-TABLE-003 | | Set to creation + 13 months. No code reads it. |
| SB-COL-029 | ai_internal.acceptance_targets.target_key | text, primary key | SB-TABLE-004 | | |
| SB-COL-030 | ai_internal.acceptance_targets.domain_function | text, not null | SB-TABLE-004 | | Name of the public function to run. |
| SB-COL-031 | ai_internal.acceptance_targets.table_name | text, not null | SB-TABLE-004 | | Provenance table name recorded in ai_accepted_output. |
| SB-COL-032 | public.ai_accepted_output.id | uuid, primary key | SB-TABLE-005 | | |
| SB-COL-033 | public.ai_accepted_output.organization_id | uuid, not null, FK organizations | SB-TABLE-005 | | |
| SB-COL-034 | public.ai_accepted_output.branch_id | uuid, FK branches | SB-TABLE-005 | | From the visit; may be NULL. |
| SB-COL-035 | public.ai_accepted_output.table_name | text, not null | SB-TABLE-005 | | |
| SB-COL-036 | public.ai_accepted_output.record_id | uuid, not null | SB-TABLE-005 | | The domain row written. |
| SB-COL-037 | public.ai_accepted_output.ai_request_reference | text, not null, check format `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` | SB-TABLE-005 | | The AI request's support reference. |
| SB-COL-038 | public.ai_accepted_output.accepted_by | uuid, not null, FK auth.users | SB-TABLE-005 | | |
| SB-COL-039 | public.ai_accepted_output.accepted_at | timestamptz, not null, default now() | SB-TABLE-005 | | |
| SB-COL-040 | public.ai_accepted_output.audit_log_id | uuid, not null, FK audit_log | SB-TABLE-005 | | |
| SB-COL-041 | ai_internal.clinic_ai_coverage.organization_id | uuid, primary key | SB-TABLE-006 | | |
| SB-COL-042 | ai_internal.clinic_ai_coverage.installation_id | uuid, not null | SB-TABLE-006 | | From the feed event. |
| SB-COL-043 | ai_internal.clinic_ai_coverage.binding_epoch | bigint, not null | SB-TABLE-006 | | Ordering key (higher wins). |
| SB-COL-044 | ai_internal.clinic_ai_coverage.clinic_seq | bigint, not null | SB-TABLE-006 | | Ordering key within an epoch. |
| SB-COL-045 | ai_internal.clinic_ai_coverage.state | text, not null | SB-TABLE-006 | | Snapshot state text. |
| SB-COL-046 | ai_internal.clinic_ai_coverage.reason | text | SB-TABLE-006 | | NULL for states active and grace. |
| SB-COL-047 | ai_internal.clinic_ai_coverage.term_ref | text | SB-TABLE-006 | | term.ref |
| SB-COL-048 | ai_internal.clinic_ai_coverage.plan_display_name | text | SB-TABLE-006 | | |
| SB-COL-049 | ai_internal.clinic_ai_coverage.starts_at | timestamptz | SB-TABLE-006 | | |
| SB-COL-050 | ai_internal.clinic_ai_coverage.ends_at | timestamptz | SB-TABLE-006 | | |
| SB-COL-051 | ai_internal.clinic_ai_coverage.grace_ends_at | timestamptz | SB-TABLE-006 | | |
| SB-COL-052 | ai_internal.clinic_ai_coverage.allowance | integer | SB-TABLE-006 | | |
| SB-COL-053 | ai_internal.clinic_ai_coverage.used | integer | SB-TABLE-006 | | |
| SB-COL-054 | ai_internal.clinic_ai_coverage.band | text | SB-TABLE-006 | | Used-allowance band; notices react to '75' and '90'. |
| SB-COL-055 | ai_internal.clinic_ai_coverage.queued_count | integer, not null | SB-TABLE-006 | | |
| SB-COL-056 | ai_internal.clinic_ai_coverage.held_count | integer, not null | SB-TABLE-006 | | |
| SB-COL-057 | ai_internal.clinic_ai_coverage.suspended | boolean, not null | SB-TABLE-006 | | |
| SB-COL-058 | ai_internal.clinic_ai_coverage.event_at | timestamptz, not null | SB-TABLE-006 | | Event `at`. |
| SB-COL-059 | ai_internal.clinic_ai_coverage.applied_at | timestamptz, not null | SB-TABLE-006 | | now() at apply time. |
| SB-COL-060 | ai_internal.feed_state.singleton | boolean, primary key, check singleton | SB-TABLE-007 | | Always true. |
| SB-COL-061 | ai_internal.feed_state.cursor | bigint, not null | SB-TABLE-007 | | Last applied feed position. |
| SB-COL-062 | ai_internal.feed_state.pending_request_id | bigint | SB-TABLE-007 | | pg_net request id in flight. |
| SB-COL-063 | ai_internal.feed_state.pending_since | timestamptz | SB-TABLE-007 | | |
| SB-COL-064 | ai_internal.feed_state.last_success_at | timestamptz | SB-TABLE-007 | | Drives `stale`. |
| SB-COL-065 | ai_internal.feed_state.consecutive_failures | integer, not null | SB-TABLE-007 | | |
| SB-COL-066 | ai_internal.status_refresh.organization_id | uuid, primary key | SB-TABLE-008 | | |
| SB-COL-067 | ai_internal.status_refresh.requested_at | timestamptz, not null | SB-TABLE-008 | | |
| SB-COL-068 | ai_internal.membership.user_id | uuid, FK auth.users ON DELETE CASCADE, part of PK | SB-TABLE-009 | | |
| SB-COL-069 | ai_internal.membership.organization_id | uuid, FK organizations ON DELETE CASCADE, part of PK | SB-TABLE-009 | | |
| SB-COL-070 | ai_internal.membership.role | public.staff_role, not null | SB-TABLE-009 | | |
| SB-COL-071 | ai_internal.membership.created_at | timestamptz, default now() | SB-TABLE-009 | | |
| SB-COL-072 | ai_internal.user_active_organization.user_id | uuid, primary key, FK auth.users ON DELETE CASCADE | SB-TABLE-010 | | |
| SB-COL-073 | ai_internal.user_active_organization.organization_id | uuid, not null, FK organizations ON DELETE CASCADE | SB-TABLE-010 | | |
| SB-COL-074 | ai_internal.user_active_organization.updated_at | timestamptz, default now() | SB-TABLE-010 | | |
| SB-COL-075 | ai_internal.membership_role_repair_mapping.user_id | uuid, part of PK | SB-TABLE-011 | | |
| SB-COL-076 | ai_internal.membership_role_repair_mapping.organization_id | uuid, part of PK | SB-TABLE-011 | | |
| SB-COL-077 | ai_internal.membership_role_repair_mapping.approved_role | staff_role, not null | SB-TABLE-011 | | Cannot be administrator. |
| SB-COL-078 | ai_internal.membership_role_repair_mapping.approved_by | text, not null | SB-TABLE-011 | | |
| SB-COL-079 | ai_internal.membership_role_repair_mapping.approved_note | text | SB-TABLE-011 | | |
| SB-COL-080 | ai_internal.membership_role_repair_mapping.approved_at | timestamptz, default now() | SB-TABLE-011 | | |
| SB-COL-081 | auth_internal.roles_permissions_default_template.role | staff_role, part of PK | SB-TABLE-012 | | |
| SB-COL-082 | auth_internal.roles_permissions_default_template.permission_key | text, part of PK | SB-TABLE-012 | | |
| SB-COL-083 | auth_internal.roles_permissions_default_template.is_granted | boolean, not null | SB-TABLE-012 | | |
| SB-COL-084 | public.roles_permissions.id | uuid, primary key | SB-TABLE-013 | | |
| SB-COL-085 | public.roles_permissions.role | staff_role, not null | SB-TABLE-013 | | |
| SB-COL-086 | public.roles_permissions.permission_key | text, not null | SB-TABLE-013 | | `ai.%` keys become token scopes. |
| SB-COL-087 | public.roles_permissions.is_granted | boolean, not null | SB-TABLE-013 | | |
| SB-COL-088 | public.roles_permissions.created_at / created_by / updated_at / updated_by / is_deleted / deleted_at / deleted_by | standard audit and soft-delete columns | SB-TABLE-013 | | Seven columns. |
| SB-COL-089 | public.roles_permissions.organization_id | uuid, not null, FK organizations ON DELETE CASCADE | SB-TABLE-013 | | Unique with (role, permission_key). |
| SB-COL-090 | public.staff_members.id, auth_user_id, full_name, role, phone, is_active, is_bootstrap_admin, must_change_password | main columns (id PK; auth_user_id unique FK auth.users; role staff_role; is_active default true; is_bootstrap_admin default false; must_change_password default false added in 20260524110400) | SB-TABLE-014 | | Plus the standard created_at, created_by, updated_at, updated_by, is_deleted, deleted_at, deleted_by. Other columns (e.g. username) may have been added by later staff migrations outside this inventory's scope. |
| SB-COL-091 | public.staff_branch_assignments.id, staff_member_id, branch_id, is_primary | main columns | SB-TABLE-015 | | Unique (staff_member_id, branch_id); plus the standard audit and soft-delete columns. `is_primary` orders branch choice for the token. |
| SB-COL-092 | public.organizations.id, name, logo_url, currency_code, timezone, subscription_tier, subscription_valid_until, settings_json | main columns | SB-TABLE-016 | | Plus the standard audit and soft-delete columns. |
| SB-COL-093 | public.branches.id, organization_id, name, code, address, phone, maps_url, is_active, working_schedule | main columns | SB-TABLE-017 | | Plus the standard audit and soft-delete columns. |
| SB-COL-094 | public.audit_log.id, user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json, ip_address, created_at | all columns (the original `timestamp` column was renamed `created_at`) | SB-TABLE-018 | | |
| SB-COL-095 | public.subscription_cache.organization_id, tier, valid_until, last_checked_at | all columns | SB-TABLE-019 | | organization_id is primary key, FK organizations ON DELETE CASCADE. |

Indexes worth knowing: ai_token_issuance (actor_staff_id, iat DESC) and (actor_staff_id, aud, iat DESC), both partial on is_deleted = false; ai_accepted_output (ai_request_reference) and (table_name, record_id) plus unique (table_name, record_id, ai_request_reference); issuer_key partial unique indexes allowing one `signing` row and one `next` row.

---

## 4. Triggers (SB-TRIG)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-TRIG-001 | `seed_roles_permissions_defaults` on `public.organizations` | AFTER INSERT, per row, runs auth_internal.trg_seed_roles_permissions_defaults | 20261002150000_tenant_scoping | | Creates the default permission rows (including the `ai.*` keys) for each new organization. |
| SB-TRIG-002 | `fill_tenant_organization_id` on appointments, visits, visit_clinical_notes, visit_vital_signs, visit_investigations, visit_attachments, treatment_plans, invoice_items, payments, invoice_number_sequences, patient_allergies, patient_medications, patient_chronic_conditions, service_branches, shift_assignments | Tenant fill triggers (function auth_internal.trg_fill_tenant_organization_id) | 20261002150000_tenant_scoping | | Not AI-specific; listed because the AI acceptance target and context provider read visit_clinical_notes and visits, which carry this trigger. |
| SB-TRIG-003 | `installation_keys_single_installation` on `ai_internal.installation_keys` | BEFORE INSERT OR UPDATE | created 20260801120000_ai_keystore_schema; DROPPED in 20261007180000_issuer_key_custody | | Dropped. Raised SINGLE_INSTALLATION_VIOLATION when a second installation id appeared. See Dropped category. |

No trigger exists on ai_token_issuance, ai_accepted_output, issuer_key, clinic_ai_coverage or feed_state.

---

## 5. RLS policies (SB-RLS)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-RLS-001 | `app_settings_deny_all` on ai_internal.app_settings | FOR ALL USING (false) | 20260801120000_ai_keystore_schema | | |
| SB-RLS-002 | `ai_token_issuance_select` on ai_internal.ai_token_issuance | FOR SELECT TO authenticated USING is_deleted = false AND organization_id = current_org_id() | 20261002150000_tenant_scoping | | Replaced the deny-all policy. Schema USAGE and table SELECT are granted to authenticated. |
| SB-RLS-003 | `ai_accepted_output_select` on public.ai_accepted_output | FOR SELECT TO authenticated USING organization_id = jwt_organization_id() AND (branch_id IS NULL OR branch_id = ANY(jwt_branch_ids())) | 20260802150000_ai_acceptance_recording | | No insert/update/delete policy or grant (SELECT only granted). |
| SB-RLS-004 | `issuer_key_deny_all` on ai_internal.issuer_key | FOR ALL USING (false) | 20261007180000_issuer_key_custody | | |
| SB-RLS-005 | `clinic_ai_coverage_deny_all` on ai_internal.clinic_ai_coverage | FOR ALL USING (false) | 20261007230000_coverage_feed_puller_status | | |
| SB-RLS-006 | `feed_state_deny_all` on ai_internal.feed_state | FOR ALL USING (false) | 20261007230000_coverage_feed_puller_status | | |
| SB-RLS-007 | `status_refresh_deny_all` on ai_internal.status_refresh | FOR ALL USING (false) | 20261007230000_coverage_feed_puller_status | | |
| SB-RLS-008 | `membership_deny_all` on ai_internal.membership | FOR ALL USING (false) | 20261002120000_membership_active_org | | |
| SB-RLS-009 | `user_active_organization_deny_all` on ai_internal.user_active_organization | FOR ALL USING (false) | 20261002120000_membership_active_org | | |
| SB-RLS-010 | `membership_role_repair_mapping_deny_all` on ai_internal.membership_role_repair_mapping | FOR ALL USING (false) | 20261014170500_r1_sql02_membership_role_repair | | |
| SB-RLS-011 | `roles_permissions_default_template_deny_all` on auth_internal.roles_permissions_default_template | FOR ALL USING (false) | 20261002150000_tenant_scoping | | |
| SB-RLS-012 | `roles_permissions_select` on public.roles_permissions | FOR SELECT TO authenticated USING is_deleted = false AND organization_id = current_org_id() AND (is_granted OR membership role administrator) | 20261002150000_tenant_scoping | | |
| SB-RLS-013 | `staff_members_select` on public.staff_members | FOR SELECT TO authenticated: own row, or a member of the same current org | 20261009120000_fix_staff_membership_session_rls | | The earlier `staff_members_update` policy and the table UPDATE grant were removed in 20261014170200_r1_sql01_staff_update_grant_closure. |
| SB-RLS-014 | `staff_branch_assignments_select` on public.staff_branch_assignments | FOR SELECT TO authenticated | 20261009120000_fix_staff_membership_session_rls | | Setup-required path or own assignments in the current org. |
| SB-RLS-015 | `organizations_select`, `organizations_insert`, `organizations_update`; `branches_select`, `branches_insert`, `branches_update` | Tenant policies using jwt_organization_id() | 20260516100200_auth_rbac_rls | | jwt_organization_id() now delegates to current_org_id(), so these follow the membership-based tenant. |
| SB-RLS-016 | `audit_log_select` plus `audit_log_deny_insert`, `audit_log_deny_update`, `audit_log_deny_delete` on public.audit_log | Select policy plus deny policies | 20260516100200_auth_rbac_rls; 20260524140100_fix_audit_log_write_protection | | |
| SB-RLS-017 | `subscription_cache_select` plus `subscription_cache_deny_insert`, `subscription_cache_deny_update`, `subscription_cache_deny_delete` | Select by org plus deny policies | 20260516100200_auth_rbac_rls; 20260524140100_fix_audit_log_write_protection | | |
| SB-RLS-018 | Tenant `*_org` policies on appointments, visits, visit_clinical_notes, etc. | `<table>_org` policies using current_org_id() | 20261002150000_tenant_scoping | | Not AI-specific; listed for the tables the AI context provider reads. |
| SB-RLS-019 | `installation_keys_deny_all` on ai_internal.installation_keys | FOR ALL USING (false) | created 20260801120000; table DROPPED 20261007180000 | | Dropped with its table. |

Note: `ai_internal.acceptance_targets` has no RLS; access is closed by REVOKE of all table privileges from PUBLIC, anon, authenticated, service_role (SELECT kept for postgres). Schema `ai_internal` itself: all privileges revoked from PUBLIC, anon, authenticated, service_role; USAGE granted to postgres, to authenticated (for the issuance SELECT), to launch_check_reader.

---

## 6. Edge functions (SB-FN)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-FN-001 | None | There is no `functions` folder under backend/supabase and no edge function code in the repo | backend/supabase | | config.toml has `[edge_runtime] enabled = true`, policy per_worker, inspector_port 8083, deno_version 2, and no secrets configured. The coverage pull is done in SQL via pg_net (see SB-CRON-001), not by an edge function. |

---

## 7. Types, extensions, roles, schemas, hooks (SB-TYPE / SB-EXT / SB-ROLE / SB-HOOK)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-TYPE-001 | `public.rpc_result` | Composite type: success boolean, data jsonb, error_code text, error_message text, contract_version integer | 20260516100000_auth_rbac_schema; contract_version attribute added in 20261007180000_issuer_key_custody | | Return envelope of nearly every RPC. |
| SB-TYPE-002 | `public.staff_role` | Enum: administrator, doctor, receptionist, lab_staff | 20260611150000_remove_owner_role | | `owner` was removed. Role stored in membership and staff_members. |
| SB-EXT-001 | `pgsodium` | Extension | 20260801120000_ai_keystore_schema | | Used for Ed25519 key generation, signing and verification (crypto_sign_new_keypair, crypto_sign_detached, crypto_sign_verify_detached). `pgsodium_keymaker` granted to postgres. |
| SB-EXT-002 | `pg_cron` | Extension | 20261007230000_coverage_feed_puller_status | | Runs the feed pull job. |
| SB-EXT-003 | `pg_net` | Extension | 20261007230000_coverage_feed_puller_status | | Sends the feed GET request; responses read from net._http_response. |
| SB-EXT-004 | Supabase Vault (`vault` schema) | Used, not created in a migration | 20261007180000_issuer_key_custody | | Stores issuer private keys (vault.create_secret, vault.decrypted_secrets). |
| SB-EXT-005 | `extensions.digest` (pgcrypto) | Used by get_ai_billing_status for sha256 | 20261008010000_read_time_status_notices | | |
| SB-ROLE-001 | `launch_check_reader` | NOLOGIN role | 20261022120000_rm35_launch_state_reader | | Only privilege: schema USAGE on ai_internal and EXECUTE on ai_internal.launch_state(). The operator creates a LOGIN role outside the repo and grants this role to it. |
| SB-ROLE-002 | `supabase_auth_admin` grant | EXECUTE on auth_internal.sync_active_organization(uuid) | 20261014170300_r1_sql03_live_staff_context (originally 20261002120000) | | Granted only if the role exists. |
| SB-SCH-001 | Schemas `ai_internal`, `auth_internal` | Internal schemas | 20260801120000_ai_keystore_schema (ai_internal) | | Neither is exposed through the REST API (config.toml api.schemas = public, graphql_public). |
| SB-HOOK-001 | Auth hook `custom_access_token` | config.toml `[auth.hook.custom_access_token]` enabled, uri `pg-functions://postgres/public/get_custom_claims` | config.toml | | Populates claims staff_member_id, staff_role, organization_id, branch_ids, setup_required (build_staff_claims) and active_org. |
| SB-HOOK-002 | Auth settings that affect tokens | config.toml `[auth]` jwt_expiry = 3600, enable_refresh_token_rotation = true, refresh_token_reuse_interval = 10, enable_signup = true, minimum_password_length = 6 | config.toml | | Session lifetime seen by `assert_valid_ai_session` (it checks the `exp` claim). |

---

## 8. Cron and scheduled jobs (SB-CRON)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-CRON-001 | `ai_coverage_feed_pull` | pg_cron job, schedule `30 seconds`, command `SELECT auth_internal.pull_coverage_feed()` | 20261007230000_coverage_feed_puller_status | | The only cron job found in the migrations. Also invoked on demand by request_ai_status_refresh. Not unscheduled by any later migration. |

No pg_cron job exists for key rotation, token or issuance-ledger cleanup, erasure, or issuer key switching. `switch_issuer_signing_kid` has no caller inside the migrations.

---

## 9. Settings and secrets (SB-ENV)

Rows of `ai_internal.app_settings` (latest state), plus vault secrets and config.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-ENV-001 | `ai.issuer_id` | app_settings key, JSON string, seed `"issuer-test"` | 20261007180000_issuer_key_custody | | Becomes the `iss` claim of AI, billing and feed tokens; also checked by verify_aat. |
| SB-ENV-002 | `ai.platform_base_url` | app_settings key, seed `"http://127.0.0.1:8787"` | 20261007180000_issuer_key_custody | | Base URL of the AI platform. Returned as platform_base_url in get_ai_status; used by the feed puller. |
| SB-ENV-003 | `ai.abo_base_url` | app_settings key, seed `"http://127.0.0.1:8788"` | 20261007180000_issuer_key_custody | | Returned as abo_base_url in the billing token and billing status. |
| SB-ENV-004 | `ai.contract_versions` | app_settings key, JSON object | 20261007180000_issuer_key_custody | | Seed: aboClinic, aboConsole, backendRpc, platformClinic, platformFeed, vendorEntrypoint, platformDo, paymobReturn, paymobAdapter, each {current 1, minimum 0}. Only platformFeed.current is read by the feed puller; launch_state returns the whole object. |
| SB-ENV-005 | `ai.issuer.rate_limit.ceiling` | app_settings key, seed `100` | 20260801120000_ai_keystore_schema | | AI token mints allowed per window per staff member. |
| SB-ENV-006 | `ai.issuer.rate_limit.window_seconds` | app_settings key, seed `3600` | 20260801120000_ai_keystore_schema | | |
| SB-ENV-007 | `ai.aat.lifetime_minutes` | app_settings key, value updated to `10` | 20260905120000_fix_aat_lifetime_minutes_seed | | Still present in the table; the latest AI minter uses a fixed 600 seconds and does not read it. |
| SB-ENV-008 | `ai.aat.audience` | app_settings key, seed `"ai-platform"` | 20260801120000_ai_keystore_schema | | Still present; latest minter hard-codes aud `ai-platform` and does not read it. |
| SB-ENV-009 | `ai.aat.ver` | app_settings key, seed `"1"` | 20260801120000_ai_keystore_schema | | Still present; latest minters hard-code ver `2`. |
| SB-ENV-010 | `ai.availability` | app_settings key | created 20260802140000_ai_availability_flag | | DELETED in 20261007230000_coverage_feed_puller_status. |
| SB-ENV-011 | Vault secret `issuer-key-<kid>` | Vault secret (base64 Ed25519 private key), description 'Ed25519 issuer private key' | 20261007180000_issuer_key_custody | | One per issuer key; referenced by issuer_key.secret_ref. |
| SB-ENV-012 | Advisory lock keys 87201401 (AI mint) and 87201402 (billing mint) | pg_advisory_xact_lock namespaces | 20261014170600_r1_sql06 / 20261014170900_r2_c2 | | Serialize per-staff rate-limit counting. |
| SB-ENV-013 | Session settings read: `request.jwt.claims`; `app.environment` | Postgres settings | 20260801120200_ai_token_issuer_rpc; seed.sql | | seed.sql defines `public.local_dev_pre_request()` setting `app.environment = development` for local dev only, wired to the `authenticator` role as pgrst.db_pre_request. Not AI-specific. |
| SB-ENV-014 | config.toml `[studio] openai_api_key = env(OPENAI_API_KEY)` | config environment reference | config.toml | | Supabase Studio's own AI assistant; unrelated to the clinic AI platform. Listed to avoid confusion. |
| SB-ENV-015 | Hard-coded limits in SQL | Constants | issue_billing_token / issue_ai_token / request_ai_status_refresh / pull_coverage_feed / get_ai_status | | Billing token life 300 s; billing rate limit 20 per 10 minutes; AI token life 600 s; feed token life 120 s; issuer key validity 13 months; status refresh throttle 10 s; feed pending timeout 5 minutes; stale threshold 2 minutes; feed page limit 200; accepted contract versions (0, 1). |
| SB-ENV-016 | Permission keys relevant to AI | Rows in roles_permissions / default template | 20260516100400_auth_rbac_seed; 20260903180000_grant_ai_visit_summary_administrator | | `ai.access` for administrator, doctor (owner row existed before the owner role was removed); `ai.visit_summary` for administrator. Seeded for each organization from the default template. The scopes in the AI token are whichever `ai.%` keys are granted for the caller's membership role. Also relevant: `visits.edit_soap` (needed by the acceptance target). |

---

## 10. Error codes raised or returned (SB-ERR)

Two forms: returned in `rpc_result.error_code`, or raised as a Postgres exception (message text = code).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-ERR-001 | CONTRACT_VERSION_UNSUPPORTED | returned (rpc_result with data accepted_versions [0,1], contract_version 1, message 'Contract version is not supported.') by get_ai_status, get_ai_billing_status, request_ai_status_refresh, issue_billing_token; raised exception with DETAIL `{"accepted_versions":[0,1]}` by issue_ai_token | 20261007180000_issuer_key_custody, 20261007230000, 20261008010000 | | NULL version is also unsupported. |
| SB-ERR-002 | FORBIDDEN_ROLE | returned | issue_billing_token, request_ai_status_refresh, get_ai_billing_status | | Caller's membership role is not administrator. Messages: 'Only administrators can issue billing tokens.', 'Only administrators can request status refresh.', 'Only administrators can view billing status.' |
| SB-ERR-003 | FORBIDDEN | returned by rpc_error in billing/status/acceptance/active-org functions ('Organization context is required.'; 'You do not have a membership in that organisation.'); raised as exception by issue_ai_token | issue_billing_token, get_ai_status, request_ai_status_refresh, record_ai_acceptance, set_active_organization, issue_ai_token | | Also used inside assert_* helpers. |
| SB-ERR-004 | STAFF_NOT_FOUND | returned by issue_billing_token ('Staff member was not found.'); raised by issue_ai_token | | | No live active staff row for the caller. |
| SB-ERR-005 | BRANCH_NOT_FOUND | returned by issue_billing_token ('No active branch is assigned for this organization.'); raised by issue_ai_token | | | |
| SB-ERR-006 | ISSUER_KEY_NOT_CONFIGURED | returned by issue_billing_token ('Issuer signing key is not configured.'); raised by issue_ai_token and issue_feed_token | | | No `signing` key row, or its vault secret missing. |
| SB-ERR-007 | RATE_LIMITED | returned by issue_billing_token ('Billing token rate limit exceeded.') and request_ai_status_refresh ('Refresh was requested recently.'); raised by issue_ai_token | | | |
| SB-ERR-008 | AI_ACCESS_DENIED | raised by issue_ai_token | | | Role has no granted `ai.%` permission in the org. |
| SB-ERR-009 | UNAUTHENTICATED | raised by assert_valid_ai_session; converted to rpc_error (code = message = UNAUTHENTICATED) in billing token and refresh | | | |
| SB-ERR-010 | SESSION_EXPIRED | raised by assert_valid_ai_session when the `exp` claim is past; converted like UNAUTHENTICATED | | | |
| SB-ERR-011 | INVALID_INPUT | returned by record_ai_acceptance (bad reference format 'Request reference must use the standard format.'; unregistered target 'Acceptance target is not registered.'; duplicate 'This AI output was already accepted for this record.') | 20260805150000_f2_review_resolution | | Also by dropped set_ai_availability / revoke_installation_key. |
| SB-ERR-012 | INTERNAL_ERROR | returned by invoke_acceptance_domain_rpc ('Domain function is not configured.') | | | |
| SB-ERR-013 | NOT_FOUND, FORBIDDEN | returned by get_visit_chief_complaint ('Visit was not found.', 'You do not have permission to view this visit clinical data.') | 20260805120000 | | |
| SB-ERR-014 | Exception 'Domain write did not return a record id.' | raised in record_ai_acceptance (rolls the whole transaction back) | | | |
| SB-ERR-015 | Exceptions from canonical_issuer_jwt_json | 'issuer JWT JSON keys must be ASCII'; 'issuer JWT numbers must be safe integers'; 'unsupported issuer JWT JSON value: <kind>' | 20261014170000 | | |
| SB-ERR-016 | MEMBERSHIP_ROLE_REPAIR_HELD_ROWS | raised by the one-time repair DO block when unresolved rows remain | 20261014170500 | | Migration-time only. |
| SB-ERR-017 | Staff update codes in update_staff_member | INVALID_INPUT, STAFF_NOT_FOUND, CROSS_ORG_DENIED, MEMBERSHIP_NOT_FOUND, LAST_ADMINISTRATOR, INVALID_BRANCH, FORBIDDEN | 20261014170400 | | Listed because this function keeps membership role (token authority) in step. |
| SB-ERR-018 | ALREADY_ENROLLED, INSTALLATION_NOT_ENROLLED, KEY_NOT_FOUND, CANNOT_REVOKE_LAST_ACTIVE_KEY, SINGLE_INSTALLATION_VIOLATION | historic codes of the dropped installation keystore | see Dropped category | | Not reachable in the latest state. |

---

## 11. Dropped items that existed earlier (SB-DROP)

Present in older migrations, removed from the latest state. Kept so the story of the clinic keypair and the availability flag can be described accurately (what existed, then what replaced it).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-DROP-001 | `public.enroll_installation_keypair()` and `auth_internal.enroll_installation_keypair()` | RPC, dropped | created 20260801120100_ai_installation_keypair_routines; last body 20260902120000_enroll_installation_keypair_already_enrolled_guard; DROPPED 20261007180000_issuer_key_custody | | Administrator only. Generated an Ed25519 keypair in the database (private key stored in installation_keys.secret_key), created or reused the single installation id, returned kid, installation_id and a public JWK (kty OKP, crv Ed25519, x, kid). Rejected with ALREADY_ENROLLED if an active key existed. |
| SB-DROP-002 | `public.rotate_installation_key()` and internal twin | RPC, dropped | 20260801120100; DROPPED 20261007180000 | | Added a new key under the same installation id; INSTALLATION_NOT_ENROLLED if none. |
| SB-DROP-003 | `public.revoke_installation_key(p_kid text)` and internal twin | RPC, dropped | last body 20260905120600_revoke_fresh_return_stored_revoked_at; DROPPED 20261007180000 | | Set revoked_at; idempotent for already revoked; refused to revoke the last active key (CANNOT_REVOKE_LAST_ACTIVE_KEY); KEY_NOT_FOUND. |
| SB-DROP-004 | `ai_internal.installation_keys` | Table, dropped | created 20260801120000_ai_keystore_schema; DROPPED 20261007180000 | | Columns were: kid (PK), installation_id, public_key, secret_key, algorithm default 'EdDSA', valid_from, revoked_at, created_at, created_by, updated_at, updated_by, is_deleted, deleted_at, deleted_by. Plus trigger function `ai_internal.enforce_single_installation()` (also dropped). |
| SB-DROP-005 | Old `issue_ai_token(p_scopes text[])` public and internal | RPC, dropped | last body 20261002150000_tenant_scoping; DROPPED 20261007180000 | | Signed with the installation key; iss was the installation id; ver from setting ai.aat.ver; had lifetime/rate-limit settings. Replaced by the integer-versioned function. Also the column ai_token_issuance.installation_id was dropped. |
| SB-DROP-006 | `public.set_ai_availability(p_enrolled boolean, p_platform_base_url text DEFAULT NULL)` and internal twin | RPC, dropped | created 20260905120100_set_ai_availability_rpc; created-by fix 20260905120400; DROPPED 20261007230000_coverage_feed_puller_status | | Administrator-only writer for app_settings key `ai.availability` ({enrolled, platform_base_url}); required a URL when enrolled = true. |
| SB-DROP-007 | `public.get_ai_availability()` and internal twin | RPC, dropped | created 20260802140000_ai_availability_flag; DROPPED 20261007230000 | | Returned the `ai.availability` JSON for any authenticated caller. Replaced by get_ai_status. |
| SB-DROP-008 | Two-argument `public.rpc_success(jsonb)` and `public.rpc_error(text, text)` | Helpers, dropped | 20261007180000_issuer_key_custody | | Replaced by versions with an optional contract version. |

Observation for the group assigner: launch_state still reports whether a function named `set_ai_availability` exists, although that function was dropped.

---

## Counts per category

| Category | Rows (items) |
|---|---|
| SB-RPC (public RPCs and public helpers) | 15 |
| SB-INT (internal functions) | 28 |
| SB-TABLE | 19 |
| SB-COL (rows; rows 088 and 090 to 094 each group several columns) | 95 rows; 109 individual columns are enumerated for the 15 AI/billing/identity-specific tables, plus the main columns of staff_members, staff_branch_assignments, organizations, branches |
| SB-TRIG | 3 |
| SB-RLS | 19 |
| SB-FN (edge functions) | 1 row stating none exist |
| SB-TYPE | 2 |
| SB-EXT | 5 |
| SB-ROLE | 2 |
| SB-SCH | 1 |
| SB-HOOK | 2 |
| SB-CRON | 1 |
| SB-ENV | 16 |
| SB-ERR | 18 |
| SB-DROP | 8 |

Individual column count detail: app_settings 9, ai_token_issuance 13, issuer_key 6, acceptance_targets 3, ai_accepted_output 9, clinic_ai_coverage 19, feed_state 6, status_refresh 2, membership 4, user_active_organization 3, membership_role_repair_mapping 6, roles_permissions_default_template 3, roles_permissions 12 (4 main + 7 standard + organization_id), audit_log 10, subscription_cache 4; staff_members, staff_branch_assignments, organizations and branches are listed by their main columns in grouped rows.
