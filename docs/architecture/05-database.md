# Database

- Purpose: Define shared schema conventions, tenancy rules, core domains, RLS strategy, and RPC patterns.
- Read this when: designing tables, migrations, RLS policies, RPC functions, or validating data model assumptions for a feature.
- Canonical for: database conventions, tenant isolation, schema domains, and PostgreSQL business-logic contracts.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/09-security-rbac.md`, and the relevant feature spec.
- Not covered here: frontend UX behavior, deployment topology, or phase planning.

---

## Database Architecture

### Multi-Tenancy Model

The database uses a **shared-schema, shared-table** multi-tenancy model with tenant isolation via `branch_id` columns. The `organization_id` foreign key exists **only** on the `branches` table. All other tables reference `branch_id` and derive their organization context through the branch's `organization_id`.

```
organizations (tenant root)
    │
    └── branches (organization_id FK) ── the ONLY table with organization_id
            │
            ├── patients (branch_id FK, registering branch; cross-branch visibility via RLS)
            ├── staff_branch_assignments (branch_id FK, many-to-many)
            ├── appointments (branch_id FK)
            ├── invoices (branch_id FK)
            ├── shifts (branch_id FK)
            ├── visits (branch_id FK)
            └── ...all operational tables (branch_id FK)
```

Rules:
- `organization_id` exists only on `branches`. No other table directly references `organization_id`.
- Every operational table includes `branch_id` (NOT NULL, FK to `branches`).
- Organization context is always derived: `table.branch_id` → `branches.organization_id`.
- Patients have a `branch_id` (the branch where they were first registered) but are visible across all branches within the same organization via RLS.
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

All queries (via PostgREST and RPC functions) include `WHERE is_deleted = false` by default. This is enforced in RLS policies.

### Core Schema Domains

#### Organization & Tenancy

| Table           | Key Columns                                                                    | Notes                                            |
| --------------- | ------------------------------------------------------------------------------ | ------------------------------------------------ |
| `organizations` | `id`, `name`, `subscription_tier`, `subscription_valid_until`, `settings_json` | Tenant root. One record per clinic organization. |
| `branches`      | `id`, `organization_id`, `name`, `address`, `phone`, `is_active`               | Each branch under an organization.               |

#### Staff & Auth

| Table                      | Key Columns                                                     | Notes                                                                       |
| -------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `staff_members`            | `id`, `auth_user_id`, `full_name`, `role`, `phone`, `is_active` | Links to `auth.users`. Role is an enum. Org derived via branch assignments. |
| `staff_branch_assignments` | `id`, `staff_member_id`, `branch_id`, `is_primary`              | Many-to-many. A staff member can work at multiple branches.                 |
| `roles_permissions`        | `id`, `role`, `permission_key`, `is_granted`                    | Defines what each role can do. Org context derived from user's JWT.         |

Staff roles enum: `owner`, `administrator`, `doctor`, `receptionist`, `lab_staff`.

#### Patients

| Table      | Key Columns                                                                                | Notes                                                                                                |
| ---------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `patients` | `id`, `branch_id`, `full_name`, `phone`, `date_of_birth`, `gender`, `national_id`, `notes` | `branch_id` is the registering branch. Cross-branch visibility within the same organization via RLS. |

#### Appointments

| Table          | Key Columns                                                                                                                         | Notes                                                                                       |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `appointments` | `id`, `branch_id`, `patient_id`, `doctor_id`, `start_time`, `end_time`, `type` (planned/walk_in), `status`, `queue_number`, `notes` | Status enum: `scheduled`, `checked_in`, `in_progress`, `completed`, `cancelled`, `no_show`. |

Conflict rule: no overlapping appointments for the same doctor at the same branch (enforced in `create_appointment` RPC function).

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

| Table                | Key Columns                                                                                                       | Notes                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `app_settings`       | `id`, `branch_id` (nullable), `key`, `value_json`                                                                 | Branch-level or org-wide settings (null `branch_id` = all branches). Org derived from JWT. |
| `audit_log`          | `id`, `user_id`, `action`, `table_name`, `record_id`, `old_data_json`, `new_data_json`, `ip_address`, `timestamp` | Detailed audit trail for sensitive operations. Org derived from user's JWT.                |
| `subscription_cache` | `organization_id`, `tier`, `valid_until`, `last_checked_at`                                                       | Local cache for offline subscription validation.                                           |

### Row Level Security (RLS) Strategy

Every table has RLS enabled. Policies follow this pattern:

```sql
-- Example: org isolation derived through branch (patients registered at any branch in the org)
CREATE POLICY "org_isolation" ON patients
  FOR ALL
  USING (
    branch_id IN (
      SELECT id FROM branches
      WHERE organization_id = (auth.jwt() ->> 'organization_id')::uuid
    )
  );

-- Example: branch-scoped data filtered by user's assigned branches
CREATE POLICY "branch_isolation" ON appointments
  FOR ALL
  USING (
    branch_id = ANY(
      string_to_array(auth.jwt() ->> 'branch_ids', ',')::uuid[]
    )
  );
```

JWT custom claims (set during login via a PostgreSQL function called by GoTrue hook):
- `organization_id`: the user's organization
- `branch_ids`: array of branch IDs the user is assigned to
- `role`: the user's role enum value

RLS policies are the first line of authorization. They ensure that even if application code has a bug, users cannot access data outside their organization or unauthorized branches.

### PostgreSQL Functions (RPC Layer)

Key business logic functions:

| Function                  | Purpose                                   | Validation                                                         |
| ------------------------- | ----------------------------------------- | ------------------------------------------------------------------ |
| `create_appointment(...)` | Book an appointment                       | Checks doctor schedule, time conflicts, branch validity            |
| `cancel_appointment(...)` | Cancel with reason tracking               | Checks status transition validity                                  |
| `create_invoice(...)`     | Generate invoice for a visit              | Validates line items, calculates totals                            |
| `apply_payment(...)`      | Record partial/full payment               | Validates amount against remaining balance, updates invoice status |
| `apply_discount(...)`     | Apply discount with permission check      | Validates caller has discount permission for the amount threshold  |
| `create_shift(...)`       | Create shift with staff assignments       | Validates no overlapping shifts for assigned staff                 |
| `create_visit(...)`       | Create visit record from appointment      | Validates appointment exists and is in correct status              |
| `get_custom_claims(uid)`  | Called by GoTrue hook to build JWT claims | Looks up staff org, branches, role                                 |

All functions return a standardized response shape:

```sql
-- Return type convention
CREATE TYPE rpc_result AS (
  success boolean,
  data jsonb,
  error_code text,
  error_message text
);
```

---
