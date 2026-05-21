# Feature Specification: Organization and Branch Management

**Feature Branch**: `specs/003-org-branch-management`

**Created**: 2026-05-21

**Status**: Draft

**Input**: User description: "Read V1-2 from @docs/architecture/12-roadmap-phases.md and according to the best practices of speckit, create the third spec"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

This feature delivers the operational administration layer for a clinic tenant after authentication exists. Clinic owners and administrators need durable screens to maintain organization identity and locale settings, manage branches, provision and maintain staff accounts with branch assignments, review and adjust the role-permission matrix, and switch active branch context during a session without relying on bootstrap-only flows or placeholder UI from V1-1.

The primary beneficiaries are clinic owners and administrators who configure how the clinic runs day to day, and all staff who work at multiple branches and need a reliable branch switcher in the main shell. Reception and clinical modules in later roadmap phases depend on correct branch scope, staff roster, and permission enforcement established here.

V1-1 (`specs/002-auth-rbac`) introduced the tenancy schema, row-level isolation, bootstrap organization and branch creation, minimal staff provisioning, password reset by administrators, and a placeholder active-branch selector. This feature replaces those minimal paths with full management experiences while preserving single-organization-per-installation, soft-delete conventions, and defense-in-depth permission checks.

## Clarifications

### Session 2026-05-21

- Q: Can this feature create a second organization on one installation? → A: No — each installation remains exactly one organization, consistent with V1-1; only organization settings are editable, not additional tenants.
- Q: Who may edit the role-permission matrix? → A: Owners may view and change grants for any role; administrators may view the matrix but cannot change grants (prevents privilege escalation without an owner).
- Q: What happens to the V1-1 placeholder branch selector and minimal bootstrap pages? → A: The branch switcher moves to the main status bar or sidebar; organization, branch, and staff management use dedicated settings-area screens that supersede minimal bootstrap flows once setup is complete.
- Q: How is branch deactivation different from soft delete? → A: Deactivate sets `is_active = false` so the branch is hidden from normal pickers and assignment lists but retained for audit; soft delete (`is_deleted`) remains for irreversible operational removal and follows existing schema conventions.
- Q: Can deactivated staff or branches be reactivated? → A: Yes — owners or administrators with the appropriate manage permission may reactivate inactive staff or branches without creating duplicate records.
- Q: Who may view and edit organization settings? → A: Owner and administrator roles may view and update organization profile fields; authorization is by role, not a separate `settings.manage_organization` permission key.
- Q: What happens when someone tries to deactivate the last active branch? → A: Hard block — deactivation is rejected with a clear message; the UI offers to open edit for that branch so administrators can update branch details instead of deactivating the only active branch.
- Q: When do permission-matrix changes take effect for staff already signed in? → A: On next login and when the client reloads auth context (e.g. app resume, post-save permission refresh, or explicit refresh if provided); running sessions do not pick up matrix changes until one of those reloads.
- Q: If a staff member’s only branch assignments are to deactivated branches, what happens at sign-in? → A: Sign-in succeeds but the user lands in the blocked shell with no active branch—the same experience as V1-1 staff with no branch assignments, with guidance to contact an administrator.
- Q: Should V1-2 management UI expose soft delete, or only deactivate/reactivate? → A: Deactivate and reactivate only; soft delete (`is_deleted`) is not offered in V1-2 management screens and remains a backend convention for maintenance or a future admin tool.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Maintain Organization Settings (Priority: P1)

As a clinic owner or administrator, I can view and update my clinic’s organization profile (name, branding, locale, and basic configuration) so the product reflects how the business presents itself and operates across branches.

**Why this priority**: Organization context is the tenant root; incorrect or missing settings affect billing display, timestamps, and staff trust in the system.

**Independent Test**: Can be fully tested by signing in as an owner or administrator, opening organization settings, updating allowed fields, saving, and confirming values persist and appear on next sign-in.

**Acceptance Scenarios**:

1. **Given** a signed-in owner or administrator, **When** they open organization settings, **Then** they see the current organization name, logo reference, currency, timezone, and readable summary of organization-wide settings.
2. **Given** valid updated organization fields, **When** an owner or administrator saves, **Then** changes persist, success is confirmed, and other signed-in sessions see updated values after refresh or next login context load.
3. **Given** a signed-in user who is not an owner or administrator, **When** they attempt to open or save organization settings, **Then** the action is blocked with a clear permission-denied outcome.
4. **Given** an installation that already has one organization, **When** a user attempts to create another organization, **Then** the action is blocked with guidance that only one organization is supported per installation.

---

### User Story 2 - Manage Branches (Priority: P1)

As a clinic owner or administrator, I can list, create, edit, deactivate, and reactivate branches so the clinic can reflect its real locations and control which branches appear in operational workflows.

**Why this priority**: Branch scope anchors staff assignments and all future operational data; branch management must exist before patient and appointment modules.

**Independent Test**: Can be fully tested by creating a second branch, editing its details, deactivating it, confirming it disappears from active branch lists, reactivating it, and verifying row-level isolation still limits access to the user’s organization.

**Acceptance Scenarios**:

1. **Given** a user with branch-management permission, **When** they open branch management, **Then** they see all non-deleted branches for their organization with name, code, contact fields, and active status.
2. **Given** valid branch details, **When** the user creates a branch, **Then** the branch is stored under the organization, appears in the list, and is available for staff assignment and branch switching when active.
3. **Given** an existing branch, **When** the user edits name, code, address, phone, or maps link, **Then** updates persist and are reflected in branch lists and the branch switcher when active.
4. **Given** an active branch with no blocking dependencies defined in this feature, **When** the user deactivates it, **Then** `is_active` becomes false, the branch is hidden from normal pickers and new assignment defaults, and historical records remain associated.
5. **Given** a deactivated branch, **When** the user reactivates it, **Then** it becomes available again in lists, assignments, and the branch switcher subject to the user’s own branch assignments.
6. **Given** a user without branch-management permission, **When** they attempt create, edit, or deactivate, **Then** the action is blocked with permission-denied messaging.
7. **Given** only one active branch remains in the organization, **When** the user attempts to deactivate it, **Then** deactivation is blocked with a clear message and an offered action to edit that branch’s details instead.

---

### User Story 3 - Manage Staff and Branch Assignments (Priority: P1)

As a clinic owner or administrator, I can list, create, edit, deactivate, and reactivate staff accounts, assign them to one or more branches with a primary branch, and enforce owner-creation rules so the clinic roster matches real staffing.

**Why this priority**: Staff and assignments drive authentication claims, branch scope, and permission checks for every later module.

**Independent Test**: Can be fully tested by creating a receptionist assigned to two branches with a primary, signing in as that user, deactivating the account, confirming sign-in denial, reactivating, and confirming access returns.

**Acceptance Scenarios**:

1. **Given** a user with staff-management permission, **When** they open staff management, **Then** they see staff in their organization with name, role, active status, and assigned branches.
2. **Given** valid staff details and at least one active branch assignment, **When** the user creates a staff account, **Then** the account can authenticate with the assigned role and branch scope consistent with V1-1 provisioning rules including owner-creation restrictions.
3. **Given** an existing staff member, **When** the user updates display name, phone, role, or branch assignments, **Then** changes persist and the affected user’s next session refresh or login reflects updated claims where applicable.
4. **Given** a staff member, **When** the user sets exactly one assignment as primary among multiple branches, **Then** login and branch switcher default to that primary when the user has not manually selected another assigned branch.
5. **Given** an active staff member, **When** the user deactivates them, **Then** the staff member cannot establish a new authenticated session and existing sessions fail closed on refresh according to inactive-staff rules.
6. **Given** a deactivated staff member, **When** the user reactivates them, **Then** they may sign in again with prior role and assignments unless those were changed during deactivation.
7. **Given** only the bootstrap administrator exists as owner creator, **When** an administrator attempts to create an owner account while any owner already exists, **Then** the action is blocked per V1-1 owner-creation rules.
8. **Given** a user without staff-management permission, **When** they attempt staff create, edit, or deactivate, **Then** the action is blocked.

---

### User Story 4 - Switch Active Branch in the Main Shell (Priority: P1)

As a staff member assigned to multiple branches, I can switch my active branch from the status bar or sidebar branch switcher so branch-scoped work and permissions use the location I am serving now.

**Why this priority**: Multi-branch clinics require frequent context changes; the V1-1 placeholder selector is insufficient for daily operations.

**Independent Test**: Can be fully tested by signing in as a user with two active branch assignments, switching branch in the main shell, and confirming branch-scoped authorization and displayed context update without re-login.

**Acceptance Scenarios**:

1. **Given** a signed-in user with multiple active branch assignments, **When** they open the branch switcher, **Then** only their assigned active branches are listed.
2. **Given** multiple assignments, **When** the user selects a different branch, **Then** active branch context updates for the session without requiring re-login and branch-scoped UI respects the new selection.
3. **Given** a signed-in user with a single assignment, **When** they view the branch switcher, **Then** the current branch is shown and no misleading empty state appears.
4. **Given** a signed-in user with no branch assignments, **When** they view the shell, **Then** the branch switcher is unavailable or disabled with the same blocked-state guidance established in V1-1.
5. **Given** a signed-in user whose assignments are only to deactivated branches, **When** they complete sign-in, **Then** they land in the blocked shell with no active branch and administrator-contact guidance, consistent with the no-assignment state.

---

### User Story 5 - Manage Role Permissions (Priority: P2)

As a clinic owner, I can view and edit which permissions each staff role is granted so the clinic can tune access before operational modules go live, within the product’s predefined permission catalog.

**Why this priority**: Permission matrix editing is security-sensitive and follows roster and branch setup; it is still required for V1-2 completeness but can ship after core CRUD if phased.

**Independent Test**: Can be fully tested by signing in as owner, toggling a grant for a non-owner role, signing in as a user of that role, and confirming UI and protected actions reflect the change after permission cache refresh.

**Acceptance Scenarios**:

1. **Given** a signed-in owner, **When** they open role permissions, **Then** they see a matrix of roles versus permission keys with current grant state.
2. **Given** a signed-in owner, **When** they change a grant for a role, **Then** the change persists, is auditable, and affects permission resolution on the next login or auth-context reload for users of that role (not mid-session without reload).
3. **Given** a signed-in administrator, **When** they open role permissions, **Then** they can view grants but cannot save changes.
4. **Given** a signed-in non-owner without manage permission, **When** they attempt to open role permissions, **Then** access is denied.
5. **Given** an owner removes a grant required for an action, **When** a user of that role attempts the action after their next login or auth-context reload, **Then** the action is blocked at UI and server layers.

---

### User Story 6 - Retire V1-1 Minimal Administration Paths (Priority: P2)

As a clinic that completed V1-1 bootstrap, I use the full settings and management screens instead of minimal setup and placeholder-shell branch selection, without losing data created during bootstrap.

**Why this priority**: Avoids duplicate or conflicting admin UX and completes the transition from bootstrap to steady-state operations.

**Independent Test**: Can be fully tested on a tenant created via V1-1 bootstrap: confirm organization, branches, and staff appear in new management lists, branch switcher works in the main shell, and bootstrap-only screens are no longer the primary path when setup is complete.

**Acceptance Scenarios**:

1. **Given** an organization and branches created during V1-1 bootstrap, **When** an owner opens organization and branch management, **Then** existing records are visible and editable through the new screens.
2. **Given** staff created via V1-1 minimal provisioning, **When** an administrator opens staff management, **Then** those accounts appear in the staff list with correct assignments and status.
3. **Given** setup is complete, **When** a multi-branch user works in the main shell, **Then** they use the status bar or sidebar branch switcher rather than the placeholder-shell selector as the primary branch-change control.

---

### Edge Cases

- Organization save with invalid timezone or currency must fail with field-level guidance without partial updates.
- Branch code uniqueness within the organization should be enforced when code is provided; duplicate codes are rejected.
- Deactivating the last active branch in the organization is hard-blocked; the user sees a clear message and may open edit for that branch to update its details instead. At least one active branch must always remain.
- Deactivating a branch must not remove historical assignment rows; staff already assigned retain assignment records but inactive branches must not appear in JWT branch claims, branch switcher, or new primary assignment unless reactivated.
- Staff whose only assignments are to deactivated branches sign in successfully but land in the V1-1 blocked shell (no active branch, no branch-scoped access, administrator-contact message).
- Staff cannot be saved without at least one active branch assignment when the role requires branch-scoped access (all roles except bootstrap/setup edge cases).
- Removing the primary flag from all assignments must auto-promote another assignment or block save with clear guidance.
- Bootstrap administrator flows remain available only while setup is incomplete; once organization and at least one active branch exist, steady-state management screens are authoritative.
- Permission matrix edits must not grant permissions to roles outside the five defined staff roles.
- Permission grant changes do not alter a signed-in user’s cached permissions until next login or auth-context reload; server-side checks on RPC calls MUST use current database grants regardless of stale client cache.
- AI services are not part of this feature; AI unavailability must not block organization, branch, staff, or permission management.
- Backend unavailability during save must fail without optimistic UI that implies success; lists show last known good data with connectivity messaging.
- Cross-organization access attempts in verification scenarios must remain blocked for all tables touched by this feature.
- Soft-deleted organization, branch, or staff rows must not appear in normal management lists.
- V1-2 management UI provides deactivate/reactivate only; administrators do not soft-delete branches or staff from these screens (`is_deleted` remains backend-only).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an organization settings experience for signed-in **owner** and **administrator** roles to view and update organization name, logo reference, currency code, timezone, and organization-wide settings payload fields defined in the existing schema; other roles are denied without introducing a new `settings.manage_organization` permission key.
- **FR-002**: The system MUST prevent creation of a second organization on a single installation; only update of the existing organization is allowed.
- **FR-003**: The system MUST provide branch management: list, create, edit, deactivate, and reactivate branches within the signed-in user’s organization.
- **FR-003a**: The system MUST hard-block deactivation of the last active branch in the organization and MUST offer navigation to edit that branch’s details in the same flow.
- **FR-004**: The system MUST enforce `settings.manage_branches` (or equivalent server-side check) for branch create, edit, and deactivate operations.
- **FR-005**: The system MUST provide staff management: list, create, edit, deactivate, and reactivate staff within the organization, including branch assignments and primary branch designation.
- **FR-006**: The system MUST enforce `settings.manage_staff` for staff management mutations and preserve V1-1 owner-creation rules (only bootstrap path for first owner; thereafter only owners create owner accounts).
- **FR-007**: The system MUST retain administrator-mediated password reset from V1-1 and expose it from staff management (owners and administrators); self-service password reset remains out of scope.
- **FR-008**: The system MUST provide a branch switcher in the main application shell (status bar or sidebar) listing only the signed-in user’s active assigned branches and updating session active-branch context without re-login.
- **FR-008a**: Custom claims and branch switcher population MUST include only active branches (`is_active = true`) from the user’s assignments; users with zero active assigned branches MUST receive the blocked-shell experience after sign-in.
- **FR-009**: The system MUST replace the V1-1 placeholder-shell branch selector as the primary branch-change control for users with completed setup.
- **FR-010**: The system MUST provide role-permission matrix UI: owners can view and edit grants; administrators can view only; other roles are denied.
- **FR-011**: The system MUST persist permission matrix changes to the existing `roles_permissions` catalog; client permission cache updates on next login or auth-context reload (app resume, post-matrix-save refresh, or explicit refresh if provided), while server-side RPC and policy checks MUST enforce current grants immediately.
- **FR-012**: The system MUST implement organization, branch, and staff mutation operations through secured server-side functions with permission and organization-scope validation, not direct table writes from the client for protected mutations.
- **FR-013**: The system MUST record sensitive mutations (organization update, branch create/update/deactivate, staff create/update/deactivate, permission grant changes) in the audit log with actor, action, target, and change payload.
- **FR-014**: The system MUST apply `is_active` deactivate/reactivate in management UI; normal lists exclude soft-deleted rows but V1-2 MUST NOT expose soft-delete actions for branches or staff (soft delete remains backend-only).
- **FR-015**: The system MUST enforce organization and branch isolation at the data access layer for all operations in this feature.
- **FR-016**: The system MUST include backend verification utilities that validate CRUD flows and row-level isolation for organization, branch, staff, and permission management operations introduced or extended here.
- **FR-017**: The system MUST derive requirements from the architecture documents listed under Required Architecture Docs and treat shared common specs as external references until authored.
- **FR-018**: The system MUST NOT deliver patient, appointment, visit, billing, or AI workflows as part of this feature.
- **FR-018a**: The system MUST NOT provide soft-delete controls in V1-2 organization, branch, or staff management screens.
- **FR-019**: The system MUST NOT introduce subscription enforcement UI or block login based on subscription state (deferred from V1-1).
- **FR-020**: The system MUST NOT change the single-tenant-per-installation model or multi-organization SaaS behavior.

### Non-Functional Requirements

- **NFR-001**: Management screens must use plain language understandable by non-technical clinic administrators.
- **NFR-002**: List views for branches and staff must remain usable with at least 50 rows without unacceptable delay under normal local clinic network conditions.
- **NFR-003**: Permission and branch changes must follow defense in depth: client gating, server function validation, and data-layer isolation.
- **NFR-004**: Save failures due to connectivity or validation errors must not leave the user believing data was saved.
- **NFR-005**: Branch switcher interaction must complete perceived context change within 2 seconds under normal local conditions.

### Required Architecture Docs

- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Multi-Tenancy Model`, `Schema Conventions`, `Core Schema Domains` (Organization & Tenancy, Staff & Auth, System)
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`, `Soft Delete`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

### External Spec Dependencies

- `specs/common/organizations.spec.md` is referenced by the roadmap but is not yet present. This specification captures organization management expectations for V1-2 until that shared spec is authored.
- `specs/common/branches.spec.md` is referenced by the roadmap but is not yet present. This specification captures branch management expectations for V1-2 until that shared spec is authored.
- `specs/common/staff.spec.md` is referenced by the roadmap but is not yet present. This specification captures staff management expectations for V1-2 until that shared spec is authored.
- `specs/002-auth-rbac` is a hard prerequisite: schema, RLS, bootstrap RPCs, session context, and minimal provisioning must already be delivered.

### Data Model

This feature uses existing tables from V1-1 without new core tenancy tables unless planning discovers a required migration gap.

- **Organization**: Tenant root; editable fields include name, logo URL, currency code, timezone, subscription metadata fields (display only in V1-2), and `settings_json` for extensible org-wide configuration.
- **Branch**: Location under the organization; fields include name, code, address, phone, maps URL, `is_active`, plus standard audit and soft-delete columns.
- **Staff Member**: Clinic worker linked to platform identity; fields include full name, role, phone, `is_active`, bootstrap flag; organization scope via branch assignments.
- **Staff Branch Assignment**: Links staff to branches with `is_primary` for default session branch.
- **Role Permission**: Global permission catalog per `staff_role` with `permission_key` and `is_granted`; edited by owners through this feature’s matrix UI.
- **Audit Log**: Records sensitive configuration changes performed through this feature’s operations.

No additional organization or branch tables are required for V1-2 scope unless implementation planning identifies a gap (for example branch-level settings via `app_settings`).

### RPC Functions

Operations extend or supersede V1-1 bootstrap RPCs with steady-state management functions (exact names finalized in planning):

- **Update organization**: Allow only `owner` or `administrator` role; update allowed organization fields for `jwt.organization_id`; reject second-org creation; audit.
- **List branches / Get branch**: Organization-scoped read for authorized roles; respect soft delete and active filters per UI state.
- **Create branch** (steady-state): Create branch under organization for users with branch-management permission; distinct from bootstrap path when setup is complete; audit.
- **Update branch**: Edit branch fields; enforce organization scope and branch-management permission; audit.
- **Deactivate / reactivate branch**: Toggle `is_active`; hard-reject deactivation when the branch is the sole active branch in the organization; audit.
- **List staff / Get staff member**: Organization-scoped via assignments; include branch assignment summary.
- **Create staff account** (steady-state): Extend V1-1 rules with full management form; transactional auth user, staff row, assignments; audit.
- **Update staff member**: Update profile, role, assignments, primary branch; enforce owner-creation rules on role changes; audit.
- **Deactivate / reactivate staff**: Toggle `is_active`; audit.
- **Reset staff password**: Reuse V1-1 administrator reset behavior from staff management context.
- **List role permissions**: Return matrix for all five roles and known permission keys.
- **Update role permission** (owner only): Toggle `is_granted` for a role/key pair; audit; reject non-owner callers.

Bootstrap RPCs (`bootstrap_create_organization`, `bootstrap_create_branch`) remain for incomplete setup; management RPCs are used when setup is complete.

### RLS Policies

Existing policies on `organizations`, `branches`, `staff_members`, `staff_branch_assignments`, and `roles_permissions` MUST continue to enforce:

- Authenticated access only.
- Organization isolation via session organization context.
- Branch-scoped updates where policies require assignment membership.
- Soft-deleted rows excluded from normal access.
- No cross-tenant reads or writes in verification scenarios.

New or adjusted policies required for steady-state RPCs and permission-matrix updates MUST be defined in implementation planning and verified by backend utilities.

### API Contracts

- Read and update organization profile for the current tenant.
- List, create, update, deactivate, and reactivate branches.
- List, create, update, deactivate, and reactivate staff; manage branch assignments and primary branch.
- Reset staff password (owner/administrator) with visible assigned password at reset time only.
- List and update role-permission grants (owner write; administrator read-only).
- Read staff branch assignments for branch switcher population.
- Client updates active branch context locally and via session integration without full re-login.

Patient, appointment, billing, and AI APIs remain out of scope.

### UI States

- **Organization Settings - Loading / Loaded / Error / Permission Denied / Save Submitting / Save Success**
- **Branch List - Empty / Loading / Loaded / Error / Permission Denied**
- **Branch Form (Create/Edit) - Initial / Validation Error / Submitting / Success / Permission Denied**
- **Branch Deactivate Confirm - Active confirmation for multi-branch deactivate; Last-active-branch blocked with message and shortcut to edit that branch**
- **Staff List - Empty / Loading / Loaded / Error / Permission Denied**
- **Staff Form (Create/Edit) - Initial / Validation Error / Submitting / Success / Permission Denied / Owner-creation blocked**
- **Staff Deactivate Confirm - With impact messaging on active sessions**
- **Staff Password Reset - From staff detail; shows assigned password to administrator performing reset**
- **Role Permissions Matrix - View-only (administrator) / Editable (owner) / Permission Denied**
- **Branch Switcher - Single branch display / Multi-branch dropdown / Disabled (no assignments) / Switching**
- **Setup Incomplete Redirect - When organization or no active branch exists, guide to bootstrap or management path per setup state**

### Validation Rules

- Organization name is required and non-empty after trim.
- Currency code must be a valid ISO 4217 code when provided.
- Timezone must be a valid IANA timezone identifier when provided.
- Branch name is required; code is optional but must be unique within the organization when provided.
- Staff full name and role are required; at least one active branch assignment is required for roles that use branch-scoped access.
- Exactly one primary assignment when multiple branches are assigned.
- Username rules from V1-1 apply to new staff accounts (length and charset).
- Owner role assignment rules from V1-1 apply on create and role change.
- Permission matrix edits may only target defined `staff_role` values and known `permission_key` values from the product catalog.
- Branch switcher selection must be limited to active branches assigned to the signed-in user.
- Auth claims resolution must exclude deactivated branches from `branch_ids`; staff with no remaining active assignments receive empty branch scope and blocked-shell treatment at sign-in.

### AI Hooks

This feature introduces no AI-assisted workflow. Permission keys related to future AI access may be edited in the matrix but AI surfaces remain inactive until later roadmap phases.

### Audit Requirements

- Organization profile updates MUST write audit log entries with before/after payload where practical.
- Branch create, update, deactivate, and reactivate MUST be audited.
- Staff create, update, deactivate, reactivate, and role or assignment changes MUST be audited.
- Permission grant changes MUST be audited with role, permission key, and old/new grant state.
- Reads (list/get) are not required to audit individually unless architecture mandates access logging later.

### Acceptance Criteria

1. Owner can update organization settings and see changes after reload.
2. Attempt to create a second organization is rejected.
3. Owner or administrator with permission can create, edit, and deactivate/reactivate branches; deactivated branches do not appear in active pickers.
4. Deactivating the sole active branch is hard-blocked; the user can open edit for that branch from the blocked-deactivate flow.
5. Owner or administrator with permission can create, edit, and deactivate/reactivate staff with branch assignments; deactivated staff cannot start new sessions.
6. Owner-creation rules from V1-1 are enforced in staff management create and role change flows.
7. Multi-branch staff can switch active branch from the main shell branch switcher without re-login.
8. Users without branch assignments or with assignments only to deactivated branches see blocked branch-switcher state consistent with V1-1.
9. Owner can change a permission grant and a user of the affected role sees updated deny/allow behavior after next login or auth-context reload; server denies the action immediately if attempted via RPC before client cache reloads.
10. Administrator can view but not save permission matrix changes.
11. Backend verification utilities demonstrate blocked cross-organization access for management operations.
12. V1-1 bootstrap-created organization, branches, and staff appear in new management screens.
13. No patient, appointment, billing, or AI workflow is required to pass this feature.

### Test Cases

1. Update organization name and timezone as owner or administrator; confirm persistence and audit record; confirm doctor role is denied organization settings save.
2. Attempt second organization creation; confirm rejection.
3. Create branch, edit code, deactivate, confirm hidden from switcher, reactivate, confirm visible.
4. Attempt to deactivate the only active branch; confirm hard block, message, and offered edit path; update branch via edit and confirm save succeeds.
5. Create staff with two branches and primary; sign in as staff; confirm default primary and switcher lists both.
6. Deactivate staff; confirm new sign-in denied; reactivate; confirm sign-in succeeds.
7. Administrator attempts owner creation when owner exists; confirm denial.
8. Owner toggles `settings.manage_branches` off for administrator role; administrator after next login or auth-context reload confirms branch management blocked in UI; RPC branch create denied immediately.
9. Owner edits permission matrix; doctor after auth-context reload confirms UI alignment; doctor RPC before reload still denied if grant removed server-side.
10. Administrator opens matrix; save control absent or save rejected.
11. Run backend verification utilities for CRUD and cross-org isolation.
12. Import tenant from V1-1 bootstrap seed path; open management screens; confirm records visible.
13. Deactivate the only branch assigned to a staff member; sign in as that staff member; confirm blocked shell and no branch switcher entries.

### Implementation Constraints

- MUST build on completed `specs/002-auth-rbac` schema, RLS, session context, and bootstrap flows without breaking existing authentication behavior.
- MUST NOT add a second organization per installation.
- Domain validation and authorization source of truth for mutations MUST live in database functions and policies—not solely in client logic.
- Cloud-only deployment enhancements are out of scope unless already supported by the local deployment path from V1-0.
- Minimal V1-1 screens may remain as fallback only until setup is complete; steady-state UX uses this feature’s management module.
- No AI dependency for any flow in this feature.
- Do not modify patient, appointment, visit, or billing schemas in this feature.
- Do not add soft-delete UI for branches or staff; use `is_active` deactivate/reactivate only.

### Key Entities *(include if feature involves data)*

- **Organization**: Clinic tenant root and editable business profile.
- **Branch**: Operational location; active flag controls visibility in pickers.
- **Staff Member**: Authenticated clinic worker with role and lifecycle state.
- **Staff Branch Assignment**: Branch access and primary default for session context.
- **Role Permission**: Capability grant for a staff role in the global catalog.
- **Active Branch Context**: Client session field selecting which assigned branch scopes the current work.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch clinics that need self-service administration without IT staff. Enterprise multi-tenant SaaS, hospital identity federation, and patient portals are out of scope.
- **Layer Placement**: The desktop client owns organization, branch, staff, and permission management screens, the branch switcher, validation UX, and permission-aware control visibility. The backend platform owns secured mutation functions, read APIs subject to row-level policies, and audit writes. The database layer owns existing tenancy schema, isolation policies, permission catalog storage, and verification utilities. The AI layer remains absent.
- **Data Integrity & Security**: Mutations use audit and soft-delete conventions; row-level policies preserve organization and branch isolation; permission matrix edits are owner-only writes; staff and branch deactivation fail closed for new access; defense in depth applies across UI, RPC, and policies.
- **Failure Handling**: Save and list failures surface clear errors without false success; connectivity loss during management shows degraded list states; AI unavailability does not affect administration; subscription state does not block administration in V1-2.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 95% of test runs, authorized users complete organization settings update and see confirmation within 10 seconds under normal local clinic network conditions.
- **SC-002**: In 100% of test scenarios, second-organization creation is rejected.
- **SC-003**: In 100% of branch management test scenarios, created branches appear in list and switcher within 10 seconds of successful save.
- **SC-004**: In 100% of staff lifecycle test scenarios, deactivated staff cannot start a new session and reactivated staff can within the same test suite.
- **SC-005**: In 100% of multi-branch user scenarios, branch switcher changes active context without re-login and within 2 seconds perceived time.
- **SC-006**: In 100% of permission-matrix test scenarios, owner grant changes are reflected for the target role after next login or auth-context reload, and server-side denial applies immediately for removed grants.
- **SC-007**: In 100% of backend verification scenarios, cross-organization management access is blocked.
- **SC-008**: In 100% of V1-1 bootstrap migration scenarios, existing organization, branch, and staff records are visible in V1-2 management screens without re-entry.

## Assumptions

- `specs/002-auth-rbac` is implemented and deployed: tables, RLS, `get_custom_claims`, bootstrap RPCs, session management, and minimal provisioning exist.
- Each installation continues to support exactly one organization.
- Permission keys are drawn from the architecture catalog; this feature edits grants per role, not arbitrary new permission key strings from the UI.
- `roles_permissions` remains a global catalog per installation (not per-organization rows) consistent with V1-1 seed model.
- Branch and staff lifecycle in V1-2 management UI uses `is_active` deactivate/reactivate only; soft delete (`is_deleted`) is not exposed in these screens.
- Password reset behavior reuses V1-1 administrator-mediated reset; viewing passwords applies only to values the administrator sets at create or reset time.
- Subscription fields on organization may display but enforcement remains deferred.
- AI remains optional and non-blocking for all administration flows.
- Shared `specs/common/organizations.spec.md`, `branches.spec.md`, and `staff.spec.md` will be authored later; this feature spec is authoritative for V1-2 until those exist.
