### Migration Purpose

This migration defines the foundational database schema for the AiClinic application. It creates:

* database extensions,
* custom data types,
* all core tables,
* indexes,
* and enables Row Level Security (RLS).

Architecturally, this file establishes the application’s:

* tenant model,
* authentication linkage,
* RBAC structure,
* branch assignment system,
* audit infrastructure,
* settings storage,
* and subscription state model.

This migration is effectively the “physical data model” of the system.

---

### What Is a Migration?

A migration is a versioned database change script.

Think of migrations like Git commits for the database schema.

Instead of modifying the database manually, the schema evolves through ordered SQL files.

Supabase runs migrations:

* in filename order,
* exactly once,
* and records which migrations were already applied.

This gives:

* reproducibility,
* version control,
* rollback history,
* and consistent environments across machines.

---

### High-Level Architecture

This schema implements a multi-layered clinic authorization structure.

The hierarchy looks like this:

```text id="mjjfhk"
Organization
    ↓
Branches
    ↓
Staff Members
    ↓
Branch Assignments
    ↓
Permissions
```

And alongside that:

```text id="wqg75t"
Audit Logs
App Settings
Subscription Cache
```

The schema is heavily designed around:

* RBAC (Role-Based Access Control),
* tenant isolation,
* and security-first architecture.

---

### PostgreSQL Concepts Used

Before examining tables, several PostgreSQL concepts appear throughout the migration.

---

### PostgreSQL

PostgreSQL is the relational database engine used by Supabase.

It provides:

* tables,
* indexes,
* SQL execution,
* transactions,
* triggers,
* stored procedures,
* RLS,
* and advanced JSON support.

Supabase is fundamentally PostgreSQL plus managed infrastructure.

---

### Schemas

A schema is like a namespace or folder.

Examples in this system:

| Schema       | Purpose                        |
| ------------ | ------------------------------ |
| `public`     | Application tables             |
| `auth`       | Supabase authentication system |
| `extensions` | PostgreSQL extensions          |

The application data primarily lives in `public`.

---

### UUIDs

Most tables use:

```sql id="xdy56n"
uuid PRIMARY KEY DEFAULT gen_random_uuid()
```

UUID = Universally Unique Identifier.

Example:

```text id="07i0j0"
550e8400-e29b-41d4-a716-446655440000
```

Compared to auto-increment integers, UUIDs:

* are globally unique,
* are safer for distributed systems,
* avoid predictable IDs,
* and reduce enumeration attacks.

This is especially important in APIs.

---

### Soft Deletes

Most tables contain:

```sql id="k5u8dh"
is_deleted boolean
deleted_at timestamptz
deleted_by uuid
```

Instead of physically deleting rows, the system marks them deleted.

Advantages:

* recoverability,
* auditability,
* historical integrity,
* safer operations.

RLS policies later hide soft-deleted rows.

---

### JSONB

Several columns use:

```sql id="r59r4v"
jsonb
```

`jsonb` is PostgreSQL’s binary JSON type.

Unlike plain text JSON:

* it is queryable,
* indexable,
* validated,
* and optimized.

This allows flexible structured configuration without schema changes.

---

### Extension: pgcrypto

```sql id="u1x9x4"
CREATE EXTENSION IF NOT EXISTS pgcrypto
```

PostgreSQL extensions add extra capabilities.

`pgcrypto` provides:

* cryptographic functions,
* hashing,
* random UUID generation,
* bcrypt password hashing.

This migration later uses:

* `gen_random_uuid()`
* `crypt()`

for secure identity handling.

---

### ENUM: staff_role

The migration defines a PostgreSQL ENUM:

```sql id="fp4yq8"
CREATE TYPE public.staff_role AS ENUM (...)
```

An ENUM is a fixed list of allowed values.

Valid roles:

* owner
* administrator
* doctor
* receptionist
* lab_staff

PostgreSQL will reject any value outside this list.

This is important because it:

* prevents invalid roles,
* centralizes role consistency,
* and improves type safety.

Without ENUMs, role values could become inconsistent strings like:

* `"admin"`
* `"Admin"`
* `"administrator"`

---

### Role Hierarchy

The roles imply increasing privilege levels.

---

### owner

Highest privilege level.

Likely responsible for:

* organization ownership,
* billing,
* top-level administration.

---

### administrator

Operational management role.

Can likely manage:

* staff,
* branches,
* settings.

---

### doctor

Clinical access role.

Likely focused on:

* patient records,
* treatment workflows.

---

### receptionist

Front-desk role.

Likely focused on:

* appointments,
* intake,
* scheduling.

---

### lab_staff

Restricted operational role.

Likely intended for:

* test results,
* limited patient visibility.

---

### COMPOSITE TYPE: rpc_result

```sql id="g94vca"
CREATE TYPE public.rpc_result AS (...)
```

This defines a reusable structured response format for RPC functions.

Instead of every function returning different JSON shapes, all RPCs share one contract.

Fields:

* `success`
* `data`
* `error_code`
* `error_message`

This standardizes communication between:

* PostgreSQL,
* Supabase RPCs,
* and Flutter.

It acts similarly to API response DTOs in backend frameworks.

---

### Table: organizations

This table represents the clinic organization.

Architecturally, it is the tenant root.

Almost all data in the system eventually belongs to an organization.

---

### Organization Structure

Important fields:

| Column              | Purpose                        |
| ------------------- | ------------------------------ |
| `name`              | Clinic display name            |
| `logo_url`          | Branding asset                 |
| `currency_code`     | ISO currency                   |
| `timezone`          | Regional timezone              |
| `subscription_tier` | Billing plan                   |
| `settings_json`     | Flexible organization settings |

---

### Subscription Metadata

Fields like:

* `subscription_tier`
* `subscription_valid_until`

prepare the system for subscription billing.

The schema is designed to support:

* plan upgrades,
* expiration,
* entitlement checks.

---

### Audit Metadata

Most tables share:

```sql id="6n7v44"
created_at
created_by
updated_at
updated_by
```

These provide operational traceability.

This becomes very important in:

* healthcare systems,
* compliance workflows,
* security investigations.

---

### Table: branches

Branches represent physical or logical clinic locations.

Examples:

* Main Branch
* North Clinic
* Downtown Lab

Each branch belongs to one organization:

```sql id="g1lq6n"
organization_id REFERENCES public.organizations(id)
```

This is a foreign key relationship.

---

### Foreign Keys

A foreign key means:

> “This value must exist in another table.”

PostgreSQL enforces referential integrity automatically.

This prevents orphaned records.

Example:

* a branch cannot reference a non-existent organization.

---

### Branch Activity

```sql id="lgy4s8"
is_active boolean
```

Inactive branches are hidden operationally without deletion.

This differs from soft delete:

* inactive = temporarily disabled,
* deleted = logically removed.

---

### Branch Index

```sql id="zw92z1"
CREATE INDEX branches_organization_id_idx
```

Indexes accelerate queries.

Without an index:

* PostgreSQL scans every row.

With an index:

* PostgreSQL can quickly locate matching rows.

This index optimizes queries like:

```sql id="kkj7pa"
WHERE organization_id = ?
```

which are extremely common in multi-tenant systems.

---

### Table: staff_members

This table links:

* authentication identities,
* to clinic identities.

Supabase Auth manages login accounts in:

```sql id="4knxw4"
auth.users
```

But the application still needs:

* role,
* full name,
* clinic permissions,
* operational metadata.

That is what `staff_members` provides.

---

### auth_user_id

```sql id="w06xod"
auth_user_id uuid UNIQUE REFERENCES auth.users(id)
```

This creates a 1-to-1 relationship:

* one login account,
* one staff profile.

The UNIQUE constraint guarantees this.

---

### Bootstrap Admin

```sql id="3owp9e"
is_bootstrap_admin
```

This special flag identifies the first installer.

The bootstrap admin exists to solve first-time setup flows before:

* organizations,
* branches,
* or owners

exist yet.

This role is temporary infrastructure bootstrap authority.

---

### Table: staff_branch_assignments

This table creates a many-to-many relationship.

Meaning:

* one staff member can belong to multiple branches,
* one branch can contain multiple staff members.

---

### Why a Join Table Exists

Without this table:

* staff could only belong to one branch.

But clinics often require:

* rotating doctors,
* shared administrators,
* cross-location support.

So assignments are normalized into a separate table.

---

### Primary Branch

```sql id="d5twf8"
is_primary
```

Defines the user’s default branch.

This likely supports:

* initial UI context,
* dashboard defaults,
* scheduling defaults.

---

### UNIQUE Constraint

```sql id="96j0u0"
UNIQUE (staff_member_id, branch_id)
```

Prevents duplicate assignments.

Without this:

* the same staff member could accidentally be assigned repeatedly to the same branch.

---

### Assignment Indexes

Indexes exist for:

* `staff_member_id`
* `branch_id`

These optimize:

* branch lookups,
* staff lookups,
* authorization joins.

---

### Table: roles_permissions

This table defines the RBAC permission matrix.

Structure:

```text id="d4g31j"
Role → Permission Key → Granted?
```

Example:

| Role          | Permission            |
| ------------- | --------------------- |
| administrator | settings.manage_staff |
| doctor        | patients.view         |

---

### Why Store Permissions in DB?

This design allows:

* dynamic permission systems,
* UI-driven authorization,
* future admin customization.

Instead of hardcoding permissions into Flutter, the app can query them dynamically.

---

### is_granted

Currently mostly redundant because rows already represent permissions.

But it allows future features like:

* explicit denies,
* partial overrides,
* inheritance systems.

---

### Table: audit_log

This table stores immutable historical actions.

Examples:

* user creation,
* password reset,
* organization bootstrap.

Audit systems are critical in healthcare-related applications.

---

### Append-Only Design

The table is intended to be append-only.

Meaning:

* rows are inserted,
* never modified.

This preserves historical integrity.

---

### Audit Structure

Important fields:

| Field           | Meaning              |
| --------------- | -------------------- |
| `user_id`       | Who performed action |
| `action`        | Operation identifier |
| `table_name`    | Affected table       |
| `record_id`     | Affected row         |
| `old_data_json` | Previous state       |
| `new_data_json` | New state            |

---

### Snapshot JSON

Using JSON snapshots allows:

* flexible auditing,
* schema-independent history,
* easier forensic analysis.

---

### Audit Indexes

Indexes optimize:

* recent activity feeds,
* organization-scoped audit queries.

Especially:

```sql id="x7e5mj"
timestamp DESC
```

helps recent-event retrieval.

---

### Table: app_settings

This table stores application configuration.

It supports:

* organization-wide settings,
* branch-specific overrides.

---

### Branch-Scoped Configuration

```sql id="36b8m5"
branch_id NULL
```

means:

* organization default setting.

Otherwise:

* branch-specific override.

This creates hierarchical configuration resolution.

---

### value_json

Settings use JSON because settings vary greatly.

Examples:

* UI configuration,
* scheduling rules,
* feature flags,
* integrations.

JSON avoids endless schema changes.

---

### Table: subscription_cache

This table stores cached subscription information.

The design intentionally separates:

* operational app access,
* from live billing provider availability.

Important note from comments:

> Login must NOT fail if cache is stale.

This is a resilience decision.

The clinic system should continue functioning even if:

* Stripe,
* billing APIs,
* or subscription verification services

are temporarily unavailable.

---

### ON DELETE CASCADE

```sql id="k0bm9q"
REFERENCES organizations(id) ON DELETE CASCADE
```

Meaning:

> If organization is deleted, automatically delete subscription cache row too.

This prevents orphaned dependent data.

---

### Enabling Row Level Security (RLS)

At the end:

```sql id="n2h4qf"
ALTER TABLE ... ENABLE ROW LEVEL SECURITY;
```

This is one of the most important security features in PostgreSQL.

Once enabled:

> No rows are visible or writable unless policies explicitly allow them.

Default behavior becomes:

* deny all access.

Migration 3 later defines the actual policies.

---

### Defense-in-Depth Security

This architecture intentionally layers security:

| Layer                | Responsibility               |
| -------------------- | ---------------------------- |
| Supabase Auth        | Authentication               |
| JWT Claims           | Identity metadata            |
| RLS Policies         | Row authorization            |
| RPC Functions        | Business workflow validation |
| Database Constraints | Data integrity               |

Even if:

* frontend code is compromised,
* API calls are manipulated,
* or backend validation has bugs,

PostgreSQL still enforces row-level protection.

---

### Overall Architectural Design

This schema reveals several strong architectural decisions.

---

### Multi-Tenant Ready

Even though V1-1 supports one organization per installation, the schema is already tenant-oriented.

Most major entities:

* branch,
* settings,
* audit logs,
* subscription state

connect back to organizations.

---

### Security-First Design

Security is embedded into the schema itself:

* UUIDs,
* RLS,
* soft deletes,
* audit logs,
* RBAC,
* permission tables,
* auth linkage.

---

### Highly Normalized Structure

Data is separated into focused tables:

* staff,
* assignments,
* permissions,
* organizations,
* settings.

This reduces duplication and improves consistency.

---

### Operational Auditability

The system is designed for traceability:

* who created records,
* who modified them,
* what changed,
* when changes happened.

This is especially important for medical/business systems.

---

### Backend-in-Database Philosophy

The schema strongly suggests a database-centric architecture where PostgreSQL is not merely storage.

It acts as:

* authorization engine,
* workflow engine,
* audit system,
* identity coordinator,
* and business rules platform.
