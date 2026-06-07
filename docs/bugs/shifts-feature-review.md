# Shifts Feature Review — End-to-End Findings

Scope: `frontend/lib/features/shifts/**` and `backend/supabase/migrations/20260606180000_shift_management.sql` (with related audit-trigger and staff_branch_assignments dependencies).

Findings are ordered by severity. Only items likely to cause bugs, integration failures, architectural violations, or maintenance problems are listed.

---

## 1. [HIGH] `AsyncNotifierProvider.family` wired with the wrong notifier base class

- File: `frontend/lib/features/shifts/presentation/providers/shift_detail_notifier.dart`
- Problem: The provider is declared as
  `AsyncNotifierProvider.autoDispose.family<ShiftDetailNotifier, ShiftDetailState, String>(ShiftDetailNotifier.new)`
  but `ShiftDetailNotifier` extends `AsyncNotifier<ShiftDetailState>` and has a constructor `ShiftDetailNotifier(this.shiftId)`. Riverpod family providers expect the notifier to extend `AutoDisposeFamilyAsyncNotifier<State, Arg>` and to read the family argument via `this.arg`, with a no-arg constructor (`ShiftDetailNotifier.new` => `() => ShiftDetailNotifier`). The current shape will not bind the family arg correctly: either `shiftId` is never injected by the framework, or compilation succeeds only because the signature is being inferred loosely, leading to runtime breakage as soon as the provider is read with different ids. Also note `_loadDetail` already uses the field `shiftId` rather than `arg`, so swapping bases requires touching both places.
- Recommended fix: Make `ShiftDetailNotifier` extend `AutoDisposeFamilyAsyncNotifier<ShiftDetailState, String>` (or the equivalent `AutoDisposeAsyncNotifier` + `family`-friendly mixin), remove the constructor parameter, and read the id with `arg` everywhere it is currently using `shiftId`.

---

## 2. [HIGH] `cancelShift` leaves stale local state with status still `active`

- File: `frontend/lib/features/shifts/presentation/providers/shift_detail_notifier.dart` (`cancelShift` + `_runMutation` with `reloadAfterSuccess: false`)
- Problem: After a successful cancel, `_runMutation` does `state = AsyncData(onSuccess(current.detail).copyWith(...))`, where `current.detail` is the still-active shift snapshot. The local `ShiftDetail.status` and `deleted_at`-derived flags are never updated. Today this is masked because `ShiftDetailPage` navigates away on success, but any other listener (calendar, deep link, race with navigation) will render an "active" shift that has actually been cancelled. It also makes the notifier non-self-consistent and harder to reuse.
- Recommended fix: Either (a) use `reloadAfterSuccess: true` for cancel and let the RPC `get_shift_detail` return the cancelled state, or (b) construct a synthetic cancelled `ShiftDetail` (status = cancelled, isReadOnly = true, updatedAt = now) and apply it in `onSuccess`.

---

## 3. [HIGH] Calendar view swallows all errors and never surfaces real failure codes

- File: `frontend/lib/features/shifts/presentation/providers/shift_calendar_provider.dart` (`refresh`)
- Problem: `try { … } catch (_) { state = … error: 'Could not load shifts. Please retry.' }` collapses every failure into the same generic message. `permission_denied`, `RPC_NOT_APPLIED`, `RPC_NOT_CONFIGURED`, `invalid_date_range`, network errors — all become indistinguishable. The repository already returns rich `RpcFailure` codes with curated user copy in `shift_rpc_messages.dart`; this layer throws it away.
- Recommended fix: Catch `RpcFailure` separately and map via `shiftMessageForRpc`; preserve the code (or at least classify auth/install errors vs transient errors). Log the underlying error with `AppLog`.

---

## 4. [HIGH] Backend eligibility check does not exclude soft-deleted branch assignments

- File: `backend/supabase/migrations/20260606180000_shift_management.sql` (`auth_internal.assert_shift_staff_eligible`)
- Problem: The function checks existence in `staff_branch_assignments` with no `sba.is_deleted = false` predicate. The frontend staff picker (`shift_staff_multi_select.dart`) deliberately filters `is_deleted = false`, so the two sides disagree: a re-assigned-then-removed staff member can no longer be picked in the UI but can still be added via a stale client or another caller — producing assignments the UI considers invalid. It also makes "remove from branch" only enforceable in the UI.
- Recommended fix: Add `AND sba.is_deleted = false` to the `EXISTS` subquery in `assert_shift_staff_eligible`. Consider also asserting `sm.organization_id = jwt_organization_id()` for defense in depth.

---

## 5. [HIGH] Duplicate staff ids in create / modify payloads are not deduped

- Files: `frontend/lib/features/shifts/data/shift_repository.dart` (`createShift`, `modifyAssignments`); `backend/supabase/migrations/20260606180000_shift_management.sql` (`create_shift`, `modify_shift_assignments`)
- Problem:
  - `createShift` iterates the input array and INSERTs one by one. A duplicate id raises a unique-constraint error mid-loop after the shift row is already inserted — leaving an orphaned shift unless the outer transaction rolls back. (PostgREST single-statement RPC will roll back, but the error returned is `23505` which the frontend's `_extractShiftErrorCode` does not recognize and reports as `POSTGREST_ERROR`.)
  - `modify_shift_assignments` raises `staff_already_assigned` on the second occurrence — surfaced as a real assignment conflict — and `[idA, idA]` in the remove array raises `staff_not_eligible` after the first delete succeeds.
  - The frontend passes raw `List<String>` from `Set` (so usually deduped), but the public API contract does not enforce it.
- Recommended fix: Dedup `p_staff_ids` / `p_add_staff_ids` / `p_remove_staff_ids` with `SELECT DISTINCT` or `array(select distinct unnest(...))` at the top of each backend function. As a secondary defense, dedupe on the client.

---

## 6. [MEDIUM] `ShiftBranchSummary` rejects branches with empty `code`

- File: `frontend/lib/features/shifts/domain/shift_detail.dart` (`ShiftBranchSummary.fromRow`)
- Problem: `code` is required non-empty, otherwise the entire `ShiftDetail.fromRpcData` returns null and the repository throws `StateError('Shift detail was returned in an unexpected shape.')`. The branches schema does not guarantee a non-empty `code` (it is a label, not a constraint). A single legitimate branch without a populated `code` makes the entire shift detail page unusable.
- Recommended fix: Make `code` optional on the frontend (`String? code`), or fall back to empty string when missing. The same applies to `name` if branches can ever have a blank trimmed name (unlikely but worth verifying).

---

## 7. [MEDIUM] `_extractShiftErrorCode` substring match is order-sensitive and can mis-classify

- File: `frontend/lib/features/shifts/data/shift_repository.dart`
- Problem: The list is checked with `message.startsWith(code) || message.contains(code)`. `shift_cancelled` is a substring of nothing dangerous today, but `shift_overlap` is matched by any message that simply mentions the word — e.g. a future error like `shift_overlap_unresolved` would be misclassified. Also, the `23505` unique-violation code (and other Postgres SQLSTATEs that surface in `error.message`) falls through to `POSTGREST_ERROR`, dropping useful information.
- Recommended fix: Match on a delimiter (e.g. `^code(:|$| )`) or rely on `error.code` / a structured payload from the RPC instead of the message body. Map `23505` to a known code.

---

## 8. [MEDIUM] `shift_overlap` payload is encoded as a stringified JSON inside an error message

- Files: `backend/supabase/migrations/20260606180000_shift_management.sql` (`assert_no_staff_shift_overlap`); `frontend/lib/features/shifts/domain/shift_overlap_conflict.dart` (`parseFromRpcMessage`)
- Problem: Conflict details travel in the human-readable `RAISE EXCEPTION 'shift_overlap: %', v_conflicts::text` string and are recovered with substring + `jsonDecode`. Any change in Postgres error formatting, locale prefixes (`ERROR:` etc.), or the addition of a hint/detail line will silently drop conflict details and degrade the UX to a generic banner. It also conflates an error channel with a data channel.
- Recommended fix: Return the conflicts as data: have the RPC return a result object (e.g. `{success, error_code, conflicts}`) on overlap rather than raising; or alternatively use `RAISE … USING DETAIL = v_conflicts::text` and parse `error.details` in the client (more stable than message body).

---

## 9. [MEDIUM] `ShiftStaffMultiSelect` does not react to active branch changes

- File: `frontend/lib/features/shifts/presentation/widgets/shift_staff_multi_select.dart`
- Problem: Staff list is loaded once in `initState` from `authSessionProvider.context?.activeBranchId`. If the active branch changes while the create/edit page is open (the calendar provider already listens for this), the picker keeps showing staff from the previous branch and the form will submit ids the backend rejects with `staff_not_eligible`.
- Recommended fix: `ref.listen` on `authSessionProvider` (or on the relevant branch field) and re-run `_loadStaff` when it changes; or accept the branch id as a widget parameter and use `didUpdateWidget` to refetch.

---

## 10. [MEDIUM] Repository bypasses the data/use-case boundary by calling Supabase directly from a widget

- File: `frontend/lib/features/shifts/presentation/widgets/shift_staff_multi_select.dart`
- Problem: A presentation widget reads `supabaseClientProvider` and runs `from('staff_branch_assignments').select(...)` inline. This breaks the repository pattern used elsewhere in the feature, makes the query untestable without a real Supabase instance, and couples the widget to the table schema (`is_deleted`, embedded `staff_members`). When the staff/branch schema evolves this is the file most likely to silently break.
- Recommended fix: Move the query into a repository (e.g. `BranchStaffRepository.listActiveStaffForBranch(branchId)` or a method on `ShiftRepository`) returning a domain model. Have the widget consume a `FutureProvider`/`AsyncNotifier`. This also enables mocking in widget tests.

---

## 11. [MEDIUM] Notes length validated on character count, not on backend's trimmed-length rule

- Files: `frontend/lib/features/shifts/presentation/widgets/shift_form_fields.dart` (`validator`); backend `create_shift` / `update_shift` (`length(trim(notes)) <= 500`)
- Problem: Frontend validator counts trimmed chars and the form submits the raw text trimmed; the backend constraint and check use `length(trim(notes))`. Internal whitespace counts toward the length on both sides today, but the backend `CHECK (length(trim(notes)) <= 500)` and the function-level check use slightly different rules from the form's `(value ?? '').trim().length`. Edge cases with embedded newlines / non-BMP characters may produce a frontend-accepted, backend-rejected `notes_too_long`. The form also does not enforce `maxLength` on the input itself.
- Recommended fix: Add a `maxLength: 500` and an `inputFormatters` cap on the `AppFormField`; align the validator to the backend rule (count after `trim`, in characters). Optionally surface the live counter to users.

---

## 12. [MEDIUM] Calendar week start is hard-coded to Monday with no locale awareness

- File: `frontend/lib/features/shifts/presentation/providers/shift_calendar_provider.dart` (`boundsFor`)
- Problem: Week always starts on `DateTime.monday`. Many locales (US, JP, etc.) start the week on Sunday/Saturday. Hard-coding this also limits future "first day of week" preferences per organization or user.
- Recommended fix: Derive the first weekday from `MaterialLocalizations.firstDayOfWeekIndex` or from organization settings; make the week-bounds function accept a `firstWeekday` parameter (already trivially extendable).

---

## 13. [MEDIUM] `setBranchFilter` always sets `loading: true` and refetches even when the branch did not actually change

- File: `frontend/lib/features/shifts/presentation/providers/shift_calendar_provider.dart` (`setBranchFilter`, `ref.listen` in `build`)
- Problem: When auth context emits but branch id is unchanged (e.g. organization re-resolved), the listener still fires `setBranchFilter(nextBranch)` because the listener only suppresses when `prevBranch != nextBranch` — but `setBranchFilter` itself does not early-return on equality. Combined, a normalized null vs empty string difference will trigger an unnecessary RPC, brief loading spinner, and potential flicker. More importantly, it can race with an in-flight `refresh` started by a focus/mode change, and the older response can overwrite the newer one (no request id / cancellation).
- Recommended fix: Early-return in `setBranchFilter` when normalized branch id equals current. Add a request token (incrementing int) inside `refresh` and discard responses whose token is stale.

---

## 14. [MEDIUM] `list_shifts` filters cancelled rows in two redundant places, but does not include cancelled rows for any caller

- File: `backend/supabase/migrations/20260606180000_shift_management.sql` (`auth_internal.list_shifts`)
- Problem: Inner query filters `s.deleted_at IS NULL`; outer query filters `sub.status <> 'cancelled'`. The first filter already guarantees the second. More importantly, there is no parameter to opt-in to cancelled shifts, which makes future "show cancelled" / audit views require either a new RPC or a SQL change. The function does not accept a `p_include_cancelled` boolean.
- Recommended fix: Drop the redundant outer filter, and add a `p_include_cancelled boolean DEFAULT false` parameter (or split into `list_shifts` and `list_cancelled_shifts`). The current shape is a known extendability pinch-point.

---

## 15. [MEDIUM] No pagination / hard upper bound on `list_shifts`

- File: `backend/supabase/migrations/20260606180000_shift_management.sql` (`list_shifts`); `frontend/.../shift_repository.dart`
- Problem: The function returns all matching shifts as a single `jsonb` aggregate. Frontend always queries a week or month, but nothing prevents a future caller from passing `[1900-01-01, 9999-12-31]` and OOM-ing both DB and client. Also makes adding "list all my upcoming shifts" / org-wide reports painful without a new RPC.
- Recommended fix: Enforce a max range (e.g. 366 days) in the function with a `RAISE EXCEPTION 'invalid_date_range'`, and/or add `p_limit`, `p_offset` parameters. Mirror the bound on the client side.

---

## 16. [LOW] `assert_no_staff_shift_overlap` validates time range but `update_shift` validates first — inconsistent ordering

- File: `backend/supabase/migrations/20260606180000_shift_management.sql`
- Problem: `assert_no_staff_shift_overlap` raises `shift_invalid_time_range` if `p_end_time <= p_start_time`. `update_shift` validates `p_end_time <= p_start_time` itself first and raises `shift_invalid_time_range`, so this is unreachable on that path. `create_shift` likewise pre-validates. The duplicate gives the helper an unrelated responsibility (input validation), and lets a future direct caller emit overlap-related errors when the real problem is bad inputs.
- Recommended fix: Drop the input check from `assert_no_staff_shift_overlap` (keep callers responsible for valid input), or convert the helper into one with a single clear contract.

---

## 17. [LOW] `update_shift` always overwrites `notes` even if the caller did not intend to

- File: `backend/supabase/migrations/20260606180000_shift_management.sql` (`update_shift`); `frontend/.../shift_repository.dart::updateShift`
- Problem: The frontend omits `p_notes` from the JSON body when notes is empty; PostgREST then uses the function's `DEFAULT NULL`, which the backend treats as "clear notes". So a user editing only the time of a shift with non-empty notes will lose them unless the form is initialized correctly. The detail page does initialize `_notesController.text = detail.notes ?? ''` on edit-mode entry, so today this works — but the contract is fragile. Any caller that omits `p_notes` will silently wipe notes.
- Recommended fix: Either (a) always send `p_notes` (current value) from the client and document that the field is mandatory in update, or (b) introduce a sentinel (e.g. a separate `p_clear_notes boolean` or accept a JSON patch object) so omitted means "leave unchanged".

---

## 18. [LOW] `shift_assignment_result.fromRpcData` requires `updated_at`, but a future status-only response would break parsing

- File: `frontend/lib/features/shifts/domain/shift_assignment_result.dart`
- Problem: `if (updatedAt == null) return null` causes the repository to throw `StateError('Assignment change succeeded but the response was unexpected.')` if the backend ever omits `updated_at` (e.g. in an idempotent no-op response). Today the backend always sets it, but the asymmetry between this and `ShiftDetail.updatedAt` (nullable) is inconsistent.
- Recommended fix: Make `updatedAt` nullable here too, or have the caller verify presence only when it intends to use it for the next mutation's optimistic check.

---

## 19. [LOW] `_loadDetail` checks permissions once at provider build; permission revocation is not observed

- File: `frontend/lib/features/shifts/presentation/providers/shift_detail_notifier.dart`
- Problem: `_loadDetail` reads `permissionServiceProvider.canViewShifts()` once. If the user's permissions change while the detail page is open (role change pushed via realtime / refresh), the page stays in its current state until manually reloaded. The mutation methods also don't re-check permissions client-side; they rely on backend enforcement (which is correct), but they do not invalidate UI when permission is lost.
- Recommended fix: Either `ref.listen` the permission service inside the notifier and `reload()` on changes, or accept that the backend will return `permission_denied` and ensure that error is mapped to a clear UI state.

---

## 20. [LOW] `ShiftListItem.notesPreview` length depends on backend trimming

- Files: `backend ... list_shifts` (`left(trim(s.notes), 80)`); `frontend ... ShiftDetail.toListItem()` (`notes.length <= 80 ? notes : notes!.substring(0, 80)`)
- Problem: The list RPC trims first then takes 80 chars; `toListItem` uses raw notes (no trim). If a user creates a shift with `"   foo   "` (after backend trim it becomes `"foo"`), `toListItem` produces `"   foo   "` — divergent preview between list view and detail-derived list view.
- Recommended fix: Apply the same trim in `toListItem`, or have the detail RPC return `notes_preview` directly so the client never recomputes it.

---

## 21. [LOW] Audit log writes in mutation RPCs use `auth.uid()` but the function is `SECURITY DEFINER`; no fallback when called by service roles

- File: `backend/supabase/migrations/20260606180000_shift_management.sql`
- Problem: All mutation functions persist `user_id := auth.uid()`. If a future scheduled job / service role calls them through `SECURITY INVOKER` wrappers without a JWT, `auth.uid()` is null and the audit row is created without an actor. There's no validation that `auth.uid()` is non-null at function entry. Today only authenticated end users hit these via the public wrappers, but extending the feature to admin/automation will silently drop the actor.
- Recommended fix: At the top of each mutation, `IF auth.uid() IS NULL THEN RAISE EXCEPTION 'permission_denied'`. Or require an explicit `p_actor_id` for non-JWT callers.

---

## 22. [LOW] Tests for the frontend do not exercise the family wiring or family argument

- Folders: `frontend/test/unit/shifts`, `frontend/test/widget/shifts`
- Problem: Without family-arg-aware tests, the issue raised in finding #1 is invisible. Add a widget test that builds two pages with different `shiftId` and asserts each notifier instance loads the correct id.
- Recommended fix: Add the missing test and run it as part of CI for this feature.

---

## Summary of priorities

1. Fix the family/notifier wiring (#1) — risk of cross-shift state bleed.
2. Fix cancel-success local state (#2) and calendar error swallowing (#3).
3. Backend eligibility/uniqueness hardening (#4, #5).
4. Tighten the `branch.code` requirement (#6) and overlap-payload channel (#8).
5. Tackle extendability/maintenance items (#10, #14, #15, #17) before adding new shift workflows.
