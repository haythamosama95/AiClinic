# Data Model: Auth and RBAC

All tables use shared conventions: `id uuid PK`, audit columns (`created_at`, `created_by`, `updated_at`, `updated_by`, `is_deleted`, `deleted_at`, `deleted_by`), RLS enabled, soft-delete filtered in policies.

## Enum: `staff_role`

`owner` | `administrator` | `doctor` | `receptionist` | `lab_staff`

## Table: `organizations`

| Column                     | Type        | Notes              |
| -------------------------- | ----------- | ------------------ |
| `name`                     | text        | NOT NULL           |
| `subscription_tier`        | text        | Default `standard` |
| `subscription_valid_until` | timestamptz | Nullable           |
| `settings_json`            | jsonb       | Default `{}`       |

**Constraints**: At most one row may exist in V1-1 (enforced by RPC, not DB CHECK — allows test flexibility).

## Table: `branches`

| Column            | Type | Notes                        |
| ----------------- | ---- | ---------------------------- |
| `organization_id` | uuid | FK → organizations, NOT NULL |
| `name`            | text | NOT NULL                     |
| `address`         | text | Nullable                     |
| `phone`           | text | Nullable                     |
| `is_active`       | bool | Default true                 |

**Rules**: Only table with direct `organization_id` FK per tenancy model.

## Table: `staff_members`

| Column               | Type       | Notes                                         |
| -------------------- | ---------- | --------------------------------------------- |
| `auth_user_id`       | uuid       | FK → auth.users, UNIQUE, NOT NULL             |
| `full_name`          | text       | NOT NULL                                      |
| `role`               | staff_role | NOT NULL                                      |
| `phone`              | text       | Nullable                                      |
| `is_active`          | bool       | Default true                                  |
| `is_bootstrap_admin` | bool       | Default false; true for shipped default admin |

## Table: `staff_branch_assignments`

| Column            | Type | Notes                                                    |
| ----------------- | ---- | -------------------------------------------------------- |
| `staff_member_id` | uuid | FK → staff_members, NOT NULL                             |
| `branch_id`       | uuid | FK → branches, NOT NULL                                  |
| `is_primary`      | bool | Default false; at most one primary per staff recommended |

**Unique**: (`staff_member_id`, `branch_id`)

## Table: `roles_permissions`

| Column           | Type       | Notes    |
| ---------------- | ---------- | -------- |
| `role`           | staff_role | NOT NULL |
| `permission_key` | text       | NOT NULL |
| `is_granted`     | bool       | NOT NULL |

**Unique**: (`role`, `permission_key`)

### Seed permission keys (representative set)

Keys align with `docs/architecture/09-security-rbac.md`:

- `settings.manage_staff`, `settings.manage_branches`
- `patients.view`, `patients.create`, `patients.edit`, `patients.delete`
- `appointments.create`, `appointments.cancel`
- `visits.create`, `visits.edit_soap`
- `invoices.create`, `invoices.apply_discount`, `invoices.apply_discount_above_threshold`
- `shifts.manage`
- `analytics.view`
- `ai.access`

**Grant matrix (V1-1 seed)**:

| Permission key               | owner | administrator | doctor | receptionist | lab_staff |
| ---------------------------- | ----- | ------------- | ------ | ------------ | --------- |
| `settings.manage_staff`      | ✓     | ✓             |        |              |           |
| `settings.manage_branches`   | ✓     | ✓             |        |              |           |
| `patients.*`                 | ✓     | ✓             | ✓      | ✓            | ✓ (view)  |
| `appointments.create/cancel` | ✓     | ✓             | ✓      | ✓            |           |
| `visits.create/edit_soap`    | ✓     | ✓             | ✓      |              |           |
| `invoices.*`                 | ✓     | ✓             |        | ✓            |           |
| `shifts.manage`              | ✓     | ✓             |        |              |           |
| `analytics.view`             | ✓     | ✓             |        |              |           |
| `ai.access`                  | ✓     | ✓             | ✓      |              |           |

(Exact seed SQL in migration; matrix above guides implementation.)

## Table: `audit_log`

| Column          | Type        | Notes               |
| --------------- | ----------- | ------------------- |
| `user_id`       | uuid        | Actor auth uid      |
| `action`        | text        | e.g. `staff.create` |
| `table_name`    | text        |                     |
| `record_id`     | uuid        | Nullable            |
| `old_data_json` | jsonb       | Nullable            |
| `new_data_json` | jsonb       | Nullable            |
| `ip_address`    | text        | Nullable            |
| `timestamp`     | timestamptz | Default now()       |

## Table: `app_settings`

| Column       | Type  | Notes                                      |
| ------------ | ----- | ------------------------------------------ |
| `branch_id`  | uuid  | Nullable — null means org-wide via JWT org |
| `key`        | text  | NOT NULL                                   |
| `value_json` | jsonb | NOT NULL                                   |

## Table: `subscription_cache`

| Column            | Type        | Notes                       |
| ----------------- | ----------- | --------------------------- |
| `organization_id` | uuid        | PK/FK → organizations       |
| `tier`            | text        |                             |
| `valid_until`     | timestamptz | Expiry does not block login |
| `last_checked_at` | timestamptz |                             |

## Client entity: `AuthSessionContext` (in-memory)

| Field              | Type          | Source                     |
| ------------------ | ------------- | -------------------------- |
| `staffMemberId`    | uuid          | JWT / staff row            |
| `organizationId`   | uuid?         | JWT; null during bootstrap |
| `branchIds`        | List\<uuid\>  | JWT claim                  |
| `activeBranchId`   | uuid?         | Client selection           |
| `role`             | staff_role    | JWT                        |
| `permissions`      | Set\<string\> | roles_permissions query    |
| `setupRequired`    | bool          | JWT `setup_required`       |
| `isBootstrapAdmin` | bool          | staff row                  |

## Relationships

```text
organizations 1──* branches
branches *──* staff_members (via staff_branch_assignments)
staff_members *──1 auth.users
roles_permissions keyed by staff_role (global seed, not per-org in V1-1)
subscription_cache 1──1 organizations
```

## State transitions: bootstrap flow

1. Fresh DB → only bootstrap `staff_members` + auth user
2. Bootstrap admin signs in → `setup_required=true`
3. `bootstrap_create_organization` + `bootstrap_create_branch` → assign bootstrap admin to branch
4. Re-login or session refresh → full org/branch claims
5. Owner/admin creates additional staff via `create_staff_account`
