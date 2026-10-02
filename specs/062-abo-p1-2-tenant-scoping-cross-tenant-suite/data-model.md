# Data Model

**Unit**: P1.2 · **Spec**: `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/spec.md`

The inventory of live tables, policies, and definers is `research.md`. This file records the entities the spec names.

## 1. Tenant inventory

The record in `research.md` of every live tenant table, the policies this unit changes, and every definer RPC, each with its org key.

An object keys on `public.current_org_id()` when its row predicate compares the row's organisation to `public.current_org_id()` or to `public.jwt_organization_id()` (which returns `current_org_id()`).

## 2. `roles_permissions`

Per-tenant permission matrix. AI token scopes are the granted `ai.%` keys for the caller's organisation and `public.current_membership_role()`.

| Column | Change |
| --- | --- |
| Existing columns (`id`, `role`, `permission_key`, `is_granted`, audit, soft-delete) | Kept |
| `organization_id uuid NOT NULL` | References `public.organizations (id)` |
| Unique `(role, permission_key)` | Replaced by unique `(organization_id, role, permission_key)` |

SELECT for `authenticated` requires `organization_id = public.current_org_id()`, and the row is granted or `public.current_membership_role() = 'administrator'`. Direct writes by `authenticated` stay closed. `auth_internal.update_role_permission` and `auth_internal.update_role_permissions` upsert only the caller's organisation.

Every existing organisation receives a copy of the pre-change matrix. A new organisation receives that same default set, not another organisation's later edits. The wire shape is `contracts/roles-permissions.md`.

## 3. `ai_internal.ai_token_issuance`

AI token issuance state.

| Column | Change |
| --- | --- |
| Existing columns | Kept |
| `organization_id uuid NOT NULL` | References `public.organizations (id)` |

Backfill uses the actor staff member's earliest `ai_internal.membership` by `(created_at, organization_id)`. `auth_internal.issue_ai_token` inserts `organization_id = public.current_org_id()` and sets the token `org` claim from `current_org_id()`.

SELECT for `authenticated` is `organization_id = public.current_org_id()`. Insert, update, and delete by `authenticated` stay denied.

## 4. AI acceptance records

`public.ai_accepted_output` already has `organization_id` and a SELECT policy `organization_id = public.jwt_organization_id()`. `auth_internal.record_ai_acceptance` already writes that value. This unit does not change the table or the function.

`ai_internal.acceptance_targets` is the global target registry. It is not an acceptance record and not a tenant table.

## 5. `staff_members` and `staff_branch_assignments`

Staff rows have no `organization_id`. Visibility is membership:

- `staff_members` SELECT and UPDATE: a row in `ai_internal.membership` for `(staff_members.auth_user_id, public.current_org_id())`.
- `staff_branch_assignments` SELECT: `branches.organization_id = public.current_org_id()` and a membership for the assigned staff member's `auth_user_id` in that organisation. The existing setup-required own-row arm remains only when `current_org_id()` is null.

## 6. Other tenant tables without `organization_id`

`research.md` §2.2 lists each table and the parent used to backfill `organization_id`. Each gains the column, a restrictive policy `organization_id = public.current_org_id()`, and the shared `BEFORE INSERT` fill. `public.invoices` already has the column; it gains the restrictive policy only.

`ai_internal.installation_keys` and `ai_internal.app_settings` are out of scope (P5.1 and P5.2).
