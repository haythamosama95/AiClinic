# Research: Patient MRN (Medical Record Number)

Resolves the technology choices and integration patterns for feature `016-patient-mrn-field`. The spec's Clarifications session already locked the product decisions (global uniqueness, `MRN-000001` format, server-side sequence + unique-constraint backstop, immutability on record, admin-only restricted reassignment flow). This document records the technical decisions that flow from those product decisions and from the existing codebase.

## Decision 1: Use a native PostgreSQL `SEQUENCE` for MRN generation (not a counter table)

- **Decision**: `CREATE SEQUENCE public.patient_mrn_seq;` consumed inside `auth_internal.assign_patient_mrn()` via `format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'))`. Pair with a global `CREATE UNIQUE INDEX patients_mrn_unique ON public.patients (mrn);` as the backstop.
- **Rationale**: FR-010 explicitly mandates "a server-side sequence for generation plus a globally-unique database constraint as a backstop, avoiding retry-based collision loops." A native `SEQUENCE` is the canonical PostgreSQL mechanism for gap-free-per-attempt monotonic generation, is fully atomic (no row lock contention), and requires no retry loop on the common path. The repo already has a precedent (`invoice_number_sequences` counter table + `assign_invoice_number`) — but that precedent is **per-branch**, where a single-row counter table cleanly mirrors per-branch partitioning. For **global** uniqueness the cleaner primitive is the native sequence; a single-row global counter table would be functionally equivalent but adds a custom table where the engine already provides one.
- **Alternatives considered**:
  - **Single-row counter table** (`mrn_sequences(id int PK CHECK(id=1), last_value bigint)`) with `INSERT ... ON CONFLICT DO NOTHING` + `UPDATE ... RETURNING last_value + 1` (mirrors `invoice_number_sequences`). Rejected as primary: equivalent semantics but duplicates database-native functionality; kept as a noted fallback if sequences ever prove operationally awkward for resets.
  - **`max(mrn) + 1` selection on insert**. Rejected: racy under concurrency, requires table-level locking, exactly the retry-loop pattern FR-010 forbids.
  - **UUID-derived MRN**. Rejected: spec mandates a sequential, human-readable, zero-padded, prefixed numeric string.

## Decision 2: Unique index is global and NOT partial on `is_deleted = false`

- **Decision**: `CREATE UNIQUE INDEX patients_mrn_unique ON public.patients (mrn);` spanning all rows including soft-deleted ones.
- **Rationale**: The spec edge case states "soft-deleted MRNs remain excluded from active uniqueness checks but preserved for audit" — but operationally, releasing an MRN for reuse on a soft-deleted row would create exactly the ambiguity the edge case warns against (a reissued MRN pointing ambiguously at the historical or the new patient). The simplest, safest reading: an MRN, once issued, is **never reused**, period. A plain `UNIQUE` (not partial) over all rows enforces this without exception and gives the audit/reconciliation story a single, clear invariant.
- **Alternatives considered**:
  - **Partial index `WHERE is_deleted = false`** to allow active-row duplicates against archived rows. Rejected: reintroduces reuse ambiguity and complicates the reassignment uniqueness check (would have to exclude both archived and the target row).
  - **Separate `archived_mrns` holding table** moved on soft delete. Rejected: extra moving parts, breaks the "audit trail is `audit_log`" convention, and adds a migration on every archive.

## Decision 3: MRN column is `text NOT NULL`, backfilled before enforcing NOT NULL

- **Decision**: `ALTER TABLE public.patients ADD COLUMN mrn text;` → backfill existing rows via `UPDATE patients SET mrn = format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0')) WHERE mrn IS NULL;` → `ALTER TABLE public.patients ALTER COLUMN mrn SET NOT NULL;` in a single migration.
- **Rationale**: Existing rows (in any dev/staging env) need an MRN before NOT NULL can be enforced; doing it in one migration keeps the schema self-consistent at every applied state. `text` (not `varchar(n)`) matches the existing `invoice_number text`, `phone text`, `national_id text` convention; the format is enforced by the generator RPC and the reassignment validator, not by a `varchar` length cap.
- **Alternatives considered**:
  - `varchar(10)` sized to `MRN-000000`. Rejected: matches no other identifier column in the schema, and a 7-digit MRN would silently break the constraint instead of formatting correctly.
  - Two separate migrations (add column, then a later NOT NULL). Rejected: leaves a window where the column is nullable and the unique constraint can be created without backfill, risking inconsistency.

## Decision 4: Reassignment is a separate restricted RPC, not an extension of `update_patient`

- **Decision**: New `auth_internal.reassign_patient_mrn(p_patient_id uuid, p_new_mrn text)` gated by a new permission `patients.reassign_mrn` (administrator only). `update_patient` is **not** modified to accept `p_mrn` — the MRN stays absent from the regular edit path, guaranteeing inline immutability at the schema-RPC boundary.
- **Rationale**: Constitution IV (Secure and Human-Gated Operations) and FR-003 require MRN immutability for ordinary staff and a restricted, audited admin-only path. Modeling reassignment as its own RPC with its own permission key makes the access surface explicit and auditable, and prevents an accidental `update_patient` call from mutating the MRN. The two-layer RPC pattern (`auth_internal` SECURITY DEFINER + `public` SQL wrapper + `GRANT EXECUTE … TO authenticated`) matches every other mutation in the codebase.
- **Alternatives considered**:
  - Add `p_mrn` to `update_patient` and gate it by a runtime role check inside the function. Rejected: blurs the immutability boundary, complicates the existing audit `patient.update` row, and risks a future caller flipping the MRN accidentally.
  - Drive reassignment directly via `UPDATE patients SET mrn = ...` from a `patients.edit`-gated UI. Rejected: bypasses the central validation/audit path and violates Constitution III/IV.

## Decision 5: Reassignment input value handling — accept free-form prefixed values, validate format + uniqueness

- **Decision**: `reassign_patient_mrn` accepts `p_new_mrn text`, normalizes (trim + upper), validates against `^MRN-\d{6,}$` (matching the generator's format), then runs the uniqueness check excluding the target row. Reject with `MRN_EXISTS` on collision; reject with `INVALID_INPUT` on malformed value. Does **not** call `nextval` (the admin is supplying a specific target value, e.g. correcting an import duplicate), so the sequence is not advanced.
- **Rationale**: Spec Clarifications describe reassignment as a "reconciliation" flow that "may reassign with duplicate validation" — implying the administrator supplies the target value (e.g., to merge a duplicated patient onto the canonical MRN), not that the system auto-generates a replacement. Validating format keeps the dataset consistent; not calling `nextval` avoids burning sequence numbers and avoids silently shifting the auto-generated space.
- **Alternatives considered**:
  - Only accept values already produced by `assign_patient_mrn()` (i.e., generate-a-replacement flow). Rejected: defeats the use case of correcting an import duplicate where the canonical MRN already exists.
  - Allow arbitrary strings (no format check). Rejected: breaks the dataset's `MRN-NNNNNN` invariant and harms reporting/list sorting.

## Decision 6: Audit reassignment via the existing `audit_log` (no new audit subsystem)

- **Decision**: `reassign_patient_mrn` inserts one row into `public.audit_log` with `action = 'patient.mrn_reassign'`, `table_name = 'patients'`, `record_id = p_patient_id`, `old_data_json = jsonb_build_object('mrn', v_old_mrn)`, `new_data_json = jsonb_build_object('mrn', p_new_mrn)`, `user_id = auth.uid()`, `organization_id = jwt_organization_id()`. `create_patient` is also extended to include `mrn` in its existing `patient.create` audit row's `new_data_json`.
- **Rationale**: Constitution III/IV and FR-011 require an auditable record of MRN creation and reassignment. The codebase already has `audit_log` with this exact pattern (`create_patient`, `update_patient`, `archive_patient` insert rows manually). Reusing it keeps the audit story unified and respects the "no new audit subsystem" assumption in the spec.
- **Alternatives considered**:
  - A dedicated `mrn_audit_log` table. Rejected: spec assumption explicitly says "rather than introducing a brand-new audit subsystem."
  - Rely solely on `patients.updated_at`/`updated_by` triggers. Rejected: those capture only that *some* update happened, not the old/new MRN values, and do not produce an actionable audit trail for reconciliation.

## Decision 7: Permission seed — new `patients.reassign_mrn` key, administrator only

- **Decision**: Add `patients.reassign_mrn` to the seeded `roles_permissions` matrix (migration `20260724120200_patient_reassign_mrn_permission.sql`), granted to `administrator` only; revoked (or `is_granted = false`) for owner/doctor/receptionist/lab_staff and any other roles. Frontend `PermissionKeys` gains `patientsReassignMrn = 'patients.reassign_mrn'`; `PermissionService` gains `canReassignPatientMrn`.
- **Rationale**: US-2 acceptance scenario 3 requires non-administrators to be denied both the flow and any inline edit. A dedicated permission key keeps the policy declarative (in the matrix) rather than hardcoded to role names inside the RPC, matching the existing RBAC pattern (`patients.view/create/edit/delete` all live as keys).
- **Alternatives considered**:
  - Hardcode `assert_role('administrator')` inside the RPC. Rejected: bypasses the seeded permission matrix, breaks the convention used by every other domain RPC, and makes future role changes require a code migration instead of a seed update.
  - Reuse `patients.edit` and gate inline by checking `administrator` in the UI only. Rejected: violates defense-in-depth (UI check alone is insufficient) and the "admin-only flow" requirement.

## Decision 8: Surface MRN in patients list as a first column with monospace typography

- **Decision**: Add a `TableColumn(id: 'mrn', header: 'MRN', accessor: (row) => Text(row.mrn, style: AppTypography.mono))` to `PatientTable` as the **first** column (before patient name). Sort/search by MRN is optional (P3 polish) and deferred unless requested.
- **Rationale**: SC-003 wants staff to locate a patient by scanning within 5 seconds; placing MRN first and using monospace makes it visually anchor the row, matching how medical records are normally scanned. `AppDataTable`/`TableColumn` is the established column-definition pattern, and `AppTypography.mono` exists for identifier-style content.
- **Alternatives considered**:
  - Place MRN as the last column. Rejected: harms the 5-second scan goal.
  - Render in the patient-name cell (e.g., subtitle). Rejected: spec US-3 explicitly asks for a "dedicated column."

## Decision 9: Surface MRN in patient details as a prominent badge/chip via `AppBadge`

- **Decision**: Inside `PatientDetailPage._PatientIdentityCard`'s existing `Wrap` of `AppBadge`s, add an MRN badge using a distinct `BadgeColor` (e.g., `BadgeColor.primary` / teal — whichever is the established "identifier" color) and `BadgeVariant.soft`, sized `BadgeSize.md`, containing the MRN in monospace text. Place it first in the `Wrap` so it reads adjacent to the patient name.
- **Rationale**: US-4 and FR-006 require a clearly distinguishable badge/chip; `_PatientIdentityCard` already composes exactly this `Wrap` of `AppBadge(variant: BadgeVariant.soft, color: BadgeColor.neutral, …)` chips, so the MRN chip is one more child in the same pattern. A distinct color makes it pop at a glance (SC-004).
- **Alternatives considered**:
  - Render MRN as a plain `Text` label in the header. Rejected: spec US-4 explicitly asks for a badge/chip.
  - Build a new dedicated widget. Rejected: `AppBadge` already covers the requirement; net-new widget would violate "simplest architecture."

## Decision 10: Show generated MRN immediately on Add-Patient success (toast + navigation to detail)

- **Decision**: Extend `auth_internal.create_patient` to return `mrn` alongside `patient_id` in `rpc_success(jsonb_build_object('patient_id', …, 'mrn', v_mrn))`. `PatientRepository.createPatient` returns a `CreatePatientResult({ patientId, mrn })`. `patientRegistrationProvider.submit()` returns the result; `AddPatientDialog` shows an `appToast` with the generated MRN and navigates to the patient detail page where the new MRN chip is rendered, so the staff member can confirm and read it back (FR-002 / US-1 acceptance 1).
- **Rationale**: Spec US-1 requires the MRN to be displayed immediately so staff can "confirm and read it back to or record it for the patient." The detail page chip is the durable surface; the toast gives instant confirmation before navigation completes. Keeping the result as a small typed DTO (`CreatePatientResult`) rather than a bare `String`Matches the project's typed-RPC-result style.
- **Alternatives considered**:
  - Skip the toast and only show the detail-page chip post-navigation. Rejected: the navigation render race may feel laggy; the toast gives explicit confirmation the moment the save returns, satisfying "immediately upon successful patient creation."
  - Show the MRN in the dialog itself before navigating. Rejected: the dialog has just confirmed a save; a toast + detail-page chip is the established pattern in the codebase (the existing `submit()` already toasts on success).

## Decision 11: Invoice surfaces already wired — only the backend payload changes

- **Decision**: The frontend already anticipates MRN: `invoice_table.dart._PatientCell` renders `item.patientMrn ?? '—'`; `invoice_hero_card.dart` accepts and renders `mrn:`; `invoice_detail_page.dart` passes `mrn: patientMrn`; `invoice_list_item.dart` parses `patient_mrn ?? mrn`; `invoice_detail.dart` parses `patient['mrn'] ?? patient['patient_mrn']`. Therefore the only required change for US-5 is on the backend: `list_invoices`, `get_invoice_detail`, and `list_patient_invoices` must include `p.mrn AS patient_mrn` (and the patient `mrn`) in their `jsonb_build_object` payloads.
- **Rationale**: Reusing already-written frontend code avoids duplicate work and confirms the contract. Confirmed by reading `20260713130000_list_invoices_include_payments.sql` (does NOT currently return `patient_mrn`) and the frontend files cited above (which already conditionally render it).
- **Alternatives considered**:
  - Reintroduce a stored `mrn` column on `invoices`. Rejected: spec Key Entities says "Invoice carries a read-only view of the responsible patient's MRN (derived from its patient relationship, not a separately editable value)" — derived via JOIN is correct, no denormalization.

## Decision 12: Appointment and clinical surfaces (P3, US-6)

- **Decision**: Extend `AppointmentListItem` with `patientMrn`; update `list_appointments` to include `p.mrn AS patient_mrn` in its row payload; surface MRN in `appointment_calendar_tile.dart` next to the patient name. Visits/encounters and medical-records surfaces within patient detail automatically show the MRN chip once `_PatientIdentityCard` does; printed/exported reports (out of initial scope unless a report renderer already exists) will pick up the MRN when those report specs are touched.
- **Rationale**: US-6 (P3) is "polish/usability" — the spec designates it lower priority than the foundational surfaces. Implementing the appointment list + tile now (cheap, one model field + one widget edit) covers the explicit patient-reference surface the spec calls out; the deeper encounter headers inherit the chip from the patient detail work. Reports are deferred until a report path exists in the codebase (none found in the research).
- **Alternatives considered**:
  - Defer all of US-6 entirely. Rejected: the appointment list is a low-cost high-value surface explicitly named in the spec; deferring it would leave a visible patient surface without the MRN.

## Decision 13: Bulk import and patient-merge flows

- **Decision**: Out of scope for this increment's implementation, per the spec's Assumptions ("Bulk patient import is out of scope for the initial increment unless required") and the merge edge case (handled as a future conflicting-resolution surface). When a bulk import path is added later, it MUST call `assign_patient_mrn()` per row (or accept supplied MRNs with per-row uniqueness validation), never bypass the sequence. When a patient-merge flow is added, the surviving patient keeps exactly one MRN (the canonical one), and the merge flow must surface a duplicate-MRN conflict resolution consistent with `reassign_patient_mrn`.
- **Rationale**: The spec calls these out as edge cases the design must accommodate conceptually, not as required increments. Documenting the forward-looking constraint here prevents a future PR from bypassing the uniqueness guarantee.
- **Alternatives considered**: Implement bulk import now. Rejected: no bulk import surface exists in the codebase, and the spec Assumptions explicitly defer it.

## Decision 14: Dev reset must reset the sequence

- **Decision**: `backend/tests/dev_reset_clinic_installation.sql` (which clears patients in dev) must be updated to call `setval('public.patient_mrn_seq', 1, false)` after deleting patients, so a fresh dev install reproduces `MRN-000001` for the first created patient.
- **Rationale**: Without resetting the sequence, dev/test runs would produce ever-growing MRNs across resets, breaking deterministic tests (e.g., `expect(firstPatient.mrn, 'MRN-000001')` in `patient_mrn_generation.sql` and Flutter integration tests).
- **Alternatives considered**:
  - Drop and recreate the sequence on each reset. Rejected: heavier and risks dependency-order issues in the migration graph.
  - Don't reset, make tests MRN-agnostic (regex match only). Rejected: weakens the uniqueness assertion and the "first patient is MRN-000001" readability test.

## Decision 15: No AI dependency; safe degradation

- **Decision**: MRN generation, reassignment validation, and display are deterministic PostgreSQL operations; no AI service is invoked anywhere in this feature. When Supabase/PostgreSQL is unreachable, the Add-Patient form and the reassignment flow MUST surface a clear error and MUST NOT persist a patient with a locally generated/unverified MRN (FR-012).
- **Rationale**: Constitution V and FR-012. Frontend forms already rely on `AppRpcInvoker` which surfaces `RpcFailure` on connectivity loss; the existing error-mapping (`connectivity`, migration-hint errors) is reused. No new offline cache or queue is introduced.
- **Alternatives considered**:
  - Generate a provisional MRN locally, sync later. Rejected: explicitly forbidden by FR-012 — risks a clash on sync.

## Decision 16: Frontend feature placement — patients feature owns reassignment

- **Decision**: The restricted admin reassignment UI lives in `frontend/lib/features/patients/presentation/pages/mrn_reassignment_dialog.dart`, opened from the patient detail page (only when `canReassignPatientMrn` is true), not under `features/settings`.
- **Rationale**: Reassignment operates on a specific patient's record and is conceptually a per-patient action; placing it in the patients feature keeps related presentation together. `features/settings` is reserved for clinic-wide configuration. The dialog is gated by permission, so it is invisible to non-admin staff (US-2 acceptance 3).
- **Alternatives considered**:
  - Place in `features/settings` as an "admin tools" page. Rejected: detaches the action from the patient context, adds an extra navigation hop, and duplicates patient lookups.