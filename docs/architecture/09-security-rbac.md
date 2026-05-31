# Security and RBAC

- Purpose: Centralize authentication, authorization, audit, deletion, and security principles.
- Read this when: working on login/session flows, permission checks, audit behavior, or sensitive operational constraints.
- Canonical for: auth behavior, RBAC, audit logging, soft delete rules, and defense-in-depth constraints.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/05-database.md`, and the feature spec being implemented.
- Not covered here: deployment topology, analytics roadmap details, or non-security UX patterns.

---

## Audit, Security, and RBAC Architecture

### Authentication

- **Supabase GoTrue** handles all authentication.
- Staff members authenticate with **username + password** (not email). Usernames are stored in GoTrue's `auth.users.email` field without an `@` symbol. Username rules: 3–32 chars, lowercase `[a-z0-9_-]`, no `@`.
- JWT tokens include custom claims: `organization_id`, `branch_ids` (comma-separated), `role`, `staff_member_id`, `setup_required`.
- Custom claims are populated by a PostgreSQL function (`get_custom_claims`) triggered during the GoTrue login hook. The function delegates to `auth_internal.build_staff_claims(user_id)`.
- Token refresh is handled by explicit `refreshSession()` calls after context-changing operations (e.g., completing clinic bootstrap).
- **No session persistence across app restarts**: the Flutter app uses `EmptyLocalStorage` and forces sign-out on cold start (shared-workstation model).
- **Idle timeout auto-sign-out**: configurable inactivity timer (default 15 minutes, range 1–120 minutes) signs the user out of the workstation.

### Bootstrap Flow

A special `is_bootstrap_admin` flag on the first staff_members row enables first-time clinic setup:
1. Bootstrap admin signs in → JWT contains `setup_required: true` (no org exists yet).
2. Admin calls `bootstrap_create_organization(...)` to create the clinic organization.
3. Admin calls `bootstrap_create_branch(...)` to create the first branch (auto-assigned).
4. Admin calls `create_staff_account(...)` to provision the first owner account.
5. After setup, `refreshSession()` updates the JWT with real org/branch claims.

### Role-Based Access Control (RBAC)

#### Role Definitions

| Role            | Description                      | Typical Permissions                                                               |
| --------------- | -------------------------------- | --------------------------------------------------------------------------------- |
| `owner`         | Organization owner. Full access. | All operations. Manage organization settings, billing, staff.                     |
| `administrator` | Branch or organization admin.    | Manage staff, branches, settings. Full operational access.                        |
| `doctor`        | Clinical staff.                  | View own schedule, manage visits/SOAP/treatment plans, view patients.             |
| `receptionist`  | Front desk staff.                | Manage appointments, check-in, create invoices, register patients.                |
| `lab_staff`     | Laboratory staff.                | Upload visit attachments (lab reports, examination PDFs), view assigned patients. |

#### Permission Model

Permissions are stored in the `roles_permissions` table as key-value pairs:

```
permission_key examples:
  patients.create
  patients.view
  patients.edit
  patients.delete
  appointments.create
  appointments.cancel
  invoices.create
  invoices.apply_discount
  invoices.apply_discount_above_threshold
  visits.create
  visits.edit_soap
  shifts.manage
  settings.manage_staff
  settings.manage_branches
  analytics.view
  ai.access
```

Permission checks happen at three levels:
1. **RLS policies** (database level): enforce organization and branch isolation. Prevents any cross-tenant data access regardless of application code. Domain tables block direct INSERT/UPDATE/DELETE via RLS (`WITH CHECK (false)`).
2. **RPC functions** (`auth_internal` schema): call `assert_permission(key)` before executing business logic. This is the authoritative enforcement layer.
3. **Flutter service layer** (application level): check granular permissions from cached `roles_permissions` before rendering UI elements. This provides fast UX feedback but is not the security boundary.

#### Permission Resolution Flow

```
User action in Flutter UI
        │
        ▼
Flutter checks permission from cached roles_permissions
  → If denied: UI element hidden/disabled, action blocked
  → If allowed: proceed
        │
        ▼
Supabase RPC function checks permission again
  → If denied: returns error
  → If allowed: executes
        │
        ▼
RLS policy filters data scope
  → User only sees/modifies data in their org/branches
```

### Audit Trail

#### Automatic Audit Fields

Every table has `created_at`, `created_by`, `updated_at`, `updated_by`, `is_deleted`, `deleted_at`, `deleted_by` columns populated automatically by triggers.

#### Detailed Audit Log

Sensitive operations are logged to the `audit_log` table by the PostgreSQL functions that perform them:

```sql
-- Inside create_appointment function:
INSERT INTO audit_log (user_id, action, table_name, record_id, new_data_json)
VALUES (auth.uid(), 'appointment.create', 'appointments', v_new_id, row_to_json(v_new_record));
```

Logged operations include:
- Patient creation, modification, deletion
- Appointment creation, reschedule, cancellation, status changes (including `confirmed` phone confirmation)
- Invoice creation, payment, discount application
- SOAP note creation and modification
- Staff role/permission changes
- Settings changes

### Soft Delete

All records use soft delete (`is_deleted = true`). Hard deletes are never performed by the application.

- RLS policies include `is_deleted = false` in their `USING` clauses.
- Soft-deleted records are invisible to normal queries.
- An admin UI (future) may allow viewing deleted records.
- Periodic cleanup of old soft-deleted records can be done via maintenance scripts.

### Security Principles

| Principle                    | Implementation                                                                         |
| ---------------------------- | -------------------------------------------------------------------------------------- |
| **No direct DB access**      | All access goes through PostgREST + RLS. No raw connection strings in the Flutter app. |
| **JWT-based auth**           | Every API request carries a JWT. PostgREST validates it before processing.             |
| **Defense in depth**         | Permission checks in Flutter UI + RPC functions + RLS policies. Three layers.          |
| **AI isolation**             | AI service has no DB credentials. Cannot read or write data.                           |
| **Approval-gated AI**        | All AI-generated commands require explicit human approval before execution.            |
| **Encrypted backups**        | Tier 2 cloud backups are encrypted before upload.                                      |
| **Subscription enforcement** | Cached locally with grace period. System degrades gracefully, never hard-locks.        |

---
