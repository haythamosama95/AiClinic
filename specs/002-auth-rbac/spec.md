# Feature Specification: Auth and RBAC

**Feature Branch**: `specs/002-auth-rbac`

**Created**: 2026-05-16

**Status**: Draft

**Input**: User description: "Read V1-1 from @docs/architecture/12-roadmap-phases.md and according to the best practices of speckit, create the second spec"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

This feature delivers secure sign-in and permission enforcement for clinic staff so every later operational module can assume a known identity, organization, branch scope, and role. Without authentication and role-based access control, patient, appointment, and billing workflows cannot safely run in a multi-branch clinic environment.

The primary beneficiaries are clinic staff who need to sign in with their work credentials and work only within their assigned branches and permissions, and clinic owners or administrators who need tenant isolation and a consistent permission model before staff and branch management screens are delivered in the next feature.

This feature establishes the data foundation for organizations, branches, staff, and permissions, plus audit and settings infrastructure. It also delivers first-time clinic bootstrap via a shipped default administrator account, minimal organization and branch setup, and minimal staff account creation, while deferring full organization, branch, staff, and permission-matrix management user interfaces to V1-2.

## Clarifications

### Session 2026-05-16

- Q: After successful sign-in, what should staff see before V1-2 operational modules? → A: A minimal authenticated placeholder shell (header with user/branch context, logout, and a placeholder home area until modules ship).
- Q: How long should a staff session remain valid without re-entering credentials (including after closing and reopening the app)? → A: Closing and fully exiting the application ends the session; reopening the app requires sign-in again. In-session refresh may continue only while the app remains running.
- Q: If a staff member has valid credentials but no branch assignments, what should happen at sign-in? → A: Allow sign-in but show a blocked state in the placeholder shell with no branch-scoped access and a clear message to contact an administrator.
- Q: When a signed-in user lacks permission for an action or route, how should the client respond in V1-1? → A: Hide or disable unauthorized UI by default, and show a brief permission-denied message when the user attempts a blocked route or action.
- Q: For staff assigned to multiple branches without the V1-2 branch switcher, how should active branch be chosen in V1-1? → A: Auto-select primary branch (or deterministic default) at login; provide a minimal active-branch selector in the placeholder shell to change branch during the session.
- Q: Does an expired subscription block login when `subscription_cache` is introduced in V1-1? → A: Create and seed the table in V1-1, but do not block login on expiry; enforcement belongs to a later billing/subscription feature.
- Q: Should shared clinic workstations auto-logout after inactivity? → A: Yes — automatic sign-out after 15 minutes of user inactivity while the app is running.
- Q: How are initial and additional staff accounts provisioned in V1-1? → A: The application ships with a default administrator account; that administrator (and later owners/administrators) can create staff accounts for other roles. Forgot-password self-service is not offered — users are directed to contact an administrator.
- Q: How are forgotten passwords handled? → A: The login experience shows a message to contact an administrator. Users with the owner or administrator role can reset another staff member's password and can view the password value only when they set or reset it (not recover an unknown prior secret).
- Q: On a fresh installation, how do the first organization and branch exist before staff are created? → A: No organization or branch is pre-seeded; the default administrator must create the organization and at least one branch through minimal V1-1 setup screens before creating staff accounts.
- Q: Must the default administrator change the shipped password on first sign-in? → A: No — show a prominent warning on first sign-in but allow proceeding with the shipped password until they change it voluntarily.
- Q: How many organizations can be created on a single clinic installation during V1-1 bootstrap? → A: Exactly one organization per installation; bootstrap creates it once and cannot add another in V1-1.
- Q: Who may create staff accounts with the owner role during V1-1 minimal provisioning? → A: Only the default bootstrap administrator can create the first owner; thereafter only existing owners can create additional owner accounts.
- Q: What resets the 15-minute idle sign-out timer? → A: Keyboard and pointer (mouse/touchpad) input anywhere in the application window.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sign In Securely (Priority: P1)

As a clinic staff member, I can sign in with my work email and password so that I can access the application with my identity, organization context, and permissions applied.

**Why this priority**: No protected clinic workflow can run until staff can authenticate and receive a scoped session.

**Independent Test**: Can be fully tested by signing in with a valid seeded staff account and confirming the session is established with organization, branch, role, and permission context available to the client.

**Acceptance Scenarios**:

1. **Given** a staff account exists and is active, **When** the user enters valid email and password on the login screen, **Then** the user is authenticated, leaves the unauthenticated entry experience, and lands on the minimal authenticated placeholder shell.
2. **Given** invalid credentials are submitted, **When** sign-in is attempted, **Then** the user sees a clear error and remains unauthenticated without exposing whether the email exists.
3. **Given** a staff account is inactive or not linked to the auth identity, **When** valid credentials are used, **Then** sign-in is denied with an actionable message and no protected session is created.

---

### User Story 2 - Stay Signed In During a Shift (Priority: P1)

As a clinic staff member, my session remains valid and refreshes automatically during normal use so I am not interrupted by avoidable re-authentication while working.

**Why this priority**: Frequent unexpected logouts during clinic hours disrupt operations and erode trust in the system.

**Independent Test**: Can be fully tested by signing in, simulating elapsed session time within normal refresh windows, and confirming the user remains authenticated without manual re-entry until logout or session expiry policy applies.

**Acceptance Scenarios**:

1. **Given** an authenticated session, **When** the application is used within the supported session lifetime, **Then** the session refreshes without requiring the user to re-enter credentials.
2. **Given** a previously authenticated user who fully closed and reopened the application, **When** the application starts, **Then** the prior session is ended and the user must sign in again.
3. **Given** a session that can no longer be refreshed while the app is running, **When** the user attempts a protected action, **Then** the user is returned to the login experience with a clear message.
4. **Given** an authenticated session with no keyboard or pointer input in the application window, **When** 15 minutes elapse while the application remains open, **Then** the session ends automatically and the user is returned to the login experience with a clear message.

---

### User Story 3 - Access Only What My Role Allows (Priority: P2)

As a clinic staff member, I can only see and attempt actions my role and branch assignments permit, so clinic data stays isolated by organization and branch and sensitive operations are blocked before they reach protected workflows.

**Why this priority**: Tenant and branch isolation are core safety requirements for multi-branch clinics and must exist before domain modules are added.

**Independent Test**: Can be fully tested by signing in as users with different roles and branch assignments and verifying permitted actions succeed while denied actions are blocked in the client and at the data access layer.

**Acceptance Scenarios**:

1. **Given** a signed-in user with a specific role, **When** the application loads post-login context, **Then** the user's cached permissions reflect the default role-permission mappings for that role.
2. **Given** a signed-in user assigned to one or more branches, **When** post-login context is established, **Then** an active branch is auto-selected from primary or default rules and branch-scoped access uses only branches assigned to that user.
3. **Given** a signed-in user with multiple branch assignments, **When** they choose a different assigned branch in the minimal placeholder-shell selector, **Then** the active branch updates for the session and branch-scoped authorization uses the newly selected branch.
4. **Given** a signed-in user without permission for an action, **When** they attempt that action, **Then** the action is blocked, a brief permission-denied message is shown, and no cross-tenant or cross-branch data is exposed.

---

### User Story 4 - Sign Out Safely (Priority: P2)

As a clinic staff member, I can sign out so that the next person using the workstation cannot continue my session.

**Why this priority**: Shared workstations in clinics require explicit session termination.

**Independent Test**: Can be fully tested by signing in, signing out, and confirming protected routes and cached identity context are cleared.

**Acceptance Scenarios**:

1. **Given** an authenticated user, **When** they choose logout, **Then** the session ends, cached identity and permission context are cleared, and the user returns to the login experience.
2. **Given** a user who logged out, **When** they attempt to open a protected area, **Then** they are redirected to login.

---

### User Story 5 - Bootstrap the Clinic Tenant (Priority: P1)

As the default administrator on a fresh installation, I can create my clinic organization and at least one branch through minimal setup screens so I can assign staff to a branch before operational modules exist.

**Why this priority**: No organization or branch is pre-seeded; without this setup path, staff provisioning and branch-scoped authorization cannot be configured.

**Independent Test**: Can be fully tested by signing in as the default administrator on a fresh install, creating an organization and branch, and confirming both persist and appear in post-login context.

**Acceptance Scenarios**:

1. **Given** a fresh installation with no organization or branch records, **When** the default administrator signs in for the first time, **Then** they see a prominent warning to change the shipped password and may proceed to organization and branch setup without forced password change.
2. **Given** a fresh installation with no organization or branch records, **When** the default administrator continues past first sign-in, **Then** they are guided to minimal organization and branch setup before staff creation is offered.
3. **Given** a signed-in default administrator, **When** they submit valid organization and branch details, **Then** the organization and branch are created and the administrator can proceed to staff provisioning.
4. **Given** a fresh installation, **When** the administrator attempts to create staff before organization and branch exist, **Then** the action is blocked with guidance to complete setup first.

---

### User Story 5b - Create Staff Accounts (Priority: P1)

As a clinic owner or administrator, I can create staff accounts for the other roles after organization and branch setup so the clinic can operate before full staff-management screens exist.

**Why this priority**: Without staff provisioning, no other roles can sign in and the auth feature cannot be validated end-to-end in a real clinic setup.

**Independent Test**: Can be fully tested by completing organization/branch setup, creating a staff account for another role, signing out, and signing in as the new account.

**Acceptance Scenarios**:

1. **Given** organization and at least one branch exist, **When** a signed-in owner or administrator creates a staff account with email, role, branch assignment, and initial password, **Then** the new account can sign in with the assigned role and permissions.
2. **Given** no owner account exists yet, **When** the default bootstrap administrator creates a staff account with the owner role, **Then** the owner account is created successfully.
3. **Given** at least one owner account already exists, **When** a signed-in administrator (non-owner) attempts to create an owner account, **Then** the action is blocked with a permission-denied outcome.
4. **Given** at least one owner account exists, **When** a signed-in owner creates another owner account, **Then** the new owner account is created successfully.
5. **Given** a signed-in user who is not an owner or administrator, **When** they attempt to create another staff account, **Then** the action is blocked with a permission-denied outcome.

---

### User Story 6 - Recover Access When Password Is Forgotten (Priority: P2)

As a staff member who forgot my password, I receive clear guidance to contact an administrator rather than using a self-service reset, and administrators can restore my access.

**Why this priority**: Small clinics often lack IT staff; admin-mediated recovery matches local deployment and shared-workstation realities.

**Independent Test**: Can be fully tested by triggering the forgot-password path on the login screen and verifying messaging; then signing in as an administrator to reset the affected account's password.

**Acceptance Scenarios**:

1. **Given** the login screen, **When** a user indicates they forgot their password, **Then** they see a plain-language message to contact their clinic administrator (no self-service email reset in V1-1).
2. **Given** a signed-in owner or administrator, **When** they reset another staff member's password, **Then** the staff member can sign in with the new password and the administrator can view the password value they just set.
3. **Given** a staff member whose password was reset by an administrator, **When** they sign in with the new password, **Then** authentication succeeds with unchanged role and branch assignments.

---

### User Story 7 - Block Unauthenticated Access (Priority: P1)

As a clinic operator, the application prevents access to protected areas until a valid authenticated session exists, building on the V1-0 route-guard foundation.

**Why this priority**: The scaffolding entry experience must transition safely into an authenticated application without accidental exposure of future protected modules.

**Independent Test**: Can be fully tested by launching the app without a session, attempting protected navigation, and confirming redirection to login; then signing in and confirming protected navigation is allowed.

**Acceptance Scenarios**:

1. **Given** no authenticated session, **When** the user attempts to access a protected route, **Then** they are redirected to the login experience.
2. **Given** a valid authenticated session with resolved staff context, **When** the user navigates to permitted protected areas, **Then** access is allowed according to role and branch scope.

---

### Edge Cases

- Invalid, expired, or revoked sessions must clear client identity context and return the user to login without partial protected state.
- Fully closing and reopening the application must end the authenticated session and clear cached identity, branch, and permission context before the next launch.
- Staff with multiple branch assignments receive a primary branch (or deterministic default) at login and may change the active branch only via the minimal placeholder-shell selector; the full branch-switcher component remains deferred to V1-2.
- Staff with no branch assignments may sign in but MUST land in a blocked placeholder-shell state: no active branch, no branch-scoped protected access, and a clear administrator-contact message—never empty or cross-tenant data.
- Authentication or identity services unavailable at login must show a clear failure state and must not create a partial authenticated session.
- Permission cache stale after backend role changes must be refreshed on next login or explicit session refresh without silently retaining outdated privileges beyond the session boundary.
- AI services are not part of this feature; unavailability of AI must not block login, logout, or session management.
- Incorrect password attempts must not leak account existence beyond generic failure messaging.
- Subscription cache records with expired `valid_until` must not block login in V1-1; subscription enforcement is deferred to a later feature.
- Subscription or license cache unavailability must not hard-lock login for this feature; degraded subscription validation follows the product's graceful-degradation rules without bypassing authentication or authorization.
- Fifteen minutes without keyboard or pointer input in the application window while the app remains open must trigger automatic sign-out on shared workstations; background token refresh alone does not count as activity.
- Default administrator credentials shipped with the product must be changeable at any time; first sign-in shows a prominent warning to change them, but setup and provisioning may proceed without forced password change in V1-1.
- Administrators cannot recover an unknown prior password from storage; they can only set a new password and view the value they assign at creation or reset time.
- Fresh installations have no pre-seeded organization or branch; staff creation is blocked until minimal organization and branch setup is completed.
- Each installation supports exactly one organization in V1-1; attempts to create a second organization are blocked.
- Only the default bootstrap administrator may create the first owner; administrators cannot create owner accounts once any owner exists.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide email-and-password authentication for clinic staff accounts linked to the platform identity store.
- **FR-002**: The system MUST issue an authenticated session that includes organization identifier, assigned branch identifiers, staff identifier, and role for use in authorization decisions.
- **FR-003**: The system MUST populate session authorization context from staff and branch assignment records at login through the documented custom-claims mechanism.
- **FR-004**: The system MUST end the authenticated session when the application is fully closed; reopening the application MUST require sign-in and MUST NOT restore a prior session.
- **FR-005**: The system MUST refresh authenticated sessions automatically during normal use while the application remains running, without requiring manual re-entry until refresh is no longer possible, the application is closed, or idle timeout applies.
- **FR-005a**: The system MUST automatically sign out the user after 15 consecutive minutes without keyboard or pointer input in the application window while the app remains open, clearing session and cached identity context.
- **FR-006**: The system MUST provide a login experience reachable from the V1-0 unauthenticated entry path and block protected routes until authentication succeeds.
- **FR-006a**: After successful sign-in, the system MUST navigate to a minimal authenticated placeholder shell that shows user identity, role, active branch, logout, and a non-operational home area until V1-2 modules are available.
- **FR-007**: The system MUST load staff profile information after successful login and establish active branch context when branch assignments exist.
- **FR-007a**: When a signed-in staff member has no branch assignments, the system MUST still complete authentication but MUST NOT grant branch-scoped access; the placeholder shell MUST show a blocked configuration state with administrator guidance.
- **FR-008**: The system MUST cache effective permissions for the signed-in user's role after login for client-side permission checks.
- **FR-009**: The system MUST enforce role-based permissions in the client before presenting or invoking protected actions by hiding or disabling unauthorized controls.
- **FR-009a**: When a user attempts a route or action they lack permission for, the system MUST show a brief, plain-language permission-denied message in addition to blocking the action.
- **FR-010**: The system MUST enforce organization and branch data isolation at the data access layer for all tables introduced in this feature.
- **FR-011**: The system MUST introduce core tenancy and staff tables required for authentication and authorization: organizations, branches, staff members, staff branch assignments, and role-permission mappings.
- **FR-012**: The system MUST apply shared schema conventions (identifiers, audit columns, soft delete, automatic update timestamps, audit user attribution) to all tables introduced in this feature.
- **FR-013**: The system MUST provide audit logging infrastructure and automatic audit-field maintenance for tables introduced in this feature.
- **FR-014**: The system MUST introduce and seed supporting tables for application settings and subscription validation cache as defined in architecture, without implementing subscription enforcement UI in this feature.
- **FR-014a**: The system MUST NOT block login based on expired subscription cache entries in V1-1; subscription enforcement is deferred to a later billing/subscription feature.
- **FR-021**: The system MUST ship with a default administrator account (email and password) suitable for first-time clinic bootstrap, documented for initial sign-in with a prominent first-sign-in warning to change the password; password change is recommended but not enforced in V1-1.
- **FR-022**: The system MUST allow the default administrator to create exactly one organization and at least one branch through minimal V1-1 setup screens on a fresh installation; no organization or branch may be pre-seeded, and additional organizations MUST NOT be creatable in V1-1.
- **FR-022a**: The system MUST block staff account creation until at least one organization and one branch exist.
- **FR-022b**: The system MUST allow signed-in owners and administrators to create staff accounts (email, role, branch assignment, initial password) through a minimal provisioning flow in V1-1 after organization and branch setup is complete.
- **FR-022c**: The system MUST allow only the default bootstrap administrator to create the first owner account; after an owner exists, only owners may create additional owner accounts, and administrators MUST NOT create owner accounts.
- **FR-023**: The system MUST provide a forgot-password path on the login experience that displays a message to contact the clinic administrator and MUST NOT provide self-service password reset in V1-1.
- **FR-024**: The system MUST allow signed-in owners and administrators to reset another staff member's password and view the password value they assign at account creation or reset time only.
- **FR-015**: The system MUST seed default permission mappings for all five staff roles: owner, administrator, doctor, receptionist, and lab staff.
- **FR-016**: The system MUST provide logout that terminates the session and clears cached identity, branch, and permission context.
- **FR-017**: The system MUST include backend verification utilities that validate authentication flow and row-level isolation for tables delivered in this feature.
- **FR-018**: The system MUST derive auth and RBAC decisions from the architecture documents referenced by V1-1 and treat shared auth and RBAC reference specs as external dependencies until those shared specs are authored.
- **FR-019**: The system MUST NOT deliver full organization settings, full branch management (list/edit/deactivate beyond initial create), full staff management (list/edit/deactivate), permission-matrix editing, or the full branch-switcher component (status bar/sidebar) in this feature; those belong to V1-2. Minimal initial organization and branch setup, staff account creation, and password reset by owners/administrators remain in scope per FR-022, FR-022b, and FR-024.
- **FR-019a**: For staff with multiple branch assignments, the system MUST auto-select the primary branch (or deterministic default) at login and MUST provide a minimal active-branch selector in the placeholder shell to change the active branch during the session.
- **FR-020**: The system MUST NOT introduce patient, appointment, billing, visit, or AI-dependent workflows as part of this feature.

### Non-Functional Requirements

- **NFR-001**: Login failure and permission-denied messages must be understandable by non-technical clinic staff without requiring log inspection.
- **NFR-002**: Authentication and permission enforcement must follow defense in depth: client permission checks, server-side validation on protected operations introduced later, and data-layer isolation policies.
- **NFR-003**: Session and permission handling must not expose one organization's data to users of another organization under any tested failure scenario.
- **NFR-004**: Degraded backend connectivity during login must fail closed: no protected session or partial permission context.
- **NFR-005**: Idle timeout and automatic sign-out must apply consistently across all authenticated roles on shared workstations.

### Required Architecture Docs

- `docs/architecture/04-backend.md`
- `docs/architecture/05-database.md` → `Multi-Tenancy Model`, `Schema Conventions`, `Core Schema Domains` (Organization & Tenancy, Staff & Auth, System)
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Authentication`, `Role-Based Access Control (RBAC)`, `Audit Trail`, `Security Principles`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

### External Spec Dependencies

- `specs/common/auth.spec.md` is referenced by the roadmap as a shared dependency but is not yet present. This specification captures minimum authentication expectations for V1-1 until the shared auth specification is authored.
- `specs/common/rbac.spec.md` is referenced by the roadmap as a shared dependency but is not yet present. This specification captures minimum RBAC expectations for V1-1 until the shared RBAC specification is authored.

### Data Model

This feature introduces the foundational tenancy, staff, permission, audit, and settings data required before operational modules.

- **Organization**: Tenant root for a clinic business; holds name, logo URL, currency code, timezone, subscription metadata, and organization-wide settings payload.
- **Branch**: A clinic location under an organization; the only table that directly holds organization reference; includes short branch code, contact fields, GPS/maps URL, and active status.
- **Staff Member**: A person working for the clinic; linked to platform identity; holds display name, role, contact, and active flag; organization context derived from branch assignments.
- **Staff Branch Assignment**: Many-to-many link between staff and branches, including which branch is primary for default session context.
- **Role Permission**: Mapping of role to permission keys with grant/deny state; used to resolve what each role may do.
- **Audit Log**: Append-only record of sensitive operations with actor, action, target entity, and change payload for investigations.
- **Application Setting**: Key-value configuration scoped to organization or optionally a single branch.
- **Subscription Cache**: Local cache of organization subscription tier and validity for graceful offline or degraded validation.

All introduced tables MUST follow shared conventions: UUID primary keys, created/updated metadata, soft delete fields, and automatic maintenance of audit timestamps and acting user where applicable.

### RPC Functions

- **Custom claims resolution**: On successful authentication, resolve staff member, organization, assigned branches, and role into session authorization claims. Must fail safely when staff record is missing or inactive. Staff with no branch assignments receive claims without branch scope and are limited to the blocked client state.
- **Create organization** (default administrator on fresh install): Create the single tenant root with required fields; only when no organization exists yet; rejects creation if an organization already exists.
- **Create branch** (default administrator / owner / administrator): Create first and additional branches under the organization during minimal setup; validate organization scope.
- **Create staff account** (owner/administrator only): Create auth identity, staff member record, and branch assignments; validate role, email uniqueness, and branch scope; requires existing organization and branch; enforce owner-creation rules per FR-022c.
- **Reset staff password** (owner/administrator only): Set a new password for a staff member within the same organization; must not expose prior unknown secrets.
- Full organization settings, branch list/edit/deactivate, and staff list/edit/deactivate RPC flows are deferred to V1-2.

### RLS Policies

Row-level policies MUST be defined for:

- `organizations`
- `branches`
- `staff_members`
- `staff_branch_assignments`
- `roles_permissions`

Policies MUST enforce:

- Authenticated access only where applicable.
- Organization isolation using session organization context.
- Branch isolation using session branch assignments.
- Soft-deleted rows excluded from normal access.
- No cross-tenant reads or writes in backend verification scenarios.

### API Contracts

- Sign in with email and password through the platform authentication service.
- Sign out and end the client session (explicit logout and idle timeout).
- Create organization and branch (bootstrap): minimal required fields on fresh install.
- Create staff account (owner/administrator only): email, role, branch assignments, initial password (after org/branch exist).
- Reset staff password (owner/administrator only): set new password; return or display assigned value to the administrator performing the reset.
- Read staff profile and branch assignment data needed for post-login context.
- Read role-permission mappings needed to build the permission cache.
- Session refresh handled by the client authentication integration without custom re-login for each request.

Protected domain APIs (patients, appointments, billing, etc.) are out of scope for this feature.

### UI States

- **Login - Initial**: Email and password fields, submit action, forgot-password guidance link, link or path back to unauthenticated entry experience where applicable.
- **Login - Forgot Password**: Plain-language message to contact the clinic administrator; no self-service reset form.
- **Login - Submitting**: Inputs disabled or loading indicator; no duplicate submissions.
- **Login - Error**: Invalid credentials, inactive account, connectivity failure, or configuration error with plain-language guidance.
- **Login - Success**: Transition to the minimal authenticated placeholder shell (header with user/branch context, logout, placeholder home).
- **Authenticated Placeholder Shell**: Post-login home with identity context visible, logout available, minimal active-branch selector when multiple assignments exist, and no operational module navigation beyond placeholders.
- **Active Branch Change**: User selects another assigned branch in the minimal selector; session branch context updates without requiring re-login.
- **Startup - No Persisted Session**: On launch after a prior close, the user starts unauthenticated at the login experience; no session restoration occurs.
- **Session Expired**: Redirect to login with message that session ended (refresh failure or idle timeout).
- **Idle Timeout Sign-Out**: After 15 minutes without keyboard or pointer input in the app window, session cleared and user returned to login with an inactivity message.
- **First Sign-In Warning**: Default administrator sees prominent shipped-password change warning; may dismiss and continue without forced change.
- **Clinic Bootstrap Setup**: Default administrator guided flow to create organization and first branch when none exist; blocks staff creation until complete.
- **Staff Account Create**: Owner/administrator form for email, role, branch assignment, and initial password; success confirmation showing assigned credentials to the administrator.
- **Staff Password Reset**: Owner/administrator sets a new password for selected staff; assigned password visible to the resetting administrator.
- **Post-Login Context Loading**: Loading staff profile, active branch, and permissions before enabling protected navigation.
- **Post-Login Ready**: Authenticated user with branch and permission context available to route guard and future modules.
- **Post-Login Blocked - No Branch Assignment**: Authenticated user in placeholder shell with profile visible, no active branch, branch-scoped actions disabled, and administrator-contact messaging.
- **Permission Denied**: User is authenticated but action or route is blocked by role or branch scope; unauthorized controls are hidden or disabled in normal navigation, and an explicit brief message appears when a blocked route or action is attempted.
- **Logout Complete**: Return to login; no residual protected state.

### Validation Rules

- Email must be present and well-formed before sign-in submission.
- Password must be present before sign-in submission.
- Only active staff linked to a valid auth identity may authenticate.
- Active branch must belong to the user's branch assignment set when branch-scoped access is granted.
- Changing active branch via the minimal selector must only list branches assigned to the signed-in user.
- Staff with zero branch assignments authenticate without an active branch and remain in the blocked configuration state.
- Permission cache must be built only from granted permissions for the user's role.
- Client must not treat unauthenticated or partially loaded session state as authorized for protected routes.

### AI Hooks

This feature introduces no AI-assisted workflow. Permission keys related to future AI access may exist in seeded data but AI surfaces are not activated in V1-1.

### Audit Requirements

- Audit infrastructure MUST record create/update attribution on tables introduced in this feature.
- Sensitive authentication-adjacent changes (for example staff role or permission mapping changes once management exists) MUST be supportable by the audit log; V1-1 focuses on infrastructure and schema readiness rather than staff-admin UI-driven changes.
- Login and logout events SHOULD be diagnosable through standard platform authentication logging; detailed security audit policies for failed login throttling are out of scope unless required by shared auth spec later.
- Staff account creation and administrator-initiated password resets SHOULD be auditable once operational audit patterns are wired; V1-1 must not omit audit infrastructure that would block recording these events later.

### Acceptance Criteria

1. A seeded staff user can sign in with email and password and reach the minimal authenticated placeholder shell with post-login context loaded.
2. Invalid credentials are rejected without creating a session.
3. Unauthenticated users cannot access protected routes and are redirected to login.
4. Authenticated session includes organization, role, staff identity, and branch scope consistent with seed data.
5. Permission cache reflects seeded role-permission mappings for each of the five roles in test scenarios.
6. Logout ends the session and clears cached identity and permission context.
7. Backend verification utilities demonstrate that cross-organization data access is blocked for tables delivered in this feature.
8. Fully closing and reopening the application ends the session and requires sign-in again.
9. No organization management, branch management, staff management, permission-matrix editing, or full branch-switcher component UI is required to pass this feature; the minimal placeholder-shell branch selector is in scope.
10. No patient, appointment, billing, or AI workflow is required to demonstrate this feature.
11. Expired subscription cache data does not prevent login.
12. On a fresh install, default administrator can create organization and branch, then create a staff account for another role that can sign in.
13. Forgot-password path shows contact-administrator messaging without self-service reset.
14. Owner or administrator can reset a staff password; affected user signs in with the new password.
15. Fifteen minutes of inactivity while the app is open ends the session and requires sign-in again.

### Test Cases

1. Sign in with valid seeded credentials and confirm authenticated post-login state with staff profile loaded.
2. Sign in with invalid password and confirm generic failure with no session.
3. Sign in with inactive staff record and confirm denial.
4. Sign in, fully close the application, reopen it, and confirm the user must sign in again with no restored session.
5. While the app remains running, allow session refresh to fail and confirm redirect to login on protected access.
6. Attempt protected route without session and confirm redirect to login.
7. Sign in as each seeded role and confirm permission cache matches expected grants for a representative permission key set.
8. Sign in as user with multiple branch assignments, confirm active branch defaults per primary or deterministic rule, change branch via minimal selector, and confirm session branch context updates.
9. Sign in as user with no branch assignments and confirm authentication succeeds, placeholder shell shows blocked configuration state, and branch-scoped protected access is denied with administrator-contact messaging.
10. Logout and confirm protected route access requires login again.
11. Run backend verification utilities for authentication flow and confirm RLS blocks cross-organization reads and writes on delivered tables.
12. Confirm soft-deleted seed rows are not visible through normal authenticated queries.
13. Sign in with expired subscription cache seed data and confirm login is not blocked.
14. On fresh install: sign in as default administrator, create organization and branch, create receptionist account, sign out, sign in as receptionist.
15. Use forgot-password on login screen and confirm contact-administrator message only.
16. As administrator, reset another user's password, view assigned value, and confirm that user signs in with the new password.
17. Sign in, remain without keyboard or pointer input for 15 minutes with app open, and confirm automatic sign-out.

### Implementation Constraints

- This feature MUST build on V1-0 project scaffolding (deployment profile, unauthenticated entry experience, route-guard foundation) without redesigning startup behavior.
- Organization and branch are not pre-seeded; V1-1 delivers minimal initial org/branch setup by the default administrator, then staff account creation and administrator password reset. Full org/branch/staff management screens are deferred to V1-2.
- Default administrator credentials must be documented in deployment/setup materials with a strong post-install change recommendation; V1-1 warns on first sign-in but does not hard-block setup on the shipped password.
- Subscription cache is populated in V1-1 for later enforcement; login must not depend on subscription validity until a later feature explicitly adds enforcement.
- Domain validation and authorization source of truth for data introduced here MUST live in database constraints, policies, and authentication hooks—not solely in client logic.
- No AI dependency for login, session management, or permission caching.
- Cloud-only deployment enhancements are out of scope unless already supported by V1-0 local deployment path.

### Key Entities *(include if feature involves data)*

- **Organization**: The clinic tenant root used to isolate all downstream data; includes branding and locale context (logo URL, currency code, timezone).
- **Branch**: A location within an organization; scope anchor for staff assignments and future operational data; includes a short branch code and optional maps link.
- **Staff Member**: An authenticated clinic worker linked to platform identity and a single role.
- **Staff Branch Assignment**: Defines which branches a staff member may access and which is primary.
- **Role Permission**: Defines granular capabilities granted to each role.
- **Authenticated Session Context**: Organization, branches, role, staff identity, active branch, and cached permissions used by the client after login.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch clinics that need staff sign-in and strict tenant isolation before operational modules. Enterprise SSO, patient portals, and hospital-scale identity federation are out of scope.
- **Layer Placement**: The desktop client owns login and logout presentation, session persistence UX, route guarding, post-login context loading, and permission-aware UI gating. The backend platform owns identity authentication, token issuance, and session refresh integration. The database layer owns staff and tenancy schema, custom claims resolution, row-level isolation, audit infrastructure, permission seed data, and verification utilities. The AI layer remains absent; no AI capability is required for authentication.
- **Data Integrity & Security**: All new tables follow shared audit and soft-delete conventions; row-level policies enforce organization and branch isolation; permissions are seeded for five roles; defense in depth applies across client permission cache, future RPC checks, and database policies; inactive or unassigned staff cannot access protected branch-scoped work.
- **Failure Handling**: Login and session refresh failures fail closed without partial protected state; backend unavailability surfaces clear login errors; AI unavailability does not affect authentication; subscription cache degradation or expiry must not hard-lock clinic login in V1-1; idle timeout protects shared workstations when staff forget to sign out.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: At least 95% of valid sign-in attempts with seeded test accounts complete and reach post-login ready state within 5 seconds under normal local clinic network conditions.
- **SC-002**: 100% of unauthenticated attempts to access protected routes in test scenarios are redirected to login.
- **SC-003**: 100% of backend verification scenarios for delivered tables demonstrate blocked cross-organization access.
- **SC-004**: In 100% of test scenarios, fully closing and reopening the application ends the session and requires sign-in before accessing protected areas.
- **SC-005**: Logout clears session and permission context in 100% of test scenarios, with subsequent protected access requiring login.
- **SC-006**: Representative role-based permission checks for all five seeded roles match expected grant/deny outcomes in 100% of defined test matrix cases.
- **SC-007**: In 100% of idle-timeout test scenarios, 15 minutes without keyboard or pointer input in the application window ends the session and requires sign-in before protected access.
- **SC-008**: In 100% of subscription-expiry test scenarios with seeded cache data, login is not blocked in V1-1.
- **SC-009**: A new installation can bootstrap organization, branch, and at least one non-administrator staff account via the default administrator and complete sign-in for that account without V1-2 management UI.

## Assumptions

- V1-0 project scaffolding is complete, including local deployment profile, unauthenticated entry experience, and route-guard foundation.
- A default administrator account is seeded or shipped with the product for first-time bootstrap; first sign-in shows a prominent password-change warning but does not force change in V1-1. No organization or branch records are pre-seeded—those are created through minimal V1-1 setup screens. Each installation supports exactly one organization in V1-1. Only the bootstrap administrator may create the first owner; thereafter only owners may create additional owner accounts.
- Additional staff accounts are created by owners/administrators through the minimal V1-1 provisioning flow until V1-2 full staff management is delivered.
- Email-and-password is the only authentication method in V1-1; SSO, MFA, and self-service password reset are deferred.
- Sessions do not survive application close; 15-minute idle timeout (no keyboard or pointer input in the app window) adds protection on shared reception workstations when the app stays open.
- Password recovery is administrator-mediated; viewing a password applies only to values the administrator sets or resets, not to recovering unknown prior secrets from storage.
- Subscription cache is created and seeded in V1-1 but login is never blocked by expiry until a later subscription-enforcement feature.
- The five roles and permission key catalog follow architecture defaults; custom per-organization permission editing UI is deferred to V1-2.
- Primary branch selection uses `is_primary` on branch assignment when present; otherwise the lexicographically first active assigned branch is used as the login default. Users with multiple assignments may change active branch via the minimal placeholder-shell selector during the session.
- Shared `specs/common/auth.spec.md` and `specs/common/rbac.spec.md` will be authored later; this feature spec is authoritative for V1-1 until those exist.
- AI remains optional and non-blocking for all authentication flows.
