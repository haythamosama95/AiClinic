# Research: Patient Management

## Decision 1: Extend `auth_internal` + public RPC wrappers (same as V1-1/V1-2)

- **Decision**: Patient mutations and search run in `auth_internal` (SECURITY DEFINER) with thin `public.*` INVOKER wrappers returning `rpc_result`.
- **Rationale**: Constitution III; permission checks (`patients.*`), national ID uniqueness, optimistic locking, deduplication, and audit stay in PostgreSQL.
- **Alternatives considered**: Direct PostgREST INSERT/UPDATE on `patients` (rejected — bypasses centralized validation and duplicate policy). Edge Functions (rejected — cloud-only).

## Decision 2: Organization-scoped RLS without branch-assignment filter on `patients`

- **Decision**: RLS uses org isolation via registering `branch_id` → `branches.organization_id = jwt.organization_id`; no `branch_ids` JWT filter on SELECT/UPDATE paths for patients.
- **Rationale**: Clarification session — cross-branch view/edit/archive within org; matches `docs/architecture/05-database.md` patient example (`org_isolation` only).
- **Alternatives considered**: Branch-assignment-scoped reads like appointments (rejected — contradicts clarified spec). Active-branch-only mutations (rejected).

## Decision 3: Phone storage and search

- **Decision**: Persist `phone` as digits-only (strip non-digits on write); validate length 8–15 when provided; prefix search uses `phone LIKE normalized_query || '%'` (min 2 digits).
- **Rationale**: Clarified prefix match; consistent indexing on `branch_id, phone`; avoids formatting breaking search.
- **Alternatives considered**: Store formatted display string (rejected — harms prefix match). E.164 strict regex only (rejected — too rigid for regional clinics).

## Decision 4: Gender enum

- **Decision**: Add `public.patient_gender` enum: `male`, `female`, `other`, `unknown`; column nullable.
- **Rationale**: Schema-level validation; optional field per spec; `unknown` for unspecified UI state.
- **Alternatives considered**: Free-text gender (rejected — reporting inconsistency). Required gender (rejected — spec allows name-only registration).

## Decision 5: Denormalized `organization_id` on `patients`

- **Decision**: Add `organization_id` FK on `patients`, set from registering branch at create; use for RLS and partial unique index `(organization_id, lower(trim(national_id)))`.
- **Rationale**: FR-012; avoids invalid index expressions; faster org isolation checks than joining branches on every policy.
- **Alternatives considered**: Org derivation only via `branch_id` join in RLS (acceptable but heavier); app-only national ID check (rejected).

## Decision 6: Unified list search input with field detection

- **Decision**: Single search box on patient list; if trimmed query is all digits → phone prefix search (min 2); otherwise name contains (min 3). Same rules for branch vs all-branches scope.
- **Rationale**: Reception desk UX; matches clarified match rules without two separate fields.
- **Alternatives considered**: Separate name and phone fields (rejected — slower desk workflow unless user requests later).

## Decision 7: Scope control on list (session state)

- **Decision**: Riverpod `PatientListScope` notifier: default `thisBranch` on sign-in; persist in memory until sign-out (not local disk).
- **Rationale**: Clarification — reset each sign-in; no cross-session scope memory.
- **Alternatives considered**: Persist scope in `SharedPreferences` (rejected — contradicts reset-on-sign-in).

## Decision 8: Optimistic concurrency on update

- **Decision**: `update_patient` requires `p_expected_updated_at timestamptz`; compare to row `updated_at`; mismatch → `STALE_PATIENT` error.
- **Rationale**: Clarification session; standard pattern with existing audit `updated_at` trigger.
- **Alternatives considered**: Silent last-write-wins (rejected).

## Decision 9: Deduplication advisory flow

- **Decision**: `check_patient_duplicates` returns candidate rows; `create_patient` / `update_patient` accept `p_acknowledge_duplicate boolean` — when false and candidates exist (phone, name+DOB, or national ID advisory), return `DUPLICATE_WARNING` with candidate list in `data`.
- **Rationale**: FR-011; national ID conflict remains separate hard error `NATIONAL_ID_EXISTS`.
- **Alternatives considered**: Block all duplicates without acknowledge (rejected — spec allows proceed after confirm).

## Decision 10: Flutter module `features/patients`

- **Decision**: New feature module per `docs/architecture/07-frontend.md`; routes under `/patients`; shell home links to patient list when `patients.view` granted.
- **Rationale**: Domain boundary; keeps `settings` for admin only.
- **Alternatives considered**: Place under `settings` (rejected — operational not admin).

## Decision 11: Pagination defaults

- **Decision**: Default page size 25; max 100 per request; sort `full_name ASC` for browse, `full_name ASC` for search results.
- **Rationale**: NFR-002 (500 patients/branch); aligns with typical data table patterns in V1-0 shared widgets.
- **Alternatives considered**: 50 default (acceptable alternate — 25 chosen for faster first paint).

## Decision 12: PermissionKeys extension

- **Decision**: Add `patientsCreate`, `patientsEdit`, `patientsDelete` to `PermissionKeys`; extend `PermissionService` helpers `canViewPatients`, etc.
- **Rationale**: Seed already grants keys; frontend currently only exposes `patientsView` in `PermissionKeys`.
- **Alternatives considered**: String literals in widgets (rejected — inconsistent with project).

## Decision 13: Archive via soft-delete RPC only

- **Decision**: `archive_patient` sets `is_deleted`, `deleted_at`, `deleted_by` via shared soft-delete helper pattern; no hard DELETE grant to authenticated role.
- **Rationale**: Constitution IV; spec FR-010.
- **Alternatives considered**: `is_active` flag separate from soft delete (rejected — platform uses `is_deleted` for archival).
