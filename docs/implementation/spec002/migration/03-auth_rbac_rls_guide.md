### Migration Purpose

This migration defines the application’s **Row Level Security (RLS)** system in PostgreSQL/Supabase. Its job is to decide:

* who can access data,
* which rows they can see,
* which rows they can modify,
* and which operations are completely forbidden.

At a high level, this file turns the database into an authorization engine. Instead of trusting the frontend or backend to enforce permissions, the database itself becomes responsible for access control.

The flow is:

1. A user logs in through Supabase Auth.
2. Supabase generates a JWT (JSON Web Token).
3. Custom claims are inserted into that JWT.
4. Every API request carries the JWT.
5. PostgreSQL RLS policies read those claims and decide access permissions.

This means authorization happens directly inside the database layer.

---

### Important RLS Concepts

#### Authenticated vs anon

Supabase uses PostgreSQL roles behind the scenes.

* `authenticated` = logged-in users
* `anon` = unauthenticated/public users

Policies are usually written for `authenticated`.

---

#### USING clause

`USING (...)` defines which rows are visible or targetable.

It applies to:

* `SELECT`
* `UPDATE`
* `DELETE`

Think of it as:

> “Which rows are allowed to exist from this user’s perspective?”

Example:

```sql
USING (organization_id = public.jwt_organization_id())
```

Meaning:

> “Only rows belonging to your organization are accessible.”

---

#### WITH CHECK clause

`WITH CHECK (...)` validates rows being written.

It applies to:

* `INSERT`
* `UPDATE`

Think of it as:

> “What values are you allowed to save?”

Even if a user can update a row, `WITH CHECK` prevents them from changing protected values.

---

#### JWT claims

A JWT contains authentication information.

This system stores extra custom fields inside the JWT, including:

* organization ID
* branch IDs
* staff member ID
* role
* setup state

The policies read these claims directly.

This avoids repeatedly querying the database for identity metadata.

---

#### SECURITY DEFINER

A function marked `SECURITY DEFINER` runs with the permissions of the function owner instead of the caller.

This is important because some helper functions need to bypass RLS safely.

Without this, some policy checks would recursively fail.

---

### Schema Grants

```sql
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
```

These commands allow roles to access schemas.

A schema is like a namespace or folder containing tables/functions.

This does not grant table access yet. It only allows referencing objects inside those schemas.

---

### Table Grants

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
```

This gives authenticated users permission to attempt operations.

However, RLS still filters rows afterward.

This is an important distinction:

> PostgreSQL permissions decide whether an operation type is allowed at all.
> RLS decides which specific rows are allowed.

So even with full table grants, RLS still protects data.

---

### JWT helper functions

| Function                     | Returns                                                           |
| ---------------------------- | ----------------------------------------------------------------- |
| `request_jwt_claims()`       | Full claims JSON from request or `auth.jwt()`                     |
| `jwt_organization_id()`      | UUID of current org                                               |
| `jwt_branch_ids()`           | Array of branch UUIDs (parsed from comma-separated string in JWT) |
| `jwt_staff_member_id()`      | Current staff row id                                              |
| `jwt_staff_role()`           | Enum role                                                         |
| `jwt_setup_required()`       | Boolean — bootstrap before org exists                             |
| `current_staff_member_row()` | Full `staff_members` row for logged-in user (`SECURITY DEFINER`)  |

---

### Function: request_jwt_claims()

This function retrieves JWT claims from the current request.

It first tries:

```sql
current_setting('request.jwt.claims', true)
```

PostgREST injects JWT data into PostgreSQL session settings during API requests.

If that fails, it falls back to:

```sql
auth.jwt()
```

If both fail, it returns:

```sql
{}
```

This prevents crashes in environments where no JWT exists, such as:

* migrations,
* admin scripts,
* internal execution contexts.

The function is marked `STABLE`, meaning PostgreSQL assumes it returns the same result during a single statement execution.

---

### JWT Helper Functions

Several small helper functions extract individual claims from the JWT.

---

### jwt_organization_id()

Returns the organization UUID from the JWT.

```sql
organization_id -> uuid
```

This is the primary tenant-isolation mechanism.

Most policies compare table rows against this value.

---

### jwt_branch_ids()

Returns an array of branch UUIDs.

The JWT stores them as a comma-separated string:

```text
uuid1,uuid2,uuid3
```

The function converts that into:

```sql
uuid[]
```

This allows policies like:

```sql
branch_id = ANY(public.jwt_branch_ids())
```

Meaning:

> “Branch ID must exist in the user’s allowed branch list.”

---

### jwt_staff_member_id()

Returns the current staff member UUID.

Used to identify the logged-in employee record.

---

### jwt_staff_role()

Returns the staff role enum.

Likely values might include:

* admin
* doctor
* receptionist

This supports role-based authorization logic.

---

### jwt_setup_required()

Returns whether the system is still in bootstrap/setup mode.

This supports first-time initialization flows before a real organization exists.

Without this flag, onboarding would deadlock because no organization-scoped policies could pass yet.

---

### current_staff_member_row()

This function loads the current logged-in staff member row.

It uses:

```sql
SECURITY DEFINER
```

which allows bypassing RLS safely.

The query:

```sql
WHERE sm.auth_user_id = auth.uid()
```

matches the current authenticated Supabase user.

This helper is useful because many policies need the caller’s staff metadata.

---

### Organizations Table Policies

The `organizations` table represents tenants.

This is the highest-level isolation boundary.

---

### organizations_select

Users may view:

* their own organization,
* or bootstrap setup data during first-time initialization.

Normal access rule:

```sql
id = public.jwt_organization_id()
```

Meaning:

> “You can only see your organization.”

Special setup rule:

If setup is required and the user is a bootstrap admin, temporary access is allowed.

This supports organization creation during onboarding.

---

### organizations_insert

```sql
WITH CHECK (false)
```

This blocks direct inserts entirely.

Clients cannot create organizations directly.

Instead, they must use a controlled RPC function from migration 4.

This is a common security pattern:

* expose business workflows via RPC,
* block raw table writes.

---

### organizations_update

Users may update only their own organization rows.

Both:

* `USING`
* `WITH CHECK`

validate organization ownership.

This prevents users from:

* accessing another organization’s row,
* or changing a row’s organization ID.

---

### Branches Table Policies

Branches belong to organizations.

---

### branches_select

Users can only view:

* non-deleted branches,
* inside their organization.

This enforces tenant isolation.

---

### branches_insert

Direct inserts are blocked.

Creation must happen through trusted RPC logic.

---

### branches_update

Users may update a branch only if:

* the branch belongs to their organization,
* and the branch exists in their assigned branch list.

This creates branch-level scoping inside the organization.

Important distinction:

* Organization membership alone is insufficient.
* The user must also be assigned to the branch.

---

### Staff Members Policies

These policies govern employee visibility.

---

### staff_members_select

Users can see:

* themselves,
* or colleagues sharing branches in the same organization.

This is implemented using an `EXISTS` subquery against:

* `staff_branch_assignments`
* `branches`

The logic effectively says:

> “You can see coworkers connected to branches within your organization.”

This supports:

* scheduling,
* internal staff lookup,
* collaboration features.

---

### staff_members_insert

Direct inserts are blocked.

Staff creation likely occurs through controlled workflows.

---

### staff_members_update

Users can update:

* themselves,
* or staff members connected to accessible branches.

This suggests branch managers or admins may edit colleague records.

`WITH CHECK (is_deleted = false)` prevents updates that would violate soft-delete constraints.

---

### Staff Branch Assignments Policies

This table links staff members to branches.

---

### staff_branch_assignments_select

Users can see assignments if:

* the branch belongs to their JWT branch list,
* or setup mode is active and the assignment belongs to themselves.

This supports both:

* normal branch authorization,
* bootstrap onboarding flows.

---

### staff_branch_assignments_insert

Direct inserts are blocked.

Assignments must be created through controlled backend logic.

---

### Roles Permissions Policies

This table likely stores the permission matrix.

Example:

* role → capability mappings.

---

### roles_permissions_select

Users may read:

* only non-deleted rows,
* only granted permissions.

This allows frontend permission checks without exposing disabled/internal entries.

The table is effectively read-only from the client perspective.

---

### Audit Log Policies

The audit log stores security or activity events.

---

### audit_log_select

Users can view:

* their own actions,
* or organization-level audit entries.

This balances:

* personal transparency,
* organizational oversight.

Cross-organization access is blocked.

---

### App Settings Policies

This table stores configuration values.

Some settings are:

* organization-wide,
* others branch-specific.

---

### app_settings_select

Users may read:

* rows inside their organization,
* and either:

  * global organization settings (`branch_id IS NULL`)
  * or branch settings for branches assigned to them.

This creates hierarchical configuration visibility.

---

### app_settings_insert

Direct inserts are blocked.

Settings changes must go through RPC/backend workflows.

---

### Subscription Cache Policies

This table likely stores billing/subscription state.

---

### subscription_cache_select

Users can only view rows matching their organization ID.

This ensures subscription information remains tenant-isolated.

---

### Architectural Pattern Summary

This migration implements several important security patterns simultaneously.

#### Tenant isolation

Almost every table checks:

```sql
organization_id = public.jwt_organization_id()
```

This prevents cross-organization data leaks.

---

#### Branch-level authorization

Many policies additionally restrict access by branch assignment.

This enables sub-scoping within a tenant.

---

#### Soft-delete awareness

Most policies include:

```sql
is_deleted = false
```

Deleted rows remain in the database but become invisible.

---

#### RPC-only mutations

Many tables block direct inserts with:

```sql
WITH CHECK (false)
```

This forces sensitive workflows through controlled RPC functions.

---

#### JWT-driven authorization

The database trusts JWT claims as the source of identity and authorization context.

This avoids repeated joins/lookups on every request.

---

#### Database-centric security

The key architectural decision here is:

> Authorization is enforced inside PostgreSQL itself, not only in application code.

Even if:

* frontend validation fails,
* backend logic has bugs,
* or an API endpoint is misconfigured,

RLS still blocks unauthorized row access.
