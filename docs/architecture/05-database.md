# Database

- Purpose: Define shared schema conventions, tenancy rules, core domains, RLS strategy, and RPC patterns.
- Read this when: designing tables, migrations, RLS policies, RPC functions, or validating data model assumptions for a feature.
- Canonical for: database conventions, tenant isolation, schema domains, and PostgreSQL business-logic contracts.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/09-security-rbac.md`, and the relevant feature spec.
- Not covered here: frontend UX behavior, deployment topology, or phase planning.

---

## Database Architecture

### Multi-Tenancy Model

The database uses a **shared-schema, shared-table** multi-tenancy model with tenant isolation via `organization_id` and `branch_id` columns.

```
organizations (tenant root)
    │
    └── branches (organization_id FK)
            │
            ├── patients (branch_id FK + organization_id FK; cross-branch visibility via RLS on org)
            ├── staff_branch_assignments (branch_id FK, many-to-many)
            ├── appointments (branch_id FK)
            ├── invoices (branch_id FK)
            ├── shifts (branch_id FK)
            ├── visits (branch_id FK)
            └── ...all operational tables (branch_id FK)
```

Rules:
- `organization_id` exists on `branches` and on `patients` (denormalized for efficient RLS queries).
- Other operational tables include `branch_id` (NOT NULL, FK to `branches`) and derive organization context through the branch.
- Patients have both `branch_id` (the registering branch) and `organization_id` (denormalized). They are visible across all branches within the same organization via RLS.
- Staff members are linked to branches via `staff_branch_assignments`. Their organization is derived from their assigned branches.
- RLS policies use the authenticated user's JWT claims (`organization_id`, `branch_ids[]`, `role`) to filter all queries automatically.

### Schema Conventions

Every table follows these conventions:

| Column       | Type                                 | Purpose                           |
| ------------ | ------------------------------------ | --------------------------------- |
| `id`         | `uuid` (default `gen_random_uuid()`) | Primary key                       |
| `created_at` | `timestamptz` (default `now()`)      | Record creation timestamp         |
| `created_by` | `uuid` (FK to `auth.users`)          | User who created the record       |
| `updated_at` | `timestamptz`                        | Last modification timestamp       |
| `updated_by` | `uuid` (FK to `auth.users`)          | User who last modified the record |
| `is_deleted` | `boolean` (default `false`)          | Soft delete flag                  |
| `deleted_at` | `timestamptz`                        | Soft delete timestamp             |
| `deleted_by` | `uuid` (FK to `auth.users`)          | User who soft-deleted the record  |

Triggers:
- `set_updated_at`: automatically sets `updated_at` to `now()` on UPDATE.
- `set_audit_user`: automatically sets `created_by`/`updated_by` from the JWT `auth.uid()`.
- Applied via: `SELECT public.apply_standard_audit_triggers('public.table_name'::regclass);`

All queries (via PostgREST and RPC functions) include `WHERE is_deleted = false` by default. This is enforced in RLS policies. Domain tables additionally block direct INSERT/UPDATE/DELETE via RLS `WITH CHECK (false)`, forcing all writes through RPC functions.

### Core Schema Domains

#### Organization & Tenancy

| Table           | Key Columns                                                                                                                | Notes                                                                                                                                                                            |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `organizations` | `id`, `name`, `logo_url`, `currency_code`, `timezone`, `subscription_tier`, `subscription_valid_until`, `settings_json`    | Tenant root. One record per clinic organization. Includes branding and locale.                                                                                                   |
| `branches`      | `id`, `organization_id`, `name`, `code`, `address`, `phone`, `maps_url`, `is_active`, `working_schedule` (jsonb, NOT NULL) | Each branch under an organization. `code` is unique per org (partial index). `working_schedule` defines per-weekday open/close times; required on create/update via branch RPCs. |

#### Staff & Auth

| Table                      | Key Columns                                                                                | Notes                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| `staff_members`            | `id`, `auth_user_id`, `full_name`, `role`, `phone`, `is_active`, `is_bootstrap_admin`      | Links to `auth.users`. Role is an enum. `is_bootstrap_admin` marks the initial installer. |
| `staff_branch_assignments` | `id`, `staff_member_id`, `branch_id`, `is_primary`, UNIQUE(`staff_member_id`, `branch_id`) | Many-to-many. A staff member can work at multiple branches. `is_primary` sets UI default. |
| `roles_permissions`        | `id`, `role`, `permission_key`, `is_granted`, UNIQUE(`role`, `permission_key`)             | Defines what each role can do. Seeded at migration time for all known permission keys.    |

Staff roles enum: `owner`, `administrator`, `doctor`, `receptionist`, `lab_staff`.

Authentication uses **usernames** (not email). Usernames are stored in GoTrue's `auth.users.email` field without an `@` symbol. Validation: 3–32 chars, `[a-z0-9_-]`, no `@`.

#### Patients

| Table      | Key Columns                                                                                                                 | Notes                                                                                                                                   |
| ---------- | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `patients` | `id`, `branch_id`, `organization_id`, `full_name`, `phone` (NOT NULL), `date_of_birth`, `gender`, `marital_status`, `notes` | `branch_id` is the registering branch. `organization_id` is denormalized for RLS. Cross-branch visibility within the same organization. |

Key differences from original spec:
- `national_id` was removed (not required for this clinic context).
- `phone` is NOT NULL (required for patient registration).
- `gender` enum restricted to `male`, `female` (removed `other`, `unknown`).
- `marital_status` enum added: `single`, `married`, `divorced`, `widowed`.
- `organization_id` added directly on patients for efficient org-scoped RLS queries.

#### Appointments

| Table          | Key Columns                                                                                                                                               | Notes                                                                                                                                                                                     |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `appointments` | `id`, `branch_id`, `patient_id`, `doctor_id` (nullable), `start_time`, `end_time`, `type` (`planned`), `status`, `queue_number`, `notes`, `cancel_reason` | Status enum: `scheduled`, `confirmed`, `checked_in`, `in_progress`, `completed`, `cancelled`, `no_show`. Lifecycle: scheduled → confirmed (phone) → checked_in → in_progress → completed. |

Enums: `appointment_type` (`planned` only); `appointment_status` as above.

**V1-4 booking and validation rules** (enforced in `auth_internal` RPCs):

- All appointments are **planned** with staff-chosen times; initial status `scheduled`.
- `doctor_id` is optional; when set, the staff member must be a doctor assigned at the branch.
- Default duration from `app_settings` key `appointment.default_duration_minutes` (branch row → org-wide row → 20-minute fallback). Staff may override per booking (5–240 minutes).
- `start_time`/`end_time` must fall within the branch `working_schedule` for that calendar day (org timezone).
- **Slot conflict**: no time overlap with any non-terminal appointment (`status` not in `cancelled`, `no_show`) at the **same branch**—branch-wide slot uniqueness (not per-doctor).
- **Same-day patient rule**: at most one non-terminal appointment per patient per branch calendar day (`PATIENT_ALREADY_BOOKED_SAME_DAY`).
- **Reschedule**: only while `status = scheduled` (before phone confirmation).
- **Day-gated status transitions**: `checked_in`, `in_progress`, `completed`, and `no_show` only on or after the appointment's local calendar day (organization timezone). `scheduled`, `confirmed`, and `cancelled` are not day-gated.
- `queue_number` exists but is unused for queue ordering in V1-4 (`start_time` ascending only).

Indexes: `(branch_id, doctor_id, start_time)`, `(branch_id, status, start_time)`, `(branch_id, start_time)` (partial: `is_deleted = false`).

RLS: SELECT for assigned branches; INSERT/UPDATE/DELETE denied (mutations via RPC only).

#### Visits & Medical Records

| Table               | Key Columns                                                                                                 | Notes                                                                                     |
| ------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `visits`            | `id`, `branch_id`, `appointment_id`, `patient_id`, `doctor_id`, `visit_date`, `status`                      | One visit per completed appointment.                                                      |
| `soap_notes`        | `id`, `visit_id`, `subjective`, `objective`, `assessment`, `plan`, `specialty_form_json`                    | Full SOAP documentation. `specialty_form_json` stores specialty-specific structured data. |
| `treatment_plans`   | `id`, `visit_id`, `patient_id`, `medication_name`, `dosage`, `frequency`, `start_date`, `end_date`, `notes` | Doctor-authored treatment plans.                                                          |
| `visit_attachments` | `id`, `visit_id`, `file_path`, `file_type`, `label`, `uploaded_by`                                          | References files in Supabase Storage. Covers lab PDFs, scans, and all visit documents.    |

#### Billing

| Table                 | Key Columns                                                                                                                                                                                                                    | Notes                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `invoices`            | `id`, `branch_id`, `patient_id`, `visit_id`, `invoice_number`, `total_amount`, `discount_amount`, `discount_approved_by`, `insurance_coverage_pct`, `insurance_provider_id`, `net_amount`, `paid_amount`, `status`, `due_date` | Status enum: `draft`, `issued`, `partially_paid`, `paid`, `overdue`, `cancelled`. |
| `invoice_items`       | `id`, `invoice_id`, `description`, `quantity`, `unit_price`, `total_price`                                                                                                                                                     | Multi-line invoice support.                                                       |
| `payments`            | `id`, `invoice_id`, `amount`, `payment_date`, `payment_method`, `notes`                                                                                                                                                        | Partial payment tracking.                                                         |
| `insurance_providers` | `id`, `branch_id`, `name`, `default_coverage_pct`, `is_active`                                                                                                                                                                 | Branch-level insurance provider catalog. Cross-branch visibility via RLS.         |

#### Shifts

| Table               | Key Columns                                                        | Notes                                      |
| ------------------- | ------------------------------------------------------------------ | ------------------------------------------ |
| `shifts`            | `id`, `branch_id`, `shift_date`, `start_time`, `end_time`, `notes` | Branch-specific. Non-recurring by default. |
| `shift_assignments` | `id`, `shift_id`, `staff_member_id`                                | One or more staff per shift.               |

Overlap rule: no overlapping shifts for the same staff member at the same branch (enforced in `create_shift` RPC function).

#### Workflow Automation

| Table                 | Key Columns                                                                                                                 | Notes                                                           |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `workflow_rules`      | `id`, `branch_id` (nullable, null = all branches in org), `trigger_event`, `action_type`, `action_config_json`, `is_active` | Trigger-action rule definitions. Org derived via branch or JWT. |
| `workflow_executions` | `id`, `workflow_rule_id`, `trigger_payload_json`, `action_result_json`, `status`, `executed_at`                             | Execution log for audit.                                        |

#### System

| Table                | Key Columns                                                                                                                                        | Notes                                                                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `app_settings`       | `id`, `organization_id` (NOT NULL FK), `branch_id` (nullable FK), `key`, `value_json`                                                              | Branch-level or org-wide settings (null `branch_id` = all branches). Org explicit. V1-4 adds `appointment.default_duration_minutes`. |
| `audit_log`          | `id`, `user_id`, `organization_id` (nullable FK), `action`, `table_name`, `record_id`, `old_data_json`, `new_data_json`, `ip_address`, `timestamp` | Detailed audit trail for sensitive operations. Org stored directly (nullable pre-bootstrap).                                         |
| `subscription_cache` | `organization_id` (PK, FK with CASCADE), `tier`, `valid_until`, `last_checked_at`                                                                  | Local cache for offline subscription validation.                                                                                     |

### Row Level Security (RLS) Strategy

Every table has RLS enabled. Policies follow this pattern:

```sql
-- Example: org isolation on patients (organization_id denormalized)
CREATE POLICY patients_select ON patients
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
  );

-- Example: INSERT/UPDATE/DELETE blocked for direct PostgREST access (writes go through RPC)
CREATE POLICY patients_insert ON patients
  FOR INSERT TO authenticated
  WITH CHECK (false);
```

Domain tables block direct INSERT/UPDATE/DELETE via RLS. All writes go through RPC functions running as SECURITY DEFINER in the `auth_internal` schema.

JWT custom claims (set during login via the `get_custom_claims` PostgreSQL function called by GoTrue hook):
- `organization_id`: the user's organization UUID
- `branch_ids`: comma-separated string of branch UUIDs the user is assigned to (primary branch listed first)
- `role`: the user's role enum value
- `staff_member_id`: the user's staff_members UUID
- `setup_required`: boolean flag when bootstrap admin has no organization yet

Helper functions for RLS policy expressions:
- `public.jwt_organization_id()` → extracts org UUID from JWT
- `public.jwt_branch_ids()` → parses comma-separated branch UUIDs into a `uuid[]` array
- `public.jwt_staff_member_id()` → extracts staff member UUID
- `public.jwt_staff_role()` → extracts role as `staff_role` enum
- `public.jwt_setup_required()` → boolean for bootstrap state
- `public.current_staff_member_row()` → returns the caller's full `staff_members` row

RLS policies are the first line of authorization. They ensure that even if application code has a bug, users cannot access data outside their organization or unauthorized branches.

### PostgreSQL Functions (RPC Layer)

All domain functions live in the `auth_internal` schema (SECURITY DEFINER) with thin `public` SECURITY INVOKER wrappers exposed via PostgREST.

#### Implemented Functions (V1-1 through V1-4)

| Public Wrapper                          | Purpose                                                          | Validation                                                                                            |
| --------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `bootstrap_create_organization(...)`    | First-time org setup (bootstrap admin only)                      | Only callable by `is_bootstrap_admin`, fails if org already exists                                    |
| `bootstrap_create_branch(...)`          | First branch creation during setup                               | Auto-assigns bootstrap admin to first branch                                                          |
| `create_staff_account(...)`             | Provision a new staff login + profile + branch assignments       | Username validation, owner-creation guards, branch existence checks                                   |
| `admin_reset_staff_password(...)`       | Admin resets another staff member's password                     | Cross-org denied, target must exist in caller's org                                                   |
| `update_organization(...)`              | Update org name/logo/currency/timezone/settings                  | ISO 4217 currency validation, IANA timezone validation                                                |
| `manage_create_branch(...)`             | Create branch (post-bootstrap)                                   | Permission check (`settings.manage_branches`), `working_schedule` validation, unique code enforcement |
| `update_branch(...)`                    | Edit branch details                                              | Org scope check, `working_schedule` validation, unique code enforcement                               |
| `set_branch_active(...)`                | Activate/deactivate branch                                       | Cannot deactivate last active branch                                                                  |
| `update_staff_member(...)`              | Edit staff profile/role/branches                                 | Permission check, cross-org safety, owner-role promotion guards                                       |
| `set_staff_active(...)`                 | Activate/deactivate staff                                        | Org scope check                                                                                       |
| `update_role_permission(...)`           | Toggle permission grant for a role                               | Owner/admin only, permission key must exist in catalog                                                |
| `search_patients(...)`                  | Paginated patient search (name or phone)                         | Branch or org scope, min query length enforcement                                                     |
| `get_patient(...)`                      | Fetch full patient detail                                        | Org ownership check, archived check                                                                   |
| `check_patient_duplicates(...)`         | Pre-registration duplicate check                                 | Phone or name+DOB matching                                                                            |
| `create_patient(...)`                   | Register a new patient                                           | Phone required (8-15 digits), duplicate warning, gender/marital_status validation                     |
| `update_patient(...)`                   | Edit patient record                                              | Optimistic concurrency (`p_expected_updated_at`), duplicate warning                                   |
| `archive_patient(...)`                  | Soft-delete a patient                                            | Permission check (`patients.delete`), idempotent archive                                              |
| `dev_reset_clinic_installation()`       | DEV ONLY: wipe org/branch data for re-bootstrap                  | Bootstrap admin only, not for production                                                              |
| `get_custom_claims(event jsonb)`        | GoTrue auth hook to build JWT custom claims                      | Looks up staff org, branches, role, setup_required flag                                               |
| `get_appointment_settings(...)`         | Resolve default appointment duration for a branch                | `appointments.create` or `appointments.cancel`; branch ∈ JWT `branch_ids`                             |
| `set_appointment_default_duration(...)` | Persist `appointment.default_duration_minutes` in `app_settings` | `settings.manage_branches` or owner/admin; duration 5–240 minutes                                     |
| `create_appointment(...)`               | Planned booking → initial `scheduled`                            | Permission, branch hours, slot + same-day patient conflicts, optional doctor                          |
| `reschedule_appointment(...)`           | Update `start_time`/`end_time` for `scheduled` appointments      | Same validation as create; excludes self from conflict set                                            |
| `cancel_appointment(...)`               | Cancel with optional reason                                      | `appointments.cancel`; from `scheduled`, `confirmed`, or `checked_in`                                 |
| `update_appointment_status(...)`        | Validated lifecycle transitions                                  | Permission by transition; day-gating for in-day statuses                                              |
| `list_appointments(...)`                | Calendar, today's queue, doctor schedule                         | Branch-scoped; date range and optional doctor/status filters                                          |

#### Planned Functions (V1-5+)

| Function              | Purpose                              | Validation                                                         |
| --------------------- | ------------------------------------ | ------------------------------------------------------------------ |
| `create_invoice(...)` | Generate invoice for a visit         | Validates line items, calculates totals                            |
| `apply_payment(...)`  | Record partial/full payment          | Validates amount against remaining balance, updates invoice status |
| `apply_discount(...)` | Apply discount with permission check | Validates caller has discount permission for the amount threshold  |
| `create_shift(...)`   | Create shift with staff assignments  | Validates no overlapping shifts for assigned staff                 |
| `create_visit(...)`   | Create visit record from appointment | Validates appointment exists and is in correct status              |

#### Standard Return Type

All functions return a standardized response shape:

```sql
CREATE TYPE rpc_result AS (
  success boolean,
  data jsonb,
  error_code text,
  error_message text
);
```

Helper constructors: `rpc_success(data)` and `rpc_error(code, message)`.

#### Permission Assertion Helpers (auth_internal)

| Function                           | Purpose                                                     |
| ---------------------------------- | ----------------------------------------------------------- |
| `assert_bootstrap_admin()`         | Raises `NOT_BOOTSTRAP_ADMIN` if caller is not the installer |
| `assert_owner_or_administrator()`  | Raises `FORBIDDEN` if caller is not owner/admin/bootstrap   |
| `assert_permission(key)`           | Raises `FORBIDDEN` if caller's role lacks the permission    |
| `assert_org_patient(id, archived)` | Raises if patient not in caller's org or is archived        |

---
