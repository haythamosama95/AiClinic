# Contract: MRN Surfaces (List, Detail, Invoice, Appointment)

## Purpose

Where the patient's MRN is surfaced in the Flutter client, the RPC payloads feeding those surfaces, and the UI contracts each surface follows. Generation/reassignment is covered in `mrn-generation.md`; this contract covers **presentation** only (read paths).

## Authorization (read)

All surfaces require the existing `patients.view` permission (for patient surfaces) or `invoices.view` / `appointments.read` (for invoice/appointment surfaces). No new read permission is introduced; MRN is just another attribute of the patient row already authorized by existing RLS.

---

## RPC payload extensions (additive — no signature changes)

### `search_patients` — row JSON gains `mrn`

```json
{
  "items": [
    {
      "id": "uuid",
      "full_name": "string",
      "phone": "string|null",
      "date_of_birth": "date|null",
      "mrn": "MRN-000042",
      "branch_id": "uuid",
      "branch_name": "string"
    }
  ],
  "total_count": 0,
  "limit": 25,
  "offset": 0
}
```

### `get_patient` — response gains `mrn`

```json
{
  "id": "uuid",
  "mrn": "MRN-000042",
  "full_name": "string",
  "...": "(existing fields)"
}
```

### `list_invoices` — patient sub-object gains `patient_mrn`

```json
{
  "items": [
    {
      "id": "uuid",
      "invoice_number": "string",
      "patient_id": "uuid",
      "patient_display_name": "string",
      "patient_mrn": "MRN-000042",
      "...": "(existing invoice fields)"
    }
  ],
  "..."
}
```

### `get_invoice_detail` — patient sub-object gains `mrn` (and alias `patient_mrn`)

```json
{
  "patient": {
    "id": "uuid",
    "full_name": "string",
    "mrn": "MRN-000042",
    "patient_mrn": "MRN-000042",
    "phone": "string|null"
  },
  "...": "(existing invoice fields)"
}
```

(Both keys are emitted so the existing frontend parsing — `patient['mrn'] ?? patient['patient_mrn']` — works unchanged.)

### `list_patient_invoices` — each row gains `patient_mrn` (same shape as `list_invoices`).

### `list_appointments` — each row gains `patient_mrn`

```json
{
  "items": [
    {
      "id": "uuid",
      "patient_id": "uuid",
      "patient_name": "string",
      "patient_mrn": "MRN-000042",
      "...": "(existing appointment fields)"
    }
  ]
}
```

### Parsing rules (Flutter)

| Model                     | Source key                                          | Fallback             |
| ------------------------- | --------------------------------------------------- | -------------------- |
| `PatientListItem.mrn`     | `row['mrn']`                                        | `row['patient_mrn']` |
| `PatientDetail.mrn`       | `row['mrn']`                                        | `row['patient_mrn']` |
| `AppointmentListItem.patientMrn` | `row['patient_mrn']`                         | `row['mrn']`         |
| `InvoiceListItem.patientMrn` | `row['patient_mrn']` *(already implemented)*    | `row['mrn']`         |
| `InvoiceDetail.patient.mrn` | `patient['mrn']` *(already implemented)*       | `patient['patient_mrn']` |

Display rule: when the resolved value is null/empty, surfaces render `'—'` (per the existing `_PatientCell` convention in `invoice_table.dart`).

---

## Flutter surfaces

### 1. Patients list (`PatientTable`)

**Route**: `/patients`
**Widget**: `frontend/lib/features/patients/presentation/widgets/patient_table.dart`
**Permission**: `patients.view`

**Column addition**:

| Column id | Header | Position        | Accessor (pseudocode)                                | Width | Notes                            |
| --------- | ------ | --------------- | ---------------------------------------------------- | ----- | -------------------------------- |
| `mrn`     | `MRN`  | First (before patient name) | `Text(item.mrn ?? '—', style: AppTypography.mono)` | ~140  | Monospace; distinct from name    |

- Existing columns (patient, phone, DOB, last visit, next visit) keep their current positions, shifted right by one.
- Sort/search by MRN is **not** required in this increment (US-3 acceptance 2 says "if supported"); deferred to P3 polish.
- Empty MRN (`—`) only possible for legacy rows pre-migration — backfill guarantees non-null post-migration, so `'—'` is a defensive fallback.

### 2. Patient details (`PatientDetailPage`)

**Route**: `/patients/:id`
**Widget**: `frontend/lib/features/patients/presentation/pages/patient_detail_page.dart` → `_PatientIdentityCard`
**Permission**: `patients.view`

**Badge/chip**:

- Add an `AppBadge` inside the existing `_PatientIdentityCard` identity `Wrap` of chips.
- Place the MRN badge **first** in the `Wrap` (immediately adjacent to the patient name header).
- Style: `AppBadge(size: BadgeSize.md, variant: BadgeVariant.soft, color: <identifier color — distinct from neutral>, child: Row(mainAxisSize: min, children: [Icon(MrnIcon, size: 14), SizedBox(width: 4), Text(patient.mrn, style: AppTypography.mono)]))`.
- The distinct color makes it pop at a glance (US-4 / SC-004); pick the established "primary"/teal identifier color used elsewhere in `core/ui/theme`.
- Tap behavior: **Copy to clipboard** is optional (P3 polish). Out of scope for this increment unless trivial; spec US-4 acceptance 2 only requires the value to match the stored MRN.

### 3. Add patient success (`AddPatientDialog`)

**Widget**: `frontend/lib/features/patients/presentation/add_patient/add_patient_dialog.dart` + `presentation/providers/patient_registration_notifier.dart`
**Permission**: `patients.create`

**Behavior**:

- `patientRegistrationProvider.submit()` now returns `CreatePatientResult({ patientId, mrn })` (DTO extended; the repository's `createPatient` reads `data?['mrn']`).
- The dialog displays an `appToast` with the generated MRN (e.g., "Patient created — MRN MRN-000042") **before** navigating.
- Navigation target is unchanged: the patient detail page, where the new MRN chip confirms the value.
- On RPC failure (connectivity / validation), the existing `RpcFailure` -> message mapping applies; no MRN is ever fabricated locally (FR-012).

### 4. Invoices list (`InvoiceLedgerTable`)

**Widget**: `frontend/lib/features/billing/presentation/widgets/invoice_table.dart` → `_PatientCell`
**Permission**: `invoices.view`

- **No frontend change required.** `_PatientCell` already renders `item.patientMrn ?? '—'` under the patient name. Once `list_invoices` returns `patient_mrn`, the cells populate automatically.
- Verify after backend deployment that cells show real MRNs instead of `—`.

### 5. Invoice details (`InvoiceHeroCard`, `InvoiceLinkCard`)

**Widget**: `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_hero_card.dart`, `invoice_link_card.dart`; driven by `invoice_detail_page.dart`
**Permission**: `invoices.view`

- **No frontend change required.** `InvoiceHeroCard` accepts `mrn:` and shows ` · $mrnDisplay`; `InvoiceLinkCard` subtitle shows `$patientMrn · $patientPhone`; `invoice_detail_page.dart` passes `mrn: patientMrn`. Once `get_invoice_detail` returns `mrn`, the surface populates.
- Verify after backend deployment.

### 6. Appointments list and tile

**Widget**: `frontend/lib/features/appointments/presentation/widgets/appointment_calendar_tile.dart` (+ the appointment list row)
**Permission**: `appointments.*` (existing view permission)

**Behavior**:

- `AppointmentListItem` gains a `patientMrn: String?` field, parsed from the new `patient_mrn` payload key.
- The tile/list row renders the MRN next to (or under) the patient name, in monospace, e.g., `"$patientMrn · $patientName"`.
- If null/empty, fall back to `patientName` only (no `—` here, to avoid clutter on the dense appointment surface).

### 7. Admin MRN reassignment dialog (NEW)

**Widget**: `frontend/lib/features/patients/presentation/pages/mrn_reassignment_dialog.dart` *(new file)*
**Permission**: `patients.reassign_mrn`
**Entry point**: opened from `PatientDetailPage` actions only when `canReassignPatientMrn` returns true.

**UX contract**:

- Confirmation-style dialog with one input field for the new MRN (pre-filled with the current value, selected for easy overwrite).
- Format hint shown under the field: `MRN-NNNNNN` (e.g. `MRN-000042`).
- **Save** button is disabled while input is empty or unchanged.
- On submit: call `ReassignPatientMrn` usecase → `PatientRepository.reassignPatientMrn(patientId, newMrn)`.
- On `MRN_EXISTS`: show an inline error under the input field ("Another patient already uses this MRN.") and keep the dialog open.
- On `INVALID_INPUT`: show the format hint as an inline error.
- On `PATIENT_ARCHIVED`: close the dialog and surface a toast ("This patient is archived and its MRN cannot be reassigned.").
- On `FORBIDDEN`: close the dialog and surface a toast ("You don't have permission to reassign MRNs."); the entry point should never have appeared, so this is defense-in-depth.
- On success: close the dialog, refresh `patientDetailProvider` (the identity-chip updates to the new MRN on the same screen), toast confirmation. Downstream surfaces (list, invoices, appointments) reflect on next refresh.

### 8. Future: printed/exported reports

No report renderer exists in the current codebase. When one is added, it MUST include the patient's MRN alongside the patient name on any patient-referencing report (US-6 acceptance 2). Tracked as a follow-up, not implemented in this increment.

---

## Surface propagation (FR-008)

All read surfaces derive the MRN via JOIN to `patients.mrn` (no denormalized copy). Therefore:

- After a successful `reassign_patient_mrn`, the **patient-detail chip** updates immediately (same provider refresh).
- The **patients list**, **invoices list**, **invoice detail**, and **appointments list** reflect the new MRN on their **next refresh** (no value migration, no cache invalidation needed beyond Riverpod's normal `ref.invalidate`).

## Out of scope

- Inline MRN editing on the patient record (explicitly forbidden — read-only field for ordinary staff).
- Search/sort by MRN in the patients list (P3 polish; deferred).
- Copy-to-clipboard on the MRN chip (P3 polish; deferred unless trivial).
- MRN column on the visits/encounters list (visits are surfaced within patient detail where the chip already shows the MRN; a separate visits list MRN column is not requested).
- Printed/exported reports (no renderer exists yet).