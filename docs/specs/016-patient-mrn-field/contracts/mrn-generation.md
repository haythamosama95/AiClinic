# Contract: MRN Generation & Reassignment

## Purpose

Server-side generation and admin-only restricted reassignment of the patient Medical Record Number (MRN). All generation is deterministic and DB-owned; all reassignment is permission-gated, duplicate-validated, and audited.

## Authorization

| RPC                       | Permission                | Scope                              |
| ------------------------- | ------------------------- | ---------------------------------- |
| `create_patient` (extend) | `patients.create` (existing) | Active branch for `branch_id`   | Now returns the generated `mrn` in its payload |
| `reassign_patient_mrn` (NEW) | `patients.reassign_mrn` (NEW) | Org (patient in caller org; not archived) |

`patients.reassign_mrn` is seeded **administrator only**; all other roles revoked.

---

## Generation (internal, not directly callable)

### `auth_internal.assign_patient_mrn()`

- **Visibility**: `auth_internal` schema — `SECURITY DEFINER`; **not** granted to any role. Callable only inside other `auth_internal` RPCs (`create_patient`, future bulk import).
- **Returns**: `text` — `format('MRN-%s', lpad(nextval('public.patient_mrn_seq')::text, 6, '0'))` (e.g., `MRN-000001`).
- **Atomicity**: `nextval` on a native PostgreSQL sequence — no row lock, no retry loop (per FR-010).
- **Backstop**: `UNIQUE` index `patients_mrn_unique` makes any concurrent collision physically impossible.

### `create_patient` (extended payload — signature otherwise unchanged)

| Parameter | Type | Required | Note |
| --------- | ---- | -------- | ---- |
| *(existing params unchanged)* | | | |

**New behavior**: Inside the same transaction as the `patients` row insert, the RPC calls `assign_patient_mrn()` and stores the resulting value in the new `mrn` column.

**Returns** (extended `rpc_result.data`):

```json
{
  "patient_id": "uuid",
  "mrn": "MRN-000042"
}
```

- The `mrn` is also included in the `patient.create` audit row's `new_data_json`.
- On duplicate-national-id / duplicate-advisory / stale-update paths the response shape is unchanged from V1-3.

**Errors**: inherited from V1-3 (`FORBIDDEN`, `INVALID_INPUT`, `NATIONAL_ID_EXISTS`, `DUPLICATE_WARNING`, `BRANCH_REQUIRED`). No new error codes from the MRN extension (sequence generation cannot fail on the common path).

---

## RPC: `reassign_patient_mrn`

### Parameters

| Parameter       | Type | Required | Notes                                              |
| --------------- | ---- | -------- | -------------------------------------------------- |
| `p_patient_id`  | uuid | Yes      | Patient to reassign (must be in caller org)        |
| `p_new_mrn`     | text | Yes      | Target MRN string; trimmed + uppercased by the RPC |

### Rules

1. `assert_permission('patients.reassign_mrn')` — non-admin → `FORBIDDEN`.
2. `assert_org_patient(p_patient_id, p_allow_archived => false)` — cross-org or archived → `NOT_FOUND` / `PATIENT_ARCHIVED`.
3. Normalize `p_new_mrn := upper(trim(p_new_mrn))`.
4. Validate format against `^MRN-\d{6,}$`; otherwise → `INVALID_INPUT` (`'MRN must be in format MRN-NNNNNN'`).
5. Reject if `p_new_mrn` equals the patient's current `mrn` (no-op) → `INVALID_INPUT` (`'MRN is already set to this value'`).
6. Check uniqueness excluding self:

```sql
SELECT 1 INTO v_conflict
  FROM public.patients p
 WHERE p.mrn = p_new_mrn
   AND p.id <> p_patient_id;
IF v_conflict IS NOT NULL THEN
  RETURN public.rpc_error(
    'MRN_EXISTS',
    'Another patient already uses this MRN.',
    jsonb_build_object('conflicting_mrn', p_new_mrn)
  );
END IF;
```

7. Update the row and audit:

```sql
UPDATE public.patients
   SET mrn = p_new_mrn,
       updated_at = now(),
       updated_by = auth.uid()
 WHERE id = p_patient_id;

INSERT INTO public.audit_log
  (user_id, organization_id, action, table_name, record_id,
   old_data_json, new_data_json)
VALUES
  (auth.uid(), v_org_id, 'patient.mrn_reassign', 'patients', p_patient_id,
   jsonb_build_object('mrn', v_old_mrn),
   jsonb_build_object('mrn', p_new_mrn));
```

8. Return success.

### Returns

```json
{ "patient_id": "uuid", "mrn": "MRN-000999" }
```

### Errors

| Code             | When                                                                          |
| ---------------- | ----------------------------------------------------------------------------- |
| `FORBIDDEN`      | Caller lacks `patients.reassign_mrn`                                          |
| `NOT_FOUND`      | Patient not in caller org                                                     |
| `PATIENT_ARCHIVED` | Patient is soft-deleted                                                     |
| `INVALID_INPUT`  | Empty / malformed `p_new_mrn`; or same as current value                       |
| `MRN_EXISTS`     | Another patient already has this MRN (data: `{"conflicting_mrn": "<value>"}`) |

### Public wrapper

`public.reassign_patient_mrn(p_patient_id uuid, p_new_mrn text)` — `SECURITY INVOKER`, `LANGUAGE sql`, thin wrapper to `auth_internal.reassign_patient_mrn`, `GRANT EXECUTE ON FUNCTION public.reassign_patient_mrn(uuid, text) TO authenticated;`

---

## Dev reset helper (updated)

`backend/tests/dev_reset_clinic_installation.sql` must be extended to delete patients and reset the sequence so a fresh dev install reproduces `MRN-000001`:

```sql
DELETE FROM public.patients WHERE is_deleted = false;
-- (after the existing patients clearing)
SELECT setval('public.patient_mrn_seq', 1, false);
```

This guarantees deterministic MRN tests (`expect(firstMrn, 'MRN-000001')`).

---

## Error codes (client mapping)

| Code               | User message (representative)                                                |
| ------------------ | ---------------------------------------------------------------------------- |
| `MRN_EXISTS`       | Another patient already uses this MRN.                                       |
| `INVALID_INPUT`    | MRN must be in format `MRN-NNNNNN` (e.g. `MRN-000001`).                      |
| `PATIENT_ARCHIVED` | This patient is archived and its MRN cannot be reassigned.                   |
| `FORBIDDEN`        | You don't have permission to reassign MRNs. Contact an administrator.        |

The frontend `AppRpcInvoker` already maps `PGRST202`/`42501`/connectivity errors to actionable messages; no new mapping is required beyond `MRN_EXISTS` / `INVALID_INPUT` display strings in the reassignment dialog.