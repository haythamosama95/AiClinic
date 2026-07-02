# Database

- Purpose: Define shared schema conventions, tenancy rules, core domains, RLS strategy, and RPC patterns.
- Read this when: designing tables, migrations, RLS policies, RPC functions, or validating data model assumptions for a feature.
- Canonical for: database conventions, tenant isolation, schema domains, and PostgreSQL business-logic contracts.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/09-security-rbac.md`, `docs/architecture/14-visits-encounter-workspace.md`, and the relevant feature spec.
- Not covered here: frontend UX behavior, deployment topology, or phase planning.

---

> **Source of truth:** This document was regenerated from a live introspection of the local Supabase database (149+ applied migrations, `backend/supabase/migrations/`) rather than from the migration files alone. When in doubt, re-verify against `psql -h localhost -p 54322 -U postgres -d postgres` (local dev credentials: `postgres`/`postgres`) rather than trusting a single migration file, since later migrations frequently alter or drop objects created earlier (e.g. `soap_notes` → `visit_clinical_notes`, coded diagnosis added then removed).

## Database Architecture

### Multi-Tenancy Model

The database uses a **shared-schema, shared-table** multi-tenancy model with tenant isolation via `organization_id` and `branch_id` columns — but see the important caveat below.

```
organizations (tenant root)
    │
    └── branches (organization_id FK)
            │
            ├── patients (branch_id FK + organization_id FK; cross-branch visibility via RLS on org)
            ├── staff_branch_assignments (branch_id FK, many-to-many)
            ├── appointments (branch_id FK)
            ├── invoices / invoice_items / payments (branch_id / org FK)
            ├── shifts (branch_id FK)
            ├── visits and all visit-* tables (branch_id FK on visits; child tables scope via visit_id)
            └── ...all operational tables (branch_id FK)
```

Rules:
- `organization_id` exists on `branches`, `patients`, `invoices`, `shifts`, and the org-scoped catalogs (`medications`, `investigations`, `predefined_vital_signs`, `insurance_providers`). Other operational tables carry `branch_id` and derive organization context through the branch.
- Patients have both `branch_id` (the registering branch) and `organization_id` (denormalized). They are visible across all branches within the same organization via RLS.
- Staff members are linked to branches via `staff_branch_assignments`. Their organization is derived from their assigned branches (or, for `administrator`, from every active branch in "the" organization — see the caveat below).
- RLS policies use the authenticated user's JWT claims (`organization_id`, `branch_ids[]`, `role`) to filter all queries automatically.

> **Caveat — effectively single-organization today:** although every table is schema-ready for multiple organizations, `auth_internal.build_staff_claims(p_user_id)` (the function that builds JWT custom claims on login) resolves `organization_id` by selecting **the single oldest non-deleted row in `organizations`** (`ORDER BY o.created_at LIMIT 1`), not by looking up an organization the calling user actually belongs to. `auth_internal.organization_exists()` similarly checks "does any organization exist" rather than "does this user's organization exist". This means the schema's multi-tenancy is only safe when **exactly one organization row exists in the database** — i.e., Tier 1/2 (one clinic per self-hosted Supabase instance). A Supabase Cloud (Tier 3) deployment hosting multiple clinics in one project would currently leak every administrator into the *first-ever-created* organization. See `docs/architecture/ARCHITECTURAL_FLAWS.md` for detail and file references.

### Schema Conventions

Every table is intended to follow these conventions, applied via `SELECT public.apply_standard_audit_triggers('public.table_name'::regclass);`:

| Column       | Type                                 | Purpose                           |
| ------------ | ------------------------------------- | --------------------------------- |
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

**Documented exceptions to the convention** (verified live, not oversights to "fix" blindly — see flaws doc for the ones that are genuinely inconsistent):
- `payments` is **append-only by design**: no `updated_at`/`updated_by`, no `is_deleted`/soft-delete. Corrections are modeled as negative-amount refund rows (`payments_refund_requires_note` check constraint requires a note on refunds), never edits. This is a deliberate immutable-ledger pattern.
- `audit_log` is append-only: no update/delete columns, and RLS denies UPDATE/DELETE/INSERT outright (writes only via `SECURITY DEFINER` functions).
- `shifts` and `shift_assignments` have `deleted_at`/`deleted_by` but **no `is_deleted` boolean column** — status is derived from `deleted_at IS NULL` plus assignee count via `auth_internal.derive_shift_status()`. This is an inconsistency relative to every other table (see flaws doc).
- `organization_billing_settings` and `invoice_number_sequences` are singleton/counter tables keyed by `organization_id`/`branch_id` respectively, with no soft-delete columns — appropriate for their role.

All queries (via PostgREST and RPC functions) filter `is_deleted = false` in RLS `USING` clauses where the column exists. Domain tables additionally block direct INSERT/UPDATE/DELETE via RLS (`WITH CHECK (false)` / `USING (false)`), forcing all writes through RPC functions.

### Core Schema Domains

The live database (local dev, 149 migrations applied) has 30 tables in `public`, all listed below by domain.

#### Organization & Tenancy

| Table           | Key Columns                                                                                                                | Notes                                                                                                                                                                            |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `organizations` | `id`, `name`, `logo_url`, `currency_code`, `timezone`, `subscription_tier` (default `'standard'`), `subscription_valid_until`, `settings_json` (jsonb, default `{}`) | Tenant root. See the single-organization caveat above — in practice one row exists per deployment.                                                                              |
| `branches`      | `id`, `organization_id`, `name`, `code`, `address`, `phone`, `maps_url`, `is_active`, `working_schedule` (jsonb, NOT NULL, defaults to Mon–Sat 09:00–17:00 / Sun closed) | `code` unique per org (partial index, case-insensitive, trimmed). `working_schedule` defines per-weekday open/close times; required on create/update via branch RPCs; drives appointment slot validation. |

#### Staff & Auth

| Table                      | Key Columns                                                                                | Notes                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `staff_members`            | `id`, `auth_user_id` (unique FK to `auth.users`), `full_name`, `role`, `phone`, `is_active`, `is_bootstrap_admin`, `must_change_password` | Role is the `staff_role` enum. `is_bootstrap_admin` marks the installer account. `must_change_password` supports admin-issued password resets. |
| `staff_branch_assignments` | `id`, `staff_member_id`, `branch_id`, `is_primary`, UNIQUE(`staff_member_id`, `branch_id`) | Many-to-many. A staff member can work at multiple branches. `is_primary` sets UI default and claim ordering. |
| `roles_permissions`        | `id`, `role`, `permission_key`, `is_granted`, UNIQUE(`role`, `permission_key`)             | Defines what each role can do. Seeded for all known permission keys × all roles (24 keys × 4 roles = 96 rows).    |

**Staff roles enum (`staff_role`): `administrator`, `doctor`, `receptionist`, `lab_staff`.** There is **no `owner` role** — it was removed in `backend/supabase/migrations/20260611150000_remove_owner_role.sql` after `20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql` collapsed owner-only setup logic into `administrator` + `is_bootstrap_admin`. `backend/tests/owner_role_migration.sql` is a regression test asserting the role no longer exists. Any documentation, spec, or comment mentioning `owner` predates this change.

Authentication uses **usernames** (not email). Usernames are stored in GoTrue's `auth.users.email` field without an `@` symbol. Validation: 3–32 chars, `[a-z0-9_-]`, no `@` (`auth_internal.assert_valid_username`).

#### Patients & Patient Safety Records

| Table      | Key Columns                                                                                                                 | Notes                                                                                                                                   |
| ---------- | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `patients` | `id`, `branch_id`, `organization_id`, `full_name`, `phone` (NOT NULL), `date_of_birth`, `gender`, `marital_status`, `notes` | `branch_id` is the registering branch; `organization_id` denormalized for RLS. Cross-branch visibility within the same organization. Unique on `(organization_id, phone)` where not deleted; trigram index on `lower(full_name)` for fuzzy search. |
| `patient_allergies`          | `id`, `patient_id`, `substance`, `reaction`                | Added in the visit-encounter-workspace migration (014, P3). Patient-level, not visit-level — persists across visits.        |
| `patient_medications`        | `id`, `patient_id`, `medication_id` (nullable FK), `name`, `note` | Current/home medications, distinct from `treatment_plans` (which are visit-scoped prescriptions).                            |
| `patient_chronic_conditions` | `id`, `patient_id`, `name`, `note`                          | Originally had a `diagnosis_code_id` FK to a coded-diagnosis catalog; that column and the catalog were **dropped** (see Visits domain below). Free-text only today. |

Key differences from the original product spec (`specs/004-patient-management`):
- `national_id` was removed (not required for this clinic context).
- `phone` is NOT NULL (required for patient registration) and globally unique per organization.
- `gender` enum restricted to `male`, `female` (no `other`/`unknown`).
- `marital_status` enum: `single`, `married`, `divorced`, `widowed`.

#### Appointments

| Table          | Key Columns                                                                                                                                               | Notes                                                                                                                                                                                     |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `appointments` | `id`, `branch_id`, `patient_id`, `doctor_id` (nullable), `start_time`, `end_time`, `type` (`appointment_type`, only value `planned`), `status`, `queue_number`, `notes`, `cancel_reason`, `checked_in_at`, `in_progress_at` | `end_time > start_time` check constraint. `checked_in_at`/`in_progress_at` timestamps added post-V1-4 for wait-time reporting. |

`appointment_status` enum values: `scheduled`, `checked_in`, `in_progress`, `completed`, `cancelled`, `no_show`, `confirmed`. Lifecycle: `scheduled` → `confirmed` (phone confirmation) → `checked_in` → `in_progress` → `completed`, with `cancelled`/`no_show` as terminal off-ramps.

Booking and validation rules (enforced in `auth_internal` RPCs, largely unchanged since V1-4):
- All appointments are **planned** with staff-chosen times; initial status `scheduled`.
- `doctor_id` is optional; when set, the staff member must be a doctor assigned at the branch (`assert_appointment_doctor`).
- Default duration resolves from `app_settings` key `appointment.default_duration_minutes` (branch row → org-wide row → **30-minute** fallback as of `20260628155000_appointment_default_duration_30.sql`, changed from the original 20-minute default). Staff may override per booking (5–240 minutes).
- `start_time`/`end_time` must fall within the branch `working_schedule` for that calendar day (org timezone).
- **Slot conflict**: no time overlap with any non-terminal appointment at the **same branch** (branch-wide uniqueness, not per-doctor) — `appointment_has_overlap`. A later migration (`20260627150000_restore_branch_wide_appointment_overlap.sql`) reaffirms this after an intermediate attempt to scope by doctor.
- **Same-day patient rule**: at most one non-terminal appointment per patient per branch calendar day (`PATIENT_ALREADY_BOOKED_SAME_DAY`).
- Exactly one `in_progress` appointment per doctor per branch at a time (partial unique index `idx_appointments_one_in_progress_per_doctor`); one unassigned-doctor `in_progress` slot per branch (`idx_appointments_one_in_progress_unassigned`).
- **Reschedule**: only while `status = scheduled`.
- **Day-gated status transitions**: `checked_in`, `in_progress`, `completed`, `no_show` only on/after the appointment's local calendar day. `scheduled`, `confirmed`, `cancelled` are not day-gated.
- A "simplified slot booking" RPC (`get_simplified_booking_slots`, `20260628160000_simplified_slot_booking.sql`) generates bookable time slots for a branch/date/preferred-doctor combination for the booking UI.

RLS: SELECT for assigned branches; INSERT/UPDATE/DELETE denied at the table level (mutations via RPC only).

#### Visits & Clinical Documentation

> Full business/product context, the encounter-workspace UI redesign, and the P1→P3 delivery history live in `docs/architecture/14-visits-encounter-workspace.md`. This section documents the current schema only.

| Table                   | Key Columns                                                                                                 | Notes                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `visits`                | `id`, `branch_id`, `appointment_id` (unique while active), `patient_id`, `doctor_id`, `visit_date`, `status` | One active visit per appointment (`visits_appointment_id_active_unique`). `visit_status` enum: `in_progress`, `completed` only (no `cancelled`/`no_show` — a visit is simply not created if the appointment doesn't reach that stage). |
| `visit_clinical_notes`  | `id`, `visit_id` (unique), `complaint`, `history`, `examination`, `diagnosis`, `plan`                        | **Replaces the former `soap_notes` table** (subjective/objective/assessment/plan/`specialty_form_json`), dropped in the 013-visits redesign (`20260628140000_visit_documentation_redesign.sql`). All five fields are free text, ≤10,000 chars each, all nullable (a visit can be completed with only some sections filled — see "any field" rule below). |
| `visit_vital_signs`     | `id`, `visit_id`, `predefined_vital_sign_id` (nullable FK), `name`, `value`, `unit`, `measured_at`           | `measured_at` added in the 014 encounter-workspace migration. Free-text `value` (not numeric) to accommodate compound readings like blood pressure ("120/80"). |
| `visit_investigations`  | `id`, `visit_id`, `investigation_id` (nullable FK to catalog), `name`, `note`, `result`, `result_recorded_at`, `result_recorded_by` | Ordered investigations with later-recorded results (added in 014 P3). `get_visit` also surfaces cross-visit **pending investigations** (ordered on a prior visit, result still null) for the current patient. |
| `treatment_plans`       | `id`, `visit_id`, `patient_id`, `medication_id` (nullable FK), `medication_name`, `dosage`, `frequency`, `duration`, `notes` | Free-text `duration` field (start/end dates were removed; `013-visits` migrated old rows best-effort). |
| `visit_attachments`     | `id`, `visit_id`, `file_path`, `file_type`, `label`, `uploaded_by`, `size_bytes`                             | References objects in the `visit-attachments` Storage bucket. `file_type` enum: `pdf`, `docx`, `jpeg`, `png`. |
| `predefined_vital_signs`| `id`, `organization_id`, `name`, `default_unit`                                                              | Org-scoped catalog, seeded per-org on organization creation (`Blood Pressure`, `Heart Rate`, `Temperature`, `Respiratory Rate`, `Oxygen Saturation`, `Weight`, `Height`, `Pain Score`). |

**Tables that existed briefly and were removed** (do not resurrect without re-reading the removal migrations for rationale):
- `soap_notes` → replaced by `visit_clinical_notes` (013-visits redesign).
- `diagnosis_codes` (org catalog) and `visit_diagnosis_codes` (visit lines) → added in the 014 plan (P3) then **dropped** in `20260702120000_remove_coded_diagnosis.sql`. Coded diagnosis was scoped out; diagnosis remains a free-text field on `visit_clinical_notes.diagnosis`. `patient_chronic_conditions.diagnosis_code_id` was dropped in the same migration.
- `visit_plan_details` (structured follow-up/instructions/referral/certificate fields, 1:1 with a visit) → added in 014 P3 then **dropped** in `20260705120000_remove_structured_plan_outputs.sql`. Structured plan output was scoped out; the free-text `visit_clinical_notes.plan` field remains the only Plan-phase text field. **`specs/014-visit-encounter-workspace/plan.md` still describes `diagnosis_codes` and `visit_plan_details` as if they will be built — that plan document is now partially superseded by these two removal migrations and should not be read as current schema.**

Visit completion rule history: an initial migration required non-empty `visit_clinical_notes` fields to complete a visit; `20260708120000_allow_empty_visit_documentation_on_complete.sql` relaxed this to allow empty documentation, and `20260709120000_require_visit_documentation_on_complete.sql` / `20260710120000_visit_documentation_any_field_on_complete.sql` re-tightened it to the current rule: **at least one of the five clinical-note fields must be non-empty** (`auth_internal.clinical_note_has_content`) to call `complete_visit`. A vestigial `soap_note_has_content` helper function of the same shape still exists in `public` from before the rename — dead code, harmless but confusing (see flaws doc).

#### Billing

| Table                            | Key Columns                                                                                                                                                                                                                    | Notes                                                                             |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `invoices`                        | `id`, `organization_id`, `branch_id`, `patient_id`, `visit_id`, `invoice_number`, `status`, `subtotal`, `discount_kind`, `discount_value`, `discount_amount`, `insurance_provider_id`, `insurance_covered_amount`, `currency` (default `USD`), `issued_at`, `void_reason`, `voided_at`, `voided_by` | **`invoice_status` enum: `draft`, `issued`, `partially_paid`, `paid`, `voided`.** There is no `overdue` or `cancelled` status — void is the only terminal non-paid state. At most one non-voided invoice per visit (`invoices_visit_active_unique`). Invoice numbers unique per branch. |
| `invoice_items`                   | `id`, `invoice_id`, `description`, `quantity`, `unit_price`, `line_subtotal`, `line_discount_kind`, `line_discount_value`, `line_discount_amount`, `line_total`                                                              | Formula-enforced via CHECK constraints (`line_subtotal = quantity * unit_price`, etc.), not just application logic. |
| `payments`                        | `id`, `invoice_id`, `branch_id`, `method`, `amount`, `reference`, `note`, `recorded_by`, `recorded_at`                                                                                                                        | Append-only ledger (see Schema Conventions). Negative `amount` = refund, requires `note`. `payment_method` enum: `cash`, `card`, `bank_transfer`, `insurance_settlement`. |
| `insurance_providers`             | `id`, `organization_id`, `name`, `contact_info`, `is_active`                                                                                                                                                                   | Org-scoped (not branch-scoped, unlike the original spec draft). Unique name per org. |
| `organization_billing_settings`   | `organization_id` (PK), `allow_partial_payments` (default `false`)                                                                                                                                                             | Singleton per org; provisioned automatically via `trg_organizations_provision_billing_settings` trigger on `organizations` insert. |
| `invoice_number_sequences`        | `branch_id` (PK), `last_value`                                                                                                                                                                                                 | Backing counter for `assign_invoice_number`; RLS fully denies client access (`invoice_number_sequences_deny`). |

`discount_kind` enum: `percentage`, `fixed`. Discounts are mutually exclusive at the line level vs. invoice level per draft invoice (`trg_invoices_discount_scope_exclusive` / `trg_invoice_items_discount_scope_exclusive`, enforced by `assert_discount_scope_exclusive`).

#### Shifts

| Table               | Key Columns                                                        | Notes                                      |
| ------------------- | ------------------------------------------------------------------ | ------------------------------------------- |
| `shifts`            | `id`, `organization_id`, `branch_id`, `shift_date`, `start_time`, `end_time`, `notes` | `end_time > start_time` check. **No `is_deleted` column** — see Schema Conventions exceptions. |
| `shift_assignments` | `id`, `shift_id`, `staff_member_id`, UNIQUE(`shift_id`, `staff_member_id`) | One row per assigned staff member per shift. |

Overlap rule: no overlapping shifts for the same staff member at the same branch (`assert_no_staff_shift_overlap`, enforced in `create_shift`/`update_shift`/`modify_shift_assignments`). Shift "status" (e.g. cancelled/active) is derived at read time by `auth_internal.derive_shift_status(deleted_at, assignee_count)` rather than stored.

#### Catalogs (Org-Scoped, Shared Across Visits/Billing)

| Table           | Key Columns                                    | Notes                                                                 |
| --------------- | ------------------------------------------------ | ---------------------------------------------------------------------- |
| `medications`   | `id`, `organization_id`, `name`                  | Seeded with 10 common drug names per org on creation; doctors can add custom entries via a "save to catalog" prompt during documentation. |
| `investigations`| `id`, `organization_id`, `name`                  | Same pattern as medications; seeded with 10 common investigation names. |

Both support fuzzy search via the `pg_trgm` extension (`search_medications`, `search_investigations`).

#### System

| Table                | Key Columns                                                                                                                                        | Notes                                                                                                                                |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `app_settings`       | `id`, `organization_id` (NOT NULL FK), `branch_id` (nullable FK), `key`, `value_json`                                                              | Branch-level or org-wide settings (null `branch_id` = all branches). Currently used for `appointment.default_duration_minutes`.      |
| `audit_log`          | `id`, `user_id`, `organization_id` (nullable FK), `action`, `table_name`, `record_id`, `old_data_json`, `new_data_json`, `ip_address`, `created_at` | Append-only audit trail. RLS: readable by the acting user or anyone in the same organization; no client writes (RPC functions insert directly as `SECURITY DEFINER`). |
| `subscription_cache` | `organization_id` (PK, FK cascade), `tier`, `valid_until`, `last_checked_at`                                                                       | Local cache for offline subscription validation. **No code currently writes to this table** — the validation flow described in `10-resilience-and-scale.md` is not yet implemented; the table exists ahead of the feature. |

### Workflow Automation Tables — Not Implemented

`workflow_rules` and `workflow_executions` (described in `docs/architecture/08-automation.md`) **do not exist** in the current schema. No migration creates them. Automation remains a documented future design only.

### Row Level Security (RLS) Strategy

Every table has RLS enabled. The dominant pattern:

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

Branch-scoped tables (appointments, visits and their children, shifts) instead check `branch_id = ANY(jwt_branch_ids())`, or — for child tables like `visit_vital_signs`, `patient_allergies`, `treatment_plans` — an `EXISTS` subquery joining back to the parent (`visits`/`patients`) plus `auth_internal.staff_can_access_branch(...)`.

Domain tables block direct INSERT/UPDATE/DELETE via RLS. All writes go through RPC functions running as `SECURITY DEFINER` in the `auth_internal` schema. A few narrow exceptions allow direct `UPDATE`/`SELECT` where the table is a pure read-model with no write path at all (e.g. `roles_permissions_select` conditionally reveals denied rows only to administrators).

JWT custom claims (set during login via the `get_custom_claims` PostgreSQL function, invoked by GoTrue's custom-access-token hook — configured as `GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_URI: pg-functions://postgres/public/get_custom_claims` in `backend/local/docker-compose.yml`):
- `organization_id`: the user's organization UUID (see the single-organization caveat above)
- `branch_ids`: comma-separated string of branch UUIDs the user is assigned to (primary branch listed first; for `administrator`, **all active branches in the organization**, not just assigned ones)
- `role`: the user's role enum value (claim name `staff_role`)
- `staff_member_id`: the user's `staff_members` UUID
- `setup_required`: boolean flag when the bootstrap admin has no organization yet

Helper functions for RLS policy expressions (all in `public`, several delegating to `auth_internal`):
- `public.jwt_organization_id()` → extracts org UUID from JWT
- `public.jwt_branch_ids()` → parses comma-separated branch UUIDs into a `uuid[]` array
- `public.jwt_staff_member_id()` → extracts staff member UUID
- `public.jwt_staff_role()` → extracts role as `staff_role` enum
- `public.jwt_setup_required()` → boolean for bootstrap state
- `public.current_staff_member_row()` → returns the caller's full `staff_members` row
- `auth_internal.staff_can_access_branch(branch_id)` → true if the branch is in the caller's `branch_ids` (or caller is administrator)
- `auth_internal.staff_has_visit_clinical_access()`, `staff_has_visit_upload_access()`, `staff_has_payments_read_access()`, `staff_has_invoices_view_access()`, `staff_has_shifts_manage()` → permission-derived booleans reused across several RLS policies and RPCs to avoid duplicating `assert_permission` calls in read paths

RLS policies are the first line of authorization. They ensure that even if application code has a bug, users cannot access data outside their organization or unauthorized branches — subject to the single-organization caveat noted above.

### PostgreSQL Functions (RPC Layer)

All domain functions live in the `auth_internal` schema (`SECURITY DEFINER`) with thin `public` `SECURITY INVOKER` wrappers exposed via PostgREST (`schemas = ["public", "graphql_public"]` in `backend/supabase/config.toml`; `auth_internal` is intentionally never exposed). The live database currently has **182 functions in `auth_internal`** and **152 in `public`** (the gap is `auth_internal`-only internal helpers such as `assert_*` guards, plus `pg_trgm` extension functions installed into `public` — see flaws doc).

#### Function Catalog by Domain (representative, not exhaustive — see live introspection for the full list)

| Domain | Key Public RPCs |
| --- | --- |
| Bootstrap / Org / Branch | `bootstrap_finish_setup`, `bootstrap_create_organization`, `bootstrap_create_branch` (legacy path), `update_organization`, `manage_create_branch`, `update_branch`, `set_branch_active`, `delete_branch` |
| Staff & RBAC | `create_staff_account`, `update_staff_member`, `set_staff_active`, `delete_staff_member`, `admin_reset_staff_password`, `admin_update_staff_username`, `update_role_permission`, `update_role_permissions` |
| Patients | `search_patients`, `get_patient`, `check_patient_duplicates`, `find_patient_duplicate_candidates`, `create_patient`, `update_patient`, `archive_patient`, `restore_patient`, `transfer_patient` |
| Patient safety records (014 P3) | `create_patient_allergy` / `update_patient_allergy` / `archive_patient_allergy`, `create_patient_medication` / `update_patient_medication` / `archive_patient_medication`, `create_patient_chronic_condition` / `update_patient_chronic_condition` / `archive_patient_chronic_condition`, `get_patient_safety_context` |
| Appointments | `create_appointment`, `reschedule_appointment`, `cancel_appointment`, `update_appointment_status`, `list_appointments`, `get_appointment`, `get_appointment_settings`, `set_appointment_default_duration`, `get_simplified_booking_slots` |
| Visits & Documentation | `create_visit`, `get_visit`, `get_visit_by_appointment`, `save_visit_documentation`, `complete_visit`, `create_visit_vital_sign`/`update_visit_vital_sign`/`archive_visit_vital_sign`, `create_visit_investigation`/`update_visit_investigation`/`archive_visit_investigation`/`record_investigation_result`, `create_treatment_plan`/`update_treatment_plan`/`archive_treatment_plan`, `register_visit_attachment`/`get_visit_attachment_download`/`delete_visit_attachment`, `list_patient_visits`, `list_patient_visit_attachments` |
| Catalogs | `search_medications`/`create_catalog_medication`, `search_investigations`/`create_catalog_investigation`, `list_predefined_vital_signs`/`create_predefined_vital_sign` |
| Billing | `create_invoice_from_visit`, `add_invoice_item`/`update_invoice_item`/`remove_invoice_item`, `apply_invoice_discount`/`apply_line_discount`, `set_insurance_coverage`, `issue_invoice`/`discard_draft_invoice`/`void_invoice`, `record_payment`/`record_refund`, `get_invoice_detail`/`list_invoices`/`list_patient_invoices`, `get_billing_settings`/`update_billing_settings`, `insurance_provider_upsert`/`insurance_provider_deactivate`/`list_insurance_providers` |
| Shifts | `create_shift`, `update_shift`, `cancel_shift`, `modify_shift_assignments`, `list_shifts`, `get_shift_detail` |
| Dev / test utilities | `dev_reset_clinic_installation`, `dev_seed_medications_catalog`, `dev_seed_investigations_catalog`, `delete_clinic_test_fixtures` (all gated to non-production use; see security doc) |

#### Standard Return Type

All functions return a standardized composite type:

```sql
CREATE TYPE rpc_result AS (
  success boolean,
  data jsonb,
  error_code text,
  error_message text
);
```

Helper constructors: `public.rpc_success(data)` and `public.rpc_error(code, message)`.

#### Permission Assertion Helpers (`auth_internal`)

| Function                           | Purpose                                                     |
| ----------------------------------- | ------------------------------------------------------------ |
| `assert_bootstrap_admin()`         | Raises `FORBIDDEN` if caller is not the installer during setup |
| `assert_owner_or_administrator()`  | Legacy name retained for compatibility; in practice checks `administrator` only (no `owner` role remains) |
| `assert_permission(key)`           | Raises `FORBIDDEN` if caller's role lacks the permission; returns the caller's `staff_members` row on success (many RPCs reuse the returned row instead of a second lookup) |
| `assert_org_patient(id, archived)` | Raises if patient not in caller's org or is archived         |
| `assert_visit_branch_scope`, `assert_patient_branch_scope`, `assert_shift_branch_scope`, `assert_invoice_branch_scope`, `assert_appointment_branch` | Per-domain "does this record belong to a branch I can access" guards, called at the top of nearly every mutating RPC |

### Extensions

`pg_trgm` (trigram similarity) is installed for fuzzy patient/medication/investigation search. It is installed into the **`public` schema**, not a dedicated `extensions` schema — this pollutes `public`'s function/operator namespace with generic names like `similarity`, `show_trgm`, `set_limit` and is flagged as a Supabase-linter-relevant item in `docs/architecture/ARCHITECTURAL_FLAWS.md`.

---
