### Migration Purpose

This migration is the core business-logic layer of the system.

Previous migrations established:

* database structure,
* audit automation,
* Row Level Security policies.

This migration adds:

* authentication-aware business workflows,
* JWT custom claim generation,
* RPC APIs for the Flutter application,
* secure staff account provisioning,
* authorization guard functions,
* password reset workflows.

Architecturally, this is the layer that transforms the database from:

* “a secure data store”

into:

* “an application platform.”

---

### High-Level Architecture

This migration connects four major systems together:

| System                 | Responsibility                 |
| ---------------------- | ------------------------------ |
| Supabase Auth (GoTrue) | User authentication            |
| JWT Claims             | User context propagation       |
| PostgreSQL RLS         | Authorization enforcement      |
| RPC Functions          | Controlled business operations |

The overall login flow becomes:

```text id="v0vjlwm"
User logs in
    ↓
GoTrue authenticates credentials
    ↓
get_custom_claims() executes
    ↓
JWT receives org/role/branch claims
    ↓
Flutter app receives token
    ↓
All future DB/API requests include JWT
    ↓
RLS policies read JWT claims
    ↓
Database enforces authorization automatically
```

This architecture is extremely important because:

* authorization decisions happen inside PostgreSQL,
* not inside Flutter,
* not inside API code,
* and not inside client logic.

---

### Core Concepts

---

### RPC (Remote Procedure Call)

An RPC is a database function callable remotely by the application.

Flutter can call:

```dart id="2fhrdu"
supabase.rpc('create_staff_account', params: {...})
```

Instead of directly manipulating tables.

This is important because:

* direct table access is dangerous,
* business workflows require validation,
* some operations must bypass RLS safely,
* workflows often involve multiple coordinated writes.

RPCs become the secure backend API layer.

---

### SECURITY DEFINER

Many functions use:

```sql id="zz2jlwm"
SECURITY DEFINER
```

Meaning:

* the function executes with the permissions of its owner,
* not the caller.

This allows the function to:

* bypass RLS,
* access protected schemas,
* write to restricted tables.

However, SECURITY DEFINER functions are dangerous unless they carefully validate callers.

That is why many RPCs begin with authorization checks like:

```sql id="2tntm8"
assert_owner_or_administrator()
```

---

### GoTrue

GoTrue is Supabase’s authentication service.

It handles:

* email/password login,
* JWT issuance,
* refresh tokens,
* sessions,
* user identity management.

This migration integrates PostgreSQL directly into GoTrue’s token generation pipeline.

---

### JWT Custom Claims

JWTs normally contain:

* user ID,
* expiration,
* issuer,
* authentication metadata.

This migration injects custom application claims like:

* organization ID,
* branch IDs,
* staff role,
* setup state.

These claims become the foundation of RLS authorization.

---

### Internal Auth Tables

Supabase stores login users in:

* `auth.users`
* `auth.identities`

These are not part of your application schema.

Your application tables live in:

* `public.*`

This migration bridges:

* authentication users,
* and clinic staff records.

---

# JWT Claim System

---

### Function: build_staff_claims()

This function constructs the custom JWT payload for a logged-in user.

It is one of the most important functions in the entire architecture.

---

### Why JWT Claims Matter

Without custom claims:

* RLS policies would not know:

  * organization,
  * branches,
  * role,
  * setup state.

The JWT becomes the “identity context packet” for every request.

---

### User Lookup

The function begins by loading the logged-in staff member:

```sql id="d5b1wh"
FROM public.staff_members sm
WHERE sm.auth_user_id = p_user_id
```

This connects:

* Supabase Auth user
* to clinic staff identity.

---

### Active Staff Validation

The query filters:

```sql id="9mljlwm"
sm.is_deleted = false
AND sm.is_active = true
```

Meaning:

* deleted staff lose access,
* inactive staff lose access.

This allows “soft disabling” accounts without deleting auth users.

---

### Empty Claims for Unauthorized Users

If no valid staff member exists:

```sql id="ghsmwh"
RETURN '{}'::jsonb;
```

Meaning:

* user authenticates successfully,
* but receives no clinic authorization claims.

As a result:

* RLS policies deny access automatically.

This is a powerful design:

* authentication ≠ authorization.

---

### Organization Resolution

The function loads the organization:

```sql id="ivd0ih"
SELECT o.id
FROM public.organizations o
```

In V1-1:

* only one organization exists per installation.

So the function selects:

* the first active organization.

---

### Branch Aggregation

The function gathers all branch assignments:

```sql id="1zhhgm"
string_agg(b.id::text, ',')
```

Result example:

```text id="ud20hm"
uuid1,uuid2,uuid3
```

These become JWT claims.

RLS policies later use them for branch-scoped authorization.

---

### Primary Branch Ordering

The query orders branches by:

```sql id="5a34q0"
sba.is_primary DESC
```

Meaning:

* primary branch appears first in the list.

This is useful for:

* frontend defaults,
* UI auto-selection,
* initial branch context.

---

### Setup Required State

```sql id="p08twx"
v_setup_required := v_staff.is_bootstrap_admin AND v_org_id IS NULL;
```

Meaning:

* bootstrap admin exists,
* but organization setup has not happened yet.

This enables the initial installation workflow.

---

### Building the JWT Payload

The function returns:

```sql id="tdrujlwm"
jsonb_build_object(...)
```

Result example:

```json id="03s7s2"
{
  "staff_member_id": "...",
  "role": "administrator",
  "organization_id": "...",
  "branch_ids": "uuid1,uuid2",
  "setup_required": false
}
```

These values later power all RLS authorization.

---

### jsonb_strip_nulls()

This removes null fields from the final JWT.

Without it:

```json id="yu9i9r"
{
  "organization_id": null
}
```

would still appear.

Removing nulls keeps JWTs cleaner and smaller.

---

# get_custom_claims()

---

### Two Versions of the Function

This migration defines:

```sql id="tspjlwm"
get_custom_claims(uuid)
```

and:

```sql id="j0l2m5"
get_custom_claims(event jsonb)
```

These are overloaded PostgreSQL functions.

Same name, different parameters.

---

### Wrapper Function

The UUID version is mainly:

* a helper,
* testable manually,
* callable directly from SQL.

It simply forwards to:

```sql id="6usjlwm"
build_staff_claims()
```

---

### GoTrue Hook Entry Point

The JSONB version is the real Supabase integration hook.

GoTrue sends:

```json id="r2w5i4"
{
  "user_id": "...",
  "claims": {...}
}
```

The function:

1. extracts existing claims,
2. builds custom clinic claims,
3. merges them together.

---

### Claim Merge Operator

This line is important:

```sql id="cgbjlwm"
v_claims || v_custom
```

`||` merges JSON objects.

Result:

* default auth claims remain,
* clinic claims are appended.

---

### Conditional Granting

The migration conditionally grants permissions to:

```text id="wthjlwm"
supabase_auth_admin
```

Why conditional?

Because:

* local environments,
* hosted Supabase,
* CI systems

may not all define that role.

This makes the migration portable.

---

# RPC Helper Functions

---

### rpc_success()

This standardizes successful API responses.

Instead of every RPC inventing its own structure, all return:

```json id="1jlwmx"
{
  "success": true,
  "data": {...},
  "error_code": null,
  "error_message": null
}
```

Consistency simplifies Flutter code significantly.

---

### rpc_error()

This standardizes failure responses:

```json id="8jlwm4"
{
  "success": false,
  "error_code": "INVALID_INPUT",
  "error_message": "Organization name is required."
}
```

This avoids exception-driven frontend logic.

---

# Authorization Guard Functions

---

### Purpose of Guard Functions

Instead of duplicating authorization logic across RPCs, the migration centralizes it.

This is an important backend architecture principle:

* reusable authorization primitives.

---

### assert_bootstrap_admin()

This verifies:

* caller exists,
* caller is active,
* caller is bootstrap admin.

If validation fails:

```sql id="jlwm2v"
RAISE EXCEPTION 'NOT_BOOTSTRAP_ADMIN';
```

This stops execution immediately.

---

### Why Exceptions Are Used

Exceptions are useful because:

* they abort execution,
* simplify control flow,
* and bubble to the RPC exception handler.

---

### assert_owner_or_administrator()

This validates:

* owner,
* administrator,
* or bootstrap admin.

This becomes the authorization gateway for administrative RPCs.

---

# Installation State Helpers

---

### organization_exists()

Checks whether the clinic organization has already been created.

Used to prevent:

* duplicate setup,
* invalid provisioning order.

---

### owner_exists()

Checks whether an owner account already exists.

Important because:

* first owner creation is special,
* later owner creation requires stricter permissions.

---

# RPC: bootstrap_create_organization()

---

### Purpose

This handles first-time clinic setup.

Only the bootstrap administrator can execute it.

---

### Validation Flow

The RPC validates:

1. caller is bootstrap admin,
2. organization does not already exist,
3. organization name is present.

Only after validation does insertion occur.

---

### NULLIF + trim()

Pattern:

```sql id="5jlwm9"
NULLIF(trim(value), '')
```

Meaning:

* remove whitespace,
* convert empty strings to NULL.

This normalizes user input.

---

### Organization Insert

The RPC inserts into:

* organizations table,
* while automatically attaching:

  * created_by,
  * updated_by.

---

### Audit Logging

After creation:

```sql id="jlwm5y"
INSERT INTO public.audit_log
```

records the action.

This creates:

* historical traceability,
* administrative accountability.

---

### Exception Translation

The RPC catches:

```sql id="jlwmz4"
NOT_BOOTSTRAP_ADMIN
```

and converts it into a structured API error response.

This is important because:

* raw PostgreSQL exceptions are poor API contracts,
* structured errors are frontend-friendly.

---

# RPC: bootstrap_create_branch()

---

### Purpose

Creates the first or subsequent clinic branches.

---

### First Branch Special Logic

The function checks:

```sql id="jlwm8n"
v_is_first_branch
```

If true:

* bootstrap admin is automatically assigned to that branch.

This guarantees:

* at least one valid branch assignment exists.

---

### Why This Matters

Without automatic assignment:

* bootstrap admin could become orphaned,
* RLS branch policies could lock them out.

This is a subtle but critical bootstrapping safeguard.

---

# Internal Function: create_auth_user()

---

### Purpose

This function creates actual Supabase authentication users.

It writes directly into:

* `auth.users`
* `auth.identities`

This bypasses the normal public signup flow.

---

### Why This Exists

The application uses:

* administrator-controlled staff provisioning,
* not self-registration.

Admins create staff accounts centrally.

---

### Email Uniqueness Check

The function first checks:

```sql id="jlwmv6"
lower(u.email) = lower(trim(p_email))
```

Meaning:

* email matching is case-insensitive.

---

### Password Hashing

Critical line:

```sql id="1jlwmh"
extensions.crypt(p_password, extensions.gen_salt('bf'))
```

This hashes passwords using bcrypt.

Important:

* plaintext passwords are never stored,
* hashing is mandatory security practice.

---

### auth.identities

Supabase requires identity provider metadata.

This row tells GoTrue:

* provider = email,
* which identity belongs to which user.

---

# RPC: create_staff_account()

---

### Purpose

Creates:

1. auth login,
2. staff member row,
3. branch assignments,
4. audit log entry.

This is a complete multi-step provisioning workflow.

---

### Authorization

Only:

* owner,
* administrator,
* bootstrap admin

may execute this RPC.

---

### Organization Setup Validation

The function blocks provisioning until:

* organization exists,
* branch setup exists.

This prevents invalid installation states.

---

### Owner Creation Restrictions

Special logic exists for `owner` role creation.

Why?

Because owners are the highest privilege users.

Rules:

* first owner requires bootstrap admin,
* later owners require an existing owner.

This prevents privilege escalation.

---

### Branch Validation

The function validates:

* every branch exists,
* belongs to the organization,
* is not deleted.

This prevents invalid foreign references.

---

### ARRAY Handling

`p_branch_ids` is a PostgreSQL UUID array.

Example:

```sql id="jlwm9z"
ARRAY['uuid1', 'uuid2']
```

The function loops through it using:

```sql id="jlwmu8"
FOREACH
```

---

### Primary Branch Validation

The primary branch must also exist inside the assignment list.

This prevents inconsistent branch state.

---

### Multi-Step Workflow

The function workflow is:

```text id="jlwmn5"
Create auth user
    ↓
Create staff member
    ↓
Create branch assignments
    ↓
Write audit log
    ↓
Return success response
```

This is effectively transactional backend orchestration.

---

### Returning Assigned Password

The password is returned once:

```json id="0jlwmq"
{
  "assigned_password": "..."
}
```

Because V1-1 has:

* no email onboarding,
* no password reset email flow.

The admin manually shares credentials.

---

# RPC: admin_reset_staff_password()

---

### Purpose

Allows administrators to reset passwords for staff members.

---

### Cross-Organization Protection

This section is critical:

```sql id="jlwm3g"
CROSS_ORG_DENIED
```

The RPC verifies:

* target staff belongs to caller’s organization.

This prevents:

* tenant boundary violations,
* cross-clinic administrative abuse.

---

### Password Update

The password is re-hashed:

```sql id="jlwm0t"
extensions.crypt(...)
```

and stored inside `auth.users`.

Again:

* plaintext passwords are never persisted.

---

### Audit Logging

Password resets are logged because:

* credential changes are sensitive operations,
* administrators must remain accountable.

---

# GRANT Statements

---

### Purpose

At the end:

```sql id="jlwm1x"
GRANT EXECUTE ON FUNCTION ...
```

allows authenticated users to call specific RPCs.

Important distinction:

* users can execute the function,
* but still cannot directly bypass function validation.

This is safer than direct table access.

---

# Architectural Summary

This migration establishes the backend application layer.

---

### JWT-Centric Authorization

Authorization context lives inside JWT claims:

* role,
* organization,
* branches,
* setup state.

RLS policies consume these claims automatically.

---

### Database-As-Backend Architecture

Instead of separate backend servers:

* PostgreSQL itself implements:

  * business logic,
  * validation,
  * orchestration,
  * authorization,
  * auditing.

This is a powerful Supabase architecture pattern.

---

### Secure Multi-Tenant Enforcement

The system carefully prevents:

* cross-organization access,
* privilege escalation,
* unauthorized provisioning.

Security exists at:

* RPC layer,
* JWT layer,
* RLS layer,
* audit layer.

---

### Controlled Privilege Escalation

SECURITY DEFINER functions intentionally bypass restrictions, but only after:

* validating caller identity,
* validating permissions,
* validating tenant scope.

This is the correct pattern for secure privileged operations.

---

### Strong Operational Traceability

Nearly all sensitive workflows create:

* audit log entries,
* actor attribution,
* historical records.

This is essential for:

* compliance,
* debugging,
* security investigations,
* operational accountability.
