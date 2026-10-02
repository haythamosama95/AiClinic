# Contract: per-tenant `roles_permissions`

**Unit**: P1.2 · **Freeze**: per-tenant `roles_permissions` (FR-003)

Later units bind to this file. They may extend it. They do not rewrite it (rule S7).

## 1. Table

`public.roles_permissions`

| Column | Type | Rule |
| --- | --- | --- |
| `id` | `uuid` | Primary key, default `gen_random_uuid()` |
| `organization_id` | `uuid NOT NULL` | References `public.organizations (id)` |
| `role` | `public.staff_role NOT NULL` | |
| `permission_key` | `text NOT NULL` | |
| `is_granted` | `boolean NOT NULL` | |
| `created_at` | `timestamptz NOT NULL` | Default `now()` |
| `created_by` | `uuid` | References `auth.users (id)` |
| `updated_at` | `timestamptz` | |
| `updated_by` | `uuid` | References `auth.users (id)` |
| `is_deleted` | `boolean NOT NULL` | Soft delete. Default `false` |
| `deleted_at` | `timestamptz` | |
| `deleted_by` | `uuid` | References `auth.users (id)` |

Unique: `(organization_id, role, permission_key)`.

## 2. Policies

Row level security stays enabled.

SELECT for `authenticated`:

- `is_deleted = false`
- `organization_id = public.current_org_id()`
- `is_granted = true` or `public.current_membership_role() = 'administrator'`

No permissive insert, update, or delete policy for `authenticated`.

## 3. Writes

| RPC | Scope |
| --- | --- |
| `public.update_role_permission(public.staff_role, text, boolean)` | Upserts the caller's `public.current_org_id()` only |
| `public.update_role_permissions(jsonb)` | Same. Each element is `role`, `permission_key`, `is_granted` |

Both are invoker wrappers around `auth_internal`. A caller with `current_org_id()` null does not change any row. Another organisation's rows stay unchanged, including `ai.%` keys.

The result stays `public.rpc_result`. This contract does not add an error body.

## 4. Seed

Each organisation has its own copy of the permission matrix. New organisations receive the default `(role, permission_key, is_granted)` set frozen at this migration, not a copy of another organisation's later edits.

## 5. AI scopes

`auth_internal.issue_ai_token` reads scopes from this table:

- `organization_id = public.current_org_id()`
- `role = public.current_membership_role()`
- `permission_key LIKE 'ai.%'`
- `is_granted = true` and `is_deleted = false`
