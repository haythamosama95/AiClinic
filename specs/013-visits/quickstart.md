# Quickstart: Visits Page Redesign (014)

Requires **V1-5** visits (`specs/006-visit-medical-records`) applied. This feature replaces documentation UI and SOAP storage.

## 1. Apply database migration

From repository root with local Supabase running:

```bash
cd backend
supabase migration up
```

Key migration:

- `backend/supabase/migrations/20260628140000_visit_documentation_redesign.sql`

Verify:

- `soap_notes` table dropped
- `visit_clinical_notes`, catalog tables, `visit_vital_signs`, `visit_investigations` exist
- `treatment_plans` has no `start_date` / `end_date` columns
- Dev seed rows present for medications, investigations, predefined vital signs

## 2. Run backend verification

```bash
./tests/run_visit_medical_records_tests.sh
```

Covers (updated):

- `save_visit_documentation` partial save, stale concurrency (`STALE_DOCUMENTATION`)
- `complete_visit` with clinical note → appointment `completed`
- Reject complete when all clinical sections empty (`DOCUMENTATION_REQUIRED_FOR_COMPLETE`)
- Catalog search + save-to-catalog idempotency
- Vital sign and investigation CRUD
- Treatment plan with required `duration` (no dates)
- Treatment date → duration migration on fixture data
- Attachments unchanged
- Cross-branch denial on new tables

## 3. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

### Doctor workflow

1. Sign in as **doctor** with `visits.create` / `visits.edit_soap`
2. Open **Appointments** → **checked in** or **in progress** → **Create visit**
3. On visit documentation page:
   - Enter Complaint, History, Examination, Diagnosis, and/or Plan → **Save**
   - Add vital signs (predefined + custom); accept/decline save-to-catalog prompt on custom
   - Add treatments via medication search; fill dose, frequency, duration
   - Add investigations via search
   - Upload attachments (unchanged)
4. **Submit visit** → appointment **completed**
5. Reopen completed visit → edit documentation sections (post-submit edit)

### Regression

- Patient visit history list still works (metadata only for receptionist)
- Lab staff attachment upload/download rules unchanged
- No SOAP or specialty form UI anywhere
- Pre-V1-5-redesign visits show empty clinical sections (SOAP data discarded)

## 4. Automated Flutter tests

```bash
cd frontend
flutter test test/unit/visits/
flutter test test/widget/visits/
dart analyze lib/features/visits
```

Key new unit tests:

- `catalog_name_normalizer_test.dart`
- Repository wrappers for `save_visit_documentation`, catalog search

## 5. Manual catalog search check (SC-002)

1. Open treatment medication field
2. Type `amox` → results appear before pausing
3. Select catalog item or enter custom `  amoxicillin  ` → displays as `Amoxicillin`
4. Decline catalog save → search `Amoxicillin` on next visit does not find custom entry
5. Accept catalog save on another custom entry → appears in future search

## 6. Spec / plan artifacts

| Doc | Path |
| --- | ---- |
| Spec | `specs/013-visits/spec.md` |
| Plan | `specs/013-visits/plan.md` |
| Data model | `specs/013-visits/data-model.md` |
| Contracts | `specs/013-visits/contracts/` |

Next step: `/speckit-tasks` to generate `tasks.md`.
