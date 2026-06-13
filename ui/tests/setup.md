# First setup wizard & owner→administrator UI tests

Comprehensive test coverage for branch `ui/005-first-setup` — clinic setup wizard, deferred bootstrap persistence, owner role removal, and related backend migrations.

**Run frontend:**

```bash
cd frontend && flutter test test/unit/setup/ test/widget/setup/ test/unit/auth/auth_route_guard_test.dart test/unit/settings/permission_matrix_view_test.dart
```

**Run backend (requires `DATABASE_URL`):**

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/owner_role_migration.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/bootstrap_rpc.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/create_staff_rpc.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_crud.sql
```

**Run boundary (live DB):**

```bash
cd frontend && flutter test test/boundary/settings/staff_admin_repository_boundary_test.dart --tags boundary
```

**Source files:**

| File                                                                        | Scope                                            |
| --------------------------------------------------------------------------- | ------------------------------------------------ |
| `frontend/test/unit/setup/setup_notifier_test.dart`                         | Draft flow, atomic finish, dev reset             |
| `frontend/test/unit/setup/setup_step_readiness_test.dart`                   | Next-button readiness helpers                    |
| `frontend/test/unit/setup/staff_role_test.dart`                             | StaffRole enum (no owner)                        |
| `frontend/test/unit/setup/bootstrap_field_options_test.dart`                | Currency/timezone defaults & validation          |
| `frontend/test/unit/setup/bootstrap_repository_test.dart`                   | finishSetup RPC payload (V1 branchIds gap)       |
| `frontend/test/widget/setup/setup_page_test.dart`                           | SetupPage host, password warning, dev panel      |
| `frontend/test/widget/setup/setup_modal_flow_test.dart`                     | Wizard steps, subtitles, staff draft flow        |
| `frontend/test/widget/setup/setup_wizard_nav_bar_test.dart`                 | Nav bar busy/disabled/tooltip states             |
| `frontend/test/widget/setup/staff_form_fields_test.dart`                    | Staff form create/edit, role labels              |
| `frontend/test/widget/setup/setup_first_sign_in_warning_test.dart`          | FirstSignInWarningDialog copy                    |
| `frontend/test/widget/setup/setup_test_support.dart`                        | Shared pump helpers & auth overrides             |
| `frontend/test/unit/setup/branch_field_validation_test.dart`                | Branch phone / maps URL rules                    |
| `frontend/test/unit/setup/staff_password_validation_test.dart`              | Password policy (no digit)                       |
| `frontend/test/unit/setup/provisioning_rules_test.dart`                     | Role selection after owner removal               |
| `frontend/test/widget/setup/setup_wizard_next_button_test.dart`             | Next disabled on clear, focus retention          |
| `frontend/test/widget/setup/setup_modal_staff_step_test.dart`               | Staff subtitle, Finish gate                      |
| `frontend/test/widget/setup/setup_modal_defaults_test.dart`                 | Default currency/timezone, organization subtitle |
| `frontend/test/unit/auth/auth_route_guard_test.dart`                        | Bootstrap wizard in-progress guard               |
| `frontend/test/boundary/settings/staff_admin_repository_boundary_test.dart` | `LAST_ADMINISTRATOR` live RPC                    |
| `backend/tests/owner_role_migration.sql`                                    | Owner enum removal verification                  |
| `backend/tests/bootstrap_rpc.sql`                                           | Atomic `bootstrap_finish_setup`, org/branch RPCs |
| `backend/tests/create_staff_rpc.sql`                                        | Staff provisioning, unlimited administrators     |
| `backend/tests/org_branch_management_crud.sql`                              | Last-administrator demote/deactivate guard       |

**Status legend:** ✅ implemented · 📋 planned / not automatable in CI

**Frontend automation:** 158 tests in `test/unit/setup/` + `test/widget/setup/`, plus auth guard & permission matrix suites (see run command above).

**Companion doc:** [`ui/tests/settings.md`](settings.md) covers `ui/006-settings` (settings hub, clinic admin, staff management).

**Not automated (by design):** release-mode dev panel hiding, step-transition animation frame timing, router redirect refresh integration, debug hot-reload persistence, 320px viewport (known step-indicator overflow — scroll view present but layout overflows).

**Last reconciled:** 2026-06-13 — statuses below reflect automated suites on `ui/006-settings`.

---

## Commit map

| Commit              | Summary                                  | Primary test sections                               |
| ------------------- | ---------------------------------------- | --------------------------------------------------- |
| `b4b3c61`           | Initial setup page                       | Setup page host, wizard steps, step indicator       |
| `e606eb6`           | Dev options grouped in navbar            | Shell dev nav (see `ui/tests/shell.md`)             |
| `3012ee1`           | Setup page floats like login             | Setup page layout, router placement                 |
| `5339c36`           | Styling, step layout, transitions        | Step transition, nav bar, branch validation         |
| `f559a58`           | Next button when mandatory field cleared | Searchable field + text field readiness             |
| `9661b84`           | Default currency/timezone                | Bootstrap field defaults                            |
| `3c2933a`           | Organization fields keep focus           | Focus retention with step transition                |
| `5b9579c`           | Guide text per stage                     | Step subtitles                                      |
| `5548354`           | Draft-based forms, atomic finish         | Notifier drafts, `StaffFormFields`, password policy |
| `407537a`           | **Owner → administrator**                | Backend migrations, RBAC, provisioning, guards      |
| `9483a25`–`49969e6` | Review fixes                             | Last-admin guard, subtitle copy, boundary manifest  |

---

## b4b3c61 — Initial setup page

### SetupPage host

| Test Name                                                | Scenario                                                    | Pass Criteria                                                    | Fail Criteria                        | Status |
| -------------------------------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------ | ------ |
| `renders SetupModal on bootstrap route`                  | Navigate to `/bootstrap` with authenticated bootstrap admin | `SetupPage` and `SetupModal` visible                             | Wrong widget or route                | ✅      |
| `shows first sign-in password warning once`              | Bootstrap admin, `hasShownPasswordWarning: false`           | `FirstSignInWarningDialog` appears; Continue marks warning shown | Dialog skipped or repeats on rebuild | ✅      |
| `does not show password warning for non-bootstrap admin` | Authenticated administrator (not bootstrap)                 | No warning dialog                                                | Warning shown incorrectly            | ✅      |
| `does not show password warning after already shown`     | `hasShownPasswordWarning: true`                             | No dialog on load                                                | Dialog reappears                     | ✅      |
| `navigates home when setup completes`                    | `finishSetup` transitions step to `complete`                | Router navigates to `/home`                                      | Stays on bootstrap                   | ✅      |
| `dev panel hidden in release mode`                       | `kReleaseMode` build                                        | No DEV ONLY panel                                                | Dev buttons visible                  | 📋      |
| `dev panel visible in debug mode`                        | Debug build on SetupPage                                    | Fill dummy + Reset installation buttons visible                  | Panel missing                        | ✅      |

### Setup wizard steps (initial)

| Test Name                                   | Scenario                 | Pass Criteria                              | Fail Criteria      | Status |
| ------------------------------------------- | ------------------------ | ------------------------------------------ | ------------------ | ------ |
| `starts on organization step`               | Fresh `SetupNotifier`    | `step == organization`                     | Wrong initial step | ✅      |
| `step indicator shows three labeled stages` | Modal renders            | Organization, Branch, Staff labels visible | Missing step       | ✅      |
| `organization step shows required fields`   | Organization step active | Name, currency, timezone fields present    | Fields missing     | ✅      |
| `branch step shows required fields`         | Advance to branch        | Name, code, address, phone, maps URL       | Fields missing     | ✅      |
| `staff step shows create form`              | Advance to staff         | Username, full name, password, role fields | Fields missing     | ✅      |

---

## e606eb6 — Dev options at bottom of navbar

Covered in [`ui/tests/shell.md`](shell.md) under shell dev nav. Setup-specific dev actions remain on `SetupPage` (`SetupDevWidgets.panel`), not in the navbar.

| Test Name                                               | Scenario              | Pass Criteria                                   | Fail Criteria           | Status |
| ------------------------------------------------------- | --------------------- | ----------------------------------------------- | ----------------------- | ------ |
| `setup dev widgets render below modal not in shell nav` | SetupPage debug build | Dev panel under `SetupModal`, not in `ShellNav` | Dev controls in sidebar | ✅      |

---

## 3012ee1 — Floating setup page (like login)

| Test Name                                      | Scenario                 | Pass Criteria                                                    | Fail Criteria                       | Status   |
| ---------------------------------------------- | ------------------------ | ---------------------------------------------------------------- | ----------------------------------- | -------- |
| `bootstrap route is top-level not under shell` | Inspect `router.dart`    | `/bootstrap` is sibling of `/login`, not under protected shell   | Bootstrap nested under shell routes | ✅ (code) |
| `setup page shows blurred shell backdrop`      | SetupPage renders        | `BackdropFilter` + `AuthenticatedShell` placeholder behind modal | Plain background only               | ✅        |
| `setup modal centered vertically on scroll`    | Short and tall viewports | Modal centered in `SingleChildScrollView`                        | Modal pinned to top only            | 📋        |
| `setup modal has floating card styling`        | Modal visible            | White card, 24px radius, max width constraint                    | Flat unstyled panel                 | ✅        |

---

## 5339c36 — Styling, step layout, transitions

### SetupStepLayout / SetupStepTransition

| Test Name                                            | Scenario              | Pass Criteria                                  | Fail Criteria               | Status |
| ---------------------------------------------------- | --------------------- | ---------------------------------------------- | --------------------------- | ------ |
| `step transition animates forward direction`         | Organization → Branch | Forward animation; branch step content visible | Instant swap or wrong step  | 📋      |
| `step transition animates backward direction`        | Staff → Back → Branch | Reverse animation direction                    | Wrong animation             | 📋      |
| `transition preserves step content height stability` | Step change mid-form  | No layout jump clipping fields                 | Content clipped or overflow | 📋      |

### SetupWizardNavBar

| Test Name                                        | Scenario             | Pass Criteria                                            | Fail Criteria                              | Status |
| ------------------------------------------------ | -------------------- | -------------------------------------------------------- | ------------------------------------------ | ------ |
| `hides nav bar when showBack and showNext false` | Both flags false     | `SizedBox.shrink`                                        | Empty row still consumes space incorrectly | ✅      |
| `Back disabled while isBusy`                     | `isSubmitting: true` | Back button `onPressed: null`                            | Back tappable during submit                | ✅      |
| `Next shows loading spinner when isBusy`         | Finish in progress   | Next button loading, not tappable                        | No loading state                           | ✅      |
| `disabled Next shows tooltip`                    | `nextEnabled: false` | Tooltip with disabled message; `AbsorbPointer` on button | Button clickable when disabled             | ✅      |
| `embedded mode omits leading Spacer`             | `embedded: true`     | Controls align without spacer                            | Spacer still present                       | ✅      |

### Branch field validation (5339c36)

| Test Name                                       | Scenario                      | Pass Criteria | Fail Criteria | Status |
| ----------------------------------------------- | ----------------------------- | ------------- | ------------- | ------ |
| `validatePhone accepts digits only`             | `201000000000`                | Returns null  | Rejected      | ✅      |
| `validatePhone rejects empty and whitespace`    | `''`, `'   '`                 | Error message | Accepted      | ✅      |
| `validatePhone rejects formatted numbers`       | `+20 100 000 0000`, `123-456` | Error message | Accepted      | ✅      |
| `validateMapsUrl accepts https and http`        | Valid map URLs                | Returns null  | Rejected      | ✅      |
| `validateMapsUrl accepts bare domains`          | `www.google.com`              | Returns null  | Rejected      | ✅      |
| `validateMapsUrl rejects empty and invalid`     | `''`, `not a url`, `ftp://`   | Error message | Accepted      | ✅      |
| `isBranchStepReady false when phone invalid`    | Phone with spaces             | Next disabled | Next enabled  | ✅      |
| `isBranchStepReady false when maps URL invalid` | Invalid maps string           | Next disabled | Next enabled  | ✅      |

---

## f559a58 — Next button when mandatory field cleared

| Test Name                                                        | Scenario                           | Pass Criteria                         | Fail Criteria                 | Status   |
| ---------------------------------------------------------------- | ---------------------------------- | ------------------------------------- | ----------------------------- | -------- |
| `clearing searchable currency disables Next via onChanged(null)` | Select EGP then clear autocomplete | `currency` null; Next readiness false | Stale non-null value          | ✅        |
| `clearing text field updates controller readiness`               | Enter then clear org name          | `nextEnabled` false after clear       | Next stays enabled            | ✅        |
| `clearing branch name disables Next`                             | Branch step, clear name field      | Next disabled                         | Next enabled                  | ✅        |
| `clearing branch code disables Next`                             | Branch step, clear code            | Next disabled                         | Next enabled                  | ✅        |
| `AppAutocomplete onChanged(null) on clear`                       | Autocomplete cleared               | Parent receives null not empty string | Empty string treated as valid | ✅ (code) |

---

## 9661b84 — Default currency and timezone

| Test Name                                              | Scenario                                        | Pass Criteria                             | Fail Criteria              | Status |
| ------------------------------------------------------ | ----------------------------------------------- | ----------------------------------------- | -------------------------- | ------ |
| `modal initializes currency to EGP`                    | Fresh SetupModal                                | `_currency == 'EGP'`; field shows EGP     | Null or wrong default      | ✅      |
| `modal initializes timezone to Africa/Cairo`           | Fresh SetupModal                                | `_timezone == 'Africa/Cairo'`             | Null or wrong default      | ✅      |
| `Next enabled when only defaults set and name filled`  | Enter org name only                             | Next enabled (defaults satisfy readiness) | Next disabled              | ✅      |
| `BootstrapCurrencyOptions.defaultCode is EGP`          | Unit                                            | Constant equals `EGP`                     | Wrong constant             | ✅      |
| `BootstrapTimezoneOptions.defaultZone is Africa/Cairo` | Unit                                            | Constant equals `Africa/Cairo`            | Wrong constant             | ✅      |
| `invalid currency code rejected by notifier`           | `continueToBranchStep(currencyCode: 'NOTREAL')` | Returns false; stays on organization      | Advances with bad currency | ✅      |
| `invalid timezone rejected by notifier`                | Invalid timezone string                         | Returns false; error message              | Advances                   | ✅      |

---

## 3c2933a — Organization fields keep focus

| Test Name                                                                | Scenario                                      | Pass Criteria                                | Fail Criteria                | Status       |
| ------------------------------------------------------------------------ | --------------------------------------------- | -------------------------------------------- | ---------------------------- | ------------ |
| `organization name keeps focus while typing with step transition layout` | Type in org name inside `SetupStepTransition` | Primary focus unchanged across pumps         | Focus lost on each keystroke | ✅            |
| `ListenableBuilder rebuild does not recreate org TextField key`          | Type continuously                             | Same focus node; controller text accumulates | Field recreated each rebuild | ✅ (implicit) |
| `branch fields keep focus while typing`                                  | Type in branch name on branch step            | Focus retained                               | Focus lost                   | ✅            |

---

## 5b9579c — Guide text per stage

| Test Name                                                        | Scenario          | Pass Criteria                                                    | Fail Criteria                     | Status |
| ---------------------------------------------------------------- | ----------------- | ---------------------------------------------------------------- | --------------------------------- | ------ |
| `organization step shows organization subtitle`                  | Organization step | Copy: *Enter your clinic's organization details to get started.* | Missing or wrong text             | ✅      |
| `branch step shows branch subtitle`                              | Branch step       | Copy: *Start with your main branch…*                             | Missing or wrong text             | ✅      |
| `staff step shows staff subtitle requiring at least one account` | Staff step        | Copy: *Create at least one staff account to finish setup…*       | Skip/add-later copy (removed bug) | ✅      |
| `complete step shows ready subtitle`                             | Complete step     | Copy: *Your clinic is ready to use.*                             | Missing                           | ✅      |

---

## 5548354 — Enhanced forms & atomic bootstrap finish

### Deferred persistence (SetupNotifier)

| Test Name                                                         | Scenario                   | Pass Criteria                                    | Fail Criteria               | Status |
| ----------------------------------------------------------------- | -------------------------- | ------------------------------------------------ | --------------------------- | ------ |
| `continueToBranchStep stores draft without organizationId`        | Valid org fields           | Draft stored; `organizationId` null; step branch | RPC called or IDs set       | ✅      |
| `continueToBranchStep rejects invalid currency`                   | Bad currency               | false; stays organization                        | Advances                    | ✅      |
| `continueToStaffStep stores branch draft without branchId`        | Valid branch fields        | Draft stored; `branchId` null                    | RPC called                  | ✅      |
| `continueToStaffStep without org draft redirects to organization` | Call with null org draft   | Error; step organization                         | Proceeds                    | ✅      |
| `goBackToOrganizationStep clears branch and staff drafts`         | From branch/staff back     | Org draft kept; branch/staff cleared             | Drafts retained incorrectly | ✅      |
| `goBackToBranchStep clears staff drafts only`                     | From staff back            | Branch draft kept; staff cleared                 | Org draft cleared           | ✅      |
| `goBackToBranchStep no-op when not on staff step`                 | On organization            | State unchanged                                  | Step changes                | ✅      |
| `advancing org step clears downstream drafts`                     | Org → branch after editing | Branch/staff drafts cleared                      | Stale downstream drafts     | ✅      |

### Staff drafts

| Test Name                                                   | Scenario               | Pass Criteria               | Fail Criteria     | Status |
| ----------------------------------------------------------- | ---------------------- | --------------------------- | ----------------- | ------ |
| `addStaffDraft stores staff locally without RPC`            | Valid staff input      | Draft in state; no network  | RPC invoked       | ✅      |
| `addStaffDraft rejects duplicate username in draft list`    | Same username twice    | Error message; single draft | Duplicate allowed | ✅      |
| `addStaffDraft rejects empty full name`                     | Whitespace name        | Error                       | Draft added       | ✅      |
| `addStaffDraft rejects invalid password`                    | `12345678` (no letter) | Error                       | Draft added       | ✅      |
| `addStaffDraft rejects empty branchIds`                     | No branches selected   | Error                       | Draft added       | ✅      |
| `addStaffDraft rejects role doctor cannot assign`           | Doctor caller          | Provisioning error          | Draft added       | ✅      |
| `addStaffDraft normalizes username`                         | Mixed case username    | Stored normalized           | Raw casing kept   | ✅      |
| `addStaffDraft without session shows sign-in error`         | No auth context        | Error message               | Draft added       | ✅      |
| `addStaffDraft without branch draft returns to branch step` | Missing branch draft   | Error; step branch          | Draft added       | ✅      |

### finishSetup (atomic RPC)

| Test Name                                                       | Scenario                  | Pass Criteria                                  | Fail Criteria            | Status          |
| --------------------------------------------------------------- | ------------------------- | ---------------------------------------------- | ------------------------ | --------------- |
| `finishSetup rejects empty staffDrafts`                         | No drafts                 | Error; stays staff step                        | Submits                  | ✅               |
| `finishSetup rejects missing org draft`                         | No org draft              | Error; step organization                       | Submits                  | ✅               |
| `finishSetup rejects missing branch draft`                      | No branch draft           | Error; step branch                             | Submits                  | ✅               |
| `finishSetup calls bootstrap_finish_setup once with all drafts` | Valid state               | Single RPC; org+branch+staff payload           | Multiple RPCs or partial | ✅ (dummy path)  |
| `finishSetup refreshes session after success`                   | Successful RPC            | Session refresh invoked; `setupRequired` false | No refresh               | ✅               |
| `finishSetup clears drafts and sets org/branch IDs on success`  | Successful RPC            | IDs set; drafts empty; step complete           | Drafts remain            | ✅               |
| `finishSetup surfaces ORG_ALREADY_EXISTS`                       | RPC returns duplicate org | User-facing message contains *already exists*  | Generic error only       | ✅ (message map) |
| `finishSetup surfaces NOT_BOOTSTRAP_ADMIN`                      | Wrong caller              | Message mentions bootstrap administrator       | Wrong message            | ✅ (message map) |
| `finishSetup does not re-validate cleared staff form on Finish` | Draft exists; form empty  | Finish proceeds using drafts                   | Blocked by empty form    | 📋               |
| `finishSetupWithDummyData uses BootstrapDummyData presets`      | Dev fill dummy            | Dummy org/branch/staff in RPC input            | Wrong presets            | ✅               |

### StaffFormFields widget

| Test Name                                              | Scenario                     | Pass Criteria                                            | Fail Criteria           | Status |
| ------------------------------------------------------ | ---------------------------- | -------------------------------------------------------- | ----------------------- | ------ |
| `create mode shows username password role fields`      | `StaffFormFieldsMode.create` | All create fields visible                                | Missing fields          | ✅      |
| `password obscured by default with visibility toggle`  | Create mode                  | `obscureText: true`; toggle reveals                      | Plain password on load  | ✅      |
| `password requirements hint matches backend`           | Create mode                  | *At least 8 characters with one letter.*                 | Digit requirement shown | ✅      |
| `edit mode shows read-only values until Modify tapped` | Edit mode                    | Fields read-only initially                               | Editable immediately    | ✅      |
| `role dropdown lists only selectableRoles`             | Administrator caller         | Administrator, Doctor, Receptionist, Lab staff           | Owner option present    | ✅      |
| `setup staff step hides branch assignments`            | Setup wizard                 | `showBranchAssignments: false`; placeholder branch label | Branch picker shown     | ✅      |
| `username validation rejects @ and short names`        | Invalid usernames            | Validation errors                                        | Accepted                | ✅      |
| `corner case: role label for administrator`            | Select administrator         | Label *Administrator* not *Owner*                        | Owner label             | ✅      |

### Staff draft acknowledgement (setup modal)

| Test Name                                                                   | Scenario        | Pass Criteria                       | Fail Criteria                     | Status |
| --------------------------------------------------------------------------- | --------------- | ----------------------------------- | --------------------------------- | ------ |
| `adding staff draft shows acknowledgement alert with username and password` | Add valid draft | `AppAlert` shows credentials        | No acknowledgement                | ✅      |
| `acknowledgement cleared when leaving staff step`                           | Back to branch  | Alert removed                       | Credentials persist on wrong step | ✅      |
| `form fields cleared after successful draft add`                            | Add draft       | Username/password controllers empty | Old values remain                 | ✅      |
| `Finish enabled after draft add even if form cleared`                       | Add one draft   | `nextEnabled: true`, label Finish   | Finish disabled                   | ✅      |

### Auth route guard (5548354 + router)

| Test Name                                                   | Scenario                            | Pass Criteria                 | Fail Criteria           | Status          |
| ----------------------------------------------------------- | ----------------------------------- | ----------------------------- | ----------------------- | --------------- |
| `setup-complete bootstrap redirects to home`                | Setup complete on `/bootstrap`      | Redirect `/home`              | Stays on bootstrap      | ✅               |
| `bootstrapStaffWizardInProgress keeps bootstrap route`      | Wizard in progress                  | No redirect from bootstrap    | Redirect to home        | ✅               |
| `setup_required protected routes redirect to bootstrap`     | `/app/patients` with setup required | Redirect bootstrap            | Protected route renders | ✅               |
| `setup_required login redirects to home shell`              | Login while setup required          | Redirect home (shell + modal) | Stays login             | ✅               |
| `router listens setupNotifierProvider for redirect refresh` | Step changes during wizard          | Redirect re-evaluated         | Stale redirect          | 📋 (integration) |

### Password policy (5548354 migration + frontend)

| Test Name                                 | Scenario               | Pass Criteria         | Fail Criteria                     | Status |
| ----------------------------------------- | ---------------------- | --------------------- | --------------------------------- | ------ |
| `frontend accepts password without digit` | `Secret12`, `abcdefgh` | Valid                 | Rejected                          | ✅      |
| `frontend rejects short password`         | `short`                | ≥8 chars error        | Accepted                          | ✅      |
| `frontend rejects letterless password`    | `12345678`             | Letter required error | Accepted                          | ✅      |
| `backend accepts password without digit`  | `abcdefgh` via RPC     | Success               | `INVALID_INPUT` for missing digit | 📋      |
| `backend rejects password without letter` | `12345678` via RPC     | `INVALID_INPUT`       | Success                           | 📋      |

### Dev reset

| Test Name                                                    | Scenario              | Pass Criteria                     | Fail Criteria              | Status |
| ------------------------------------------------------------ | --------------------- | --------------------------------- | -------------------------- | ------ |
| `resetInstallationForDevelopment clears wizard on success`   | Successful reset RPC  | Step organization; drafts cleared | State retained             | ✅      |
| `resetInstallationForDevelopment surfaces RESET_SAFE_DELETE` | Migration not applied | Message contains migration hint   | Generic connectivity error | ✅      |
| `resetInstallationForDevelopment refreshes session`          | Success               | Session refresh called            | Stale setupRequired        | 📋      |

---

## 407537a — Owner role removed, replaced with administrator

### Backend migration `20260611150000_remove_owner_role.sql`

| Test Name                                                                  | Scenario                        | Pass Criteria                                       | Fail Criteria                   | Status |
| -------------------------------------------------------------------------- | ------------------------------- | --------------------------------------------------- | ------------------------------- | ------ |
| `staff_role enum has no owner value`                                       | Query `pg_enum` after migration | Only administrator, doctor, receptionist, lab_staff | `owner` label exists            | 📋      |
| `existing owner rows migrated to administrator`                            | Pre-migration owner fixture     | `role = administrator`                              | Row deleted or wrong role       | 📋      |
| `roles_permissions owner rows deleted`                                     | Post migration                  | No `role = owner` rows                              | Owner permission rows remain    | 📋      |
| `assert_owner_or_administrator allows administrator`                       | Administrator JWT               | RPC succeeds                                        | FORBIDDEN                       | 📋      |
| `assert_owner_or_administrator allows bootstrap admin`                     | Bootstrap admin before org      | Bootstrap RPCs succeed                              | NOT_BOOTSTRAP_ADMIN incorrectly | 📋      |
| `build_staff_claims administrator gets org-wide branch access`             | Administrator claims            | All org branches in `branch_ids`                    | Single branch only              | 📋      |
| `update_role_permission billing.manage not delegable to non-administrator` | Doctor toggles billing.manage   | FORBIDDEN                                           | Success                         | 📋      |
| `update_billing_settings requires administrator role`                      | Non-admin caller                | FORBIDDEN                                           | Success                         | 📋      |

### Backend `bootstrap_finish_setup` admin count fix (`20260611160000`)

| Test Name                                            | Scenario                                  | Pass Criteria                     | Fail Criteria          | Status |
| ---------------------------------------------------- | ----------------------------------------- | --------------------------------- | ---------------------- | ------ |
| `finish_setup_operational_roles_only succeeds`       | Bootstrap admin + receptionist draft only | Success                           | NO_ADMINISTRATOR error | ✅      |
| `finish_setup rejects zero staff drafts server-side` | Empty staff array                         | INVALID_INPUT                     | Success                | 📋      |
| `finish_setup_existing_username_rolls_back`          | Duplicate username in auth.users          | USERNAME_EXISTS; no org persisted | Partial org created    | ✅      |
| `finish_setup_happy_path creates org branch staff`   | Valid payload                             | org_id + branch_id returned       | Failure                | ✅      |

### Backend staff provisioning (owner removal)

| Test Name                                      | Scenario                                          | Pass Criteria                       | Fail Criteria                    | Status |
| ---------------------------------------------- | ------------------------------------------------- | ----------------------------------- | -------------------------------- | ------ |
| `bootstrap_creates_first_administrator`        | Bootstrap admin creates administrator             | Success                             | FORBIDDEN_OWNER_CREATE (removed) | ✅      |
| `bootstrap_admin_creates_second_administrator` | Second administrator                              | Success                             | Single-admin cap enforced        | ✅      |
| `admin_can_create_administrator`               | Non-bootstrap administrator creates administrator | Success                             | FORBIDDEN                        | ✅      |
| `staff_doctor_caller_forbidden`                | Doctor creates staff                              | FORBIDDEN                           | Success                          | ✅      |
| `staff_blocked_before_org_setup`               | No org yet                                        | ORG_SETUP_INCOMPLETE                | Success                          | ✅      |
| `staff_empty_branch_ids_rejected`              | Empty branches                                    | INVALID_INPUT                       | Success                          | ✅      |
| `staff_invalid_branch_rejected`                | Unknown branch UUID                               | INVALID_BRANCH                      | Success                          | ✅      |
| `staff_primary_not_in_assignments_rejected`    | Primary outside list                              | INVALID_INPUT                       | Success                          | ✅      |
| `administrator_full_name_trimmed`              | Whitespace full name                              | Trimmed in DB                       | Raw whitespace stored            | ✅      |
| `provisioned_staff_jwt_claims_ready`           | New receptionist                                  | Correct role + branch_ids in claims | Missing claims                   | ✅      |
| `receptionist_branch_assignment_primary`       | New staff                                         | Primary assignment on branch        | Missing assignment               | ✅      |

### Backend last administrator guard (`20260611170000` + crud tests)

| Test Name                                                       | Scenario                                 | Pass Criteria                      | Fail Criteria       | Status |
| --------------------------------------------------------------- | ---------------------------------------- | ---------------------------------- | ------------------- | ------ |
| `staff_deactivate_last_administrator_rejected`                  | Sole active administrator deactivated    | LAST_ADMINISTRATOR                 | Success (lockout)   | ✅      |
| `staff_update_demote_last_administrator_rejected`               | Sole administrator → doctor              | LAST_ADMINISTRATOR                 | Success             | ✅      |
| `staff_deactivate_second_administrator_success`                 | Two administrators; deactivate non-last  | Success                            | LAST_ADMINISTRATOR  | ✅      |
| `staff_deactivate_bootstrap_administrator_success`              | Two administrators; deactivate bootstrap | Success when another admin remains | Incorrect rejection | ✅      |
| `staffAdmin.LAST_ADMINISTRATOR boundary demote bootstrap admin` | Live DB: one admin left                  | RPC LAST_ADMINISTRATOR             | Success             | ✅      |

### Backend cross-suite role renames (407537a)

All SQL suites using `administrator` instead of `owner` must pass unchanged semantics:

| Suite                                         | Status      |
| --------------------------------------------- | ----------- |
| `appointment_management_crud.sql` / `rls.sql` | ✅ (updated) |
| `auth_rbac_extended.sql`                      | ✅           |
| `billing_*.sql`                               | ✅           |
| `patient_management_*.sql`                    | ✅           |
| `shift_management_*.sql`                      | ✅           |
| `visit_medical_records_*.sql`                 | ✅           |
| `jwt_claims_contract.sql`                     | ✅           |

### Frontend StaffRole enum & RBAC UI

| Test Name                                              | Scenario        | Pass Criteria                                      | Fail Criteria      | Status      |
| ------------------------------------------------------ | --------------- | -------------------------------------------------- | ------------------ | ----------- |
| `StaffRole has no owner value`                         | Enum values     | administrator, doctor, receptionist, labStaff only | owner present      | ✅ (compile) |
| `StaffRole.tryParse rejects owner string`              | Parse `'owner'` | null                                               | Returns owner role | ✅           |
| `PermissionMatrixView.displayRoles excludes owner`     | Matrix view     | 4 operational roles                                | Owner column       | ✅           |
| `canAccessOrganizationSettings requires administrator` | Doctor session  | false                                              | true for doctor    | 📋           |
| `canAccessPermissionMatrix requires administrator`     | Doctor session  | false                                              | true               | 📋           |
| `organizationHasOwner use case removed`                | Codebase        | No repository method / use case                    | Dead code remains  | ✅ (removed) |
| `staff_admin_repository has no organizationHasOwner`   | Unit compile    | Method absent                                      | Method exists      | ✅ (removed) |

### ProvisioningRules (407537a)

| Test Name                                               | Scenario            | Pass Criteria                             | Fail Criteria    | Status |
| ------------------------------------------------------- | ------------------- | ----------------------------------------- | ---------------- | ------ |
| `doctor cannot provision`                               | Doctor profile      | false                                     | true             | ✅      |
| `administrator can provision`                           | Administrator       | true                                      | false            | ✅      |
| `bootstrap admin can provision`                         | isBootstrapAdmin    | true                                      | false            | ✅      |
| `administrator selectable roles include administrator`  | Admin caller        | administrator in list                     | Owner-only cap   | ✅      |
| `bootstrap admin may assign administrator during setup` | Bootstrap admin     | validateRoleChoice null for administrator | Error            | ✅      |
| `doctor cannot reset passwords`                         | Doctor              | false                                     | true             | ✅      |
| `administrator can reset passwords`                     | Administrator       | true                                      | false            | ✅      |
| `receptionist cannot provision or assign administrator` | Receptionist caller | canProvision false; empty selectableRoles | Can create admin | 📋      |

### Auth & settings route guards (407537a)

| Test Name                                                  | Scenario               | Pass Criteria        | Fail Criteria       | Status             |
| ---------------------------------------------------------- | ---------------------- | -------------------- | ------------------- | ------------------ |
| `administrator can access organization settings route`     | Admin + setup complete | No redirect          | Redirect settings   | ✅ (existing tests) |
| `doctor redirected from organization settings`             | Doctor                 | Redirect `/settings` | Org settings render | 📋                  |
| `doctor redirected from permission matrix`                 | Doctor                 | Redirect             | Matrix renders      | 📋                  |
| `administrator with manageStaff can access staff settings` | Admin permissions      | Allowed              | Blocked             | ✅                  |

### Login modal (407537a copy)

| Test Name                                            | Scenario          | Pass Criteria           | Fail Criteria | Status |
| ---------------------------------------------------- | ----------------- | ----------------------- | ------------- | ------ |
| `forgot password references administrator not owner` | Forgot panel open | Copy says administrator | Says owner    | 📋      |

---

## 49969e6 — Review fixes (composer)

| Test Name                                             | Scenario                             | Pass Criteria                                | Fail Criteria           | Status |
| ----------------------------------------------------- | ------------------------------------ | -------------------------------------------- | ----------------------- | ------ |
| `staff step subtitle matches Finish gate`             | Staff step, no drafts                | Subtitle requires ≥1 staff; Finish disabled  | Contradictory skip copy | ✅      |
| `Finish stays disabled until staff draft added`       | Staff step widget                    | nextEnabled false → true after addStaffDraft | Finish enabled early    | ✅      |
| `restore_last_administrator_guard migration applied`  | DB has assert_not_last_administrator | Demote/deactivate tests pass                 | Lockout possible        | ✅      |
| `boundary manifest staffAdmin.LAST_ADMINISTRATOR row` | Manifest + test                      | Scenario registered                          | Missing manifest row    | ✅      |

---

## Edge cases & rare scenarios (cross-cutting)

| Test Name                                                       | Scenario                    | Pass Criteria                                | Fail Criteria          | Status                |
| --------------------------------------------------------------- | --------------------------- | -------------------------------------------- | ---------------------- | --------------------- |
| `double-click Finish does not double-submit`                    | Rapid Finish taps           | Single RPC; isSubmitting guards              | Duplicate orgs         | ✅                     |
| `network failure during finishSetup shows connectivity message` | RPC throws non-RpcFailure   | Generic connectivity error                   | Crash or silent fail   | ✅                     |
| `wizard state survives hot reload in debug`                     | Dev hot reload on bootstrap | Drafts restored from notifier                | Total state loss       | 📋                     |
| `very long organization name trimmed not truncated silently`    | 500-char name               | Trimmed; server validates max                | UI crash               | 📋                     |
| `unicode organization name accepted`                            | Arabic clinic name          | Stored correctly                             | Rejected client-side   | ✅                     |
| `branch code uppercase normalization`                           | Mixed case code             | Stored as entered or normalized consistently | Duplicate branch codes | ✅                     |
| `multiple staff drafts all submitted on Finish`                 | 3 drafts                    | All 3 in RPC payload                         | Only last draft sent   | ✅                     |
| `staff draft branchIds not sent to bootstrap_finish_setup (V1)` | Finish payload              | RPC assigns all to new branch                | branchIds in payload   | 📋 (documented V1 gap) |
| `setup_required session cannot open settings staff create`      | `/settings/staff/new`       | Redirect bootstrap                           | Settings page renders  | ✅                     |
| `narrow viewport 320px setup modal scrollable`                  | Small phone                 | Modal usable, no overflow                    | Clipped controls       | 📋                     |
| `wide viewport modal max width 920px`                           | Desktop width               | ConstrainedBox max 920                       | Full-bleed form        | ✅                     |
| `corner case: timezone case insensitive validation`             | `africa/cairo`              | Accepted (normalized)                        | Rejected               | ✅                     |
| `corner case: currency case insensitive`                        | `egp`                       | Normalized to EGP                            | Rejected               | 📋                     |
| `JWT after bootstrap: setup_required false`                     | Post finish claims          | false                                        | true stuck in setup    | ✅ (bootstrap_rpc)     |
| `bootstrap admin assigned primary branch on finish`             | finish_setup                | Primary assignment exists                    | Missing assignment     | ✅                     |

---

## Backend run checklist (full owner-removal regression)

After applying migrations `20260611120000` through `20260611170000`:

```bash
for f in bootstrap_rpc create_staff_rpc org_branch_management_crud auth_rbac_extended jwt_claims_contract; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "backend/tests/${f}.sql" || break
done
```

All tests in those files must pass with zero failures in their temp result tables.
