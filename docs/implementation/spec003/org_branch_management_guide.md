# Understanding the Migration: Organization & Branch Management in Supabase

This migration is building a **backend business layer** for your clinic system using PostgreSQL + Supabase.

If you are coming from a frontend-only background, this file may look overwhelming because it combines:

* Database indexing
* Authentication
* Authorization
* Stored procedures (RPCs)
* Validation
* Multi-tenant security
* Audit logging
* Soft deletes
* Role-based access control (RBAC)
* Database policies
* Supabase-specific auth integration

This document explains every important concept in beginner-friendly detail.

---

# Table of Contents

1. What This File Is Actually Doing
2. High-Level Architecture
3. What is Supabase?
4. What is PostgreSQL?
5. What is a Migration?
6. Why Put Business Logic in the Database?
7. Schemas (`public`, `auth_internal`)
8. Understanding the Main Tables
9. Understanding RPC Functions
10. SECURITY DEFINER vs SECURITY INVOKER
11. Authentication Flow
12. Authorization & Permissions
13. Multi-Tenant Organization Isolation
14. Soft Deletes
15. Audit Logging
16. Deep Dive Into Every Function
17. Row Level Security (RLS) Policy
18. Public Wrappers
19. GRANT EXECUTE
20. Full End-to-End Example
21. Why This Architecture Is Strong
22. Potential Improvements
23. Important Backend Concepts You Just Learned

---

# 1. What This File Is Actually Doing

This migration creates the backend logic for:

* Updating clinic organization settings
* Creating branches
* Updating branches
* Activating/deactivating branches
* Updating staff members
* Activating/deactivating staff
* Managing role permissions

It also adds:

* Permission checking
* Security boundaries
* Organization isolation
* Audit logging
* Validation
* Database policies

This is not “just SQL”.

This is effectively a backend API implemented directly inside PostgreSQL.

---

# 2. High-Level Architecture

Your architecture likely looks like this:

```text
Flutter App
    ↓
Supabase RPC Call
    ↓
PostgreSQL Function
    ↓
Tables / Validation / Security
```

Example:

```text
Flutter:
supabase.rpc('manage_create_branch')

↓ calls

public.manage_create_branch()

↓ internally calls

auth_internal.manage_create_branch()

↓ inserts into

public.branches
```

---

# 3. What is Supabase?

Supabase is a backend platform built on top of PostgreSQL.

It gives you:

* PostgreSQL database
* Authentication
* File storage
* Realtime subscriptions
* APIs
* Row Level Security
* RPC functions

Think of Supabase as:

```text
Firebase-style backend
+
Real PostgreSQL database
```

---

# 4. What is PostgreSQL?

PostgreSQL is the actual database engine.

But PostgreSQL is much more than “just storing data”.

It supports:

* Functions
* Stored procedures
* Transactions
* Security rules
* Triggers
* JSON
* Complex queries
* Extensions

This migration heavily uses PostgreSQL's advanced capabilities.

---

# 5. What is a Migration?

A migration is a version-controlled database change.

Example:

```sql
CREATE TABLE branches (...);
```

or

```sql
CREATE FUNCTION update_branch(...);
```

Migrations are executed sequentially.

Example:

```text
V1-0
V1-1
V1-2   ← this file
```

This guarantees every developer/database gets identical schema updates.

---

# 6. Why Put Business Logic in the Database?

Traditional architecture:

```text
Frontend
  ↓
Backend API
  ↓
Database
```

Your architecture:

```text
Frontend
  ↓
Database RPC Functions
```

Advantages:

---

## Centralized Validation

Instead of validating in many clients:

```text
Flutter
Web
Desktop
Future mobile app
```

You validate once in PostgreSQL.

---

## Better Security

Even if someone bypasses Flutter and directly calls the database:

* Permissions still apply
* Validation still applies
* Organization isolation still applies

---

## Smaller Backend

You avoid building:

* Express.js APIs
* NestJS APIs
* Django APIs

The database becomes the backend.

---

# 7. Schemas (`public`, `auth_internal`)

Schemas are like folders inside PostgreSQL.

---

## `public`

Main application objects.

Examples:

```sql
public.branches
public.staff_members
public.update_branch()
```

Accessible to app users.

---

## `auth_internal`

Internal secure backend logic.

Examples:

```sql
auth_internal.update_branch()
auth_internal.assert_permission()
```

These are protected/internal functions.

---

# 8. Understanding the Main Tables

This migration references several tables.

---

## `organizations`

Represents the clinic/company.

Example:

```text
ABC Dental Group
```

Contains:

* Name
* Logo
* Currency
* Timezone
* Settings

---

## `branches`

Clinic locations.

Example:

```text
Nasr City Branch
Zayed Branch
```

Contains:

* Name
* Code
* Address
* Phone
* Active state

---

## `staff_members`

Employees/users.

Example:

```text
Doctor
Receptionist
Owner
Administrator
```

Contains:

* Full name
* Role
* Auth user ID
* Active state

---

## `staff_branch_assignments`

Links staff to branches.

Example:

```text
Doctor A → Zayed Branch
Doctor A → Nasr City Branch
```

---

## `roles_permissions`

Permission matrix.

Example:

| Role          | Permission               | Granted |
| ------------- | ------------------------ | ------- |
| receptionist  | settings.manage_branches | false   |
| administrator | settings.manage_branches | true    |

---

## `audit_log`

Stores historical changes.

Example:

```text
User X changed branch name from A to B
```

Critical for:

* Compliance
* Security
* Investigations
* Recovery

---

# 9. Understanding RPC Functions

RPC = Remote Procedure Call.

In Supabase:

```dart
await supabase.rpc('update_branch', params: {...});
```

calls a PostgreSQL function.

---

## Why RPC Instead of Direct Table Access?

Because RPC allows:

* Validation
* Security
* Transactions
* Permission checks
* Audit logging

Without RPC, frontend could directly modify tables dangerously.

---

# 10. SECURITY DEFINER vs SECURITY INVOKER

Very important concept.

---

# SECURITY INVOKER

Runs with caller permissions.

Example:

```sql
SECURITY INVOKER
```

Meaning:

```text
"Use the user's permissions."
```

---

# SECURITY DEFINER

Runs with function owner's permissions.

Example:

```sql
SECURITY DEFINER
```

Meaning:

```text
"Temporarily elevate permissions."
```

Used carefully for secure controlled operations.

---

# Why Use Both?

Pattern used here:

```text
public wrapper
    ↓
SECURITY INVOKER

calls

internal secure function
    ↓
SECURITY DEFINER
```

This is excellent architecture.

---

# 11. Authentication Flow

Supabase auth users are stored separately.

This line:

```sql
auth.uid()
```

returns current logged-in user ID.

Example:

```text
550e8400-e29b-41d4-a716-446655440000
```

The system then maps that auth user to:

```sql
public.staff_members
```

via:

```sql
sm.auth_user_id = auth.uid()
```

---

# 12. Authorization & Permissions

Authentication answers:

```text
Who are you?
```

Authorization answers:

```text
What are you allowed to do?
```

This migration implements Role-Based Access Control (RBAC).

---

# Permission Checking

Example:

```sql
PERFORM auth_internal.assert_permission('settings.manage_branches');
```

This checks whether the user has:

```text
settings.manage_branches
```

permission.

If not:

```sql
RAISE EXCEPTION 'FORBIDDEN';
```

---

# Permission Matrix

Stored in:

```sql
public.roles_permissions
```

Example:

| Role         | Permission            | Granted |
| ------------ | --------------------- | ------- |
| owner        | settings.manage_staff | true    |
| receptionist | settings.manage_staff | false   |

---

# 13. Multi-Tenant Organization Isolation

This is one of the most important backend concepts.

Your system supports multiple organizations.

Example:

```text
Clinic A
Clinic B
Clinic C
```

Each organization must NEVER access another organization’s data.

This migration enforces that everywhere.

---

# Example

```sql
WHERE b.organization_id = v_org_id
```

This guarantees:

```text
User from Clinic A
cannot update Clinic B branch
```

This is called:

```text
Tenant Isolation
```

---

# 14. Soft Deletes

Instead of deleting rows:

```sql
DELETE FROM branches
```

the system marks:

```sql
is_deleted = true
```

Why?

Because soft deletes preserve history.

Useful for:

* Recovery
* Auditing
* Compliance
* Preventing accidental data loss

---

# 15. Audit Logging

Every critical change inserts into:

```sql
public.audit_log
```

Example:

```sql
INSERT INTO public.audit_log (...)
```

The audit log stores:

* Who changed data
* What changed
* Old values
* New values
* Timestamp

This is extremely important in medical/business systems.

---

# 16. Deep Dive Into Every Function

---

# A) Unique Index

```sql
CREATE UNIQUE INDEX IF NOT EXISTS branches_organization_code_unique
```

Prevents duplicate branch codes inside same organization.

---

## Example

Allowed:

```text
Clinic A → branch code "ZAYED"
Clinic B → branch code "ZAYED"
```

Not allowed:

```text
Clinic A → "ZAYED"
Clinic A → "zayed"
```

because:

```sql
lower(trim(code))
```

normalizes values.

---

# B) `assert_permission`

Core permission enforcement function.

Steps:

1. Find current logged-in staff member
2. Ensure active and not deleted
3. Check role permissions
4. Return staff row if allowed
5. Otherwise throw `FORBIDDEN`

This is foundational security infrastructure.

---

# C) `update_organization`

Updates organization settings.

---

## Validations

### Name required

```sql
IF NULLIF(trim(p_name), '') IS NULL
```

Explanation:

```text
trim() removes spaces
NULLIF('', '') becomes NULL
```

This prevents:

```text
""
"     "
```

---

## Currency validation

```sql
^[A-Z]{3}$
```

Regex meaning:

```text
Exactly 3 uppercase letters
```

Examples:

```text
USD
EGP
EUR
```

---

## Timezone validation

Checks against PostgreSQL timezone catalog:

```sql
pg_timezone_names
```

Ensures valid timezone.

---

## Audit logging

Stores old + new organization data.

---

# D) `manage_create_branch`

Creates a branch.

---

## Key Validations

### Permission check

```sql
settings.manage_branches
```

---

### Setup completed

```sql
public.jwt_setup_required()
```

Prevents branch creation before clinic setup finishes.

---

### Branch name required

Self explanatory.

---

## Insert

```sql
INSERT INTO public.branches
```

Creates row.

---

## Audit log

Records creation.

---

## Exception Handling

```sql
WHEN unique_violation
```

Catches duplicate branch code violations.

Very important backend pattern.

---

# E) `update_branch`

Updates existing branch.

---

## Important Security

```sql
AND b.organization_id = v_org_id
```

Prevents cross-organization updates.

---

## Capturing Old State

```sql
v_old
```

Stores branch before update.

Needed for audit logging.

---

## RETURNING * INTO

```sql
RETURNING * INTO v_new;
```

Returns updated row immediately.

Very common PostgreSQL pattern.

---

# F) `set_branch_active`

Activates/deactivates branch.

---

## Critical Business Rule

Cannot deactivate last active branch.

Logic:

```sql
SELECT count(*)
```

If only one active branch remains:

```sql
RETURN error
```

This protects system integrity.

---

# G) `update_staff_member`

Most complex function in file.

Why?

Because staff management is complicated.

---

## Responsibilities

This function handles:

* Updating name
* Updating role
* Updating phone
* Updating active state
* Updating branch assignments
* Updating primary branch
* Organization validation
* Permission validation

---

# Important Concepts Here

---

## `unnest(p_branch_ids)`

Converts array into rows.

Example:

```text
[branch1, branch2]
```

becomes:

| branch_id |
| --------- |
| branch1   |
| branch2   |

---

## `FOREACH`

Loops through branch array.

```sql
FOREACH v_branch_id IN ARRAY p_branch_ids
```

Equivalent to programming loops.

---

## `ON CONFLICT`

Very important PostgreSQL feature.

Equivalent to:

```text
Insert or update
```

This is called:

```text
UPSERT
```

---

## Reactivating Soft Deleted Assignments

This logic:

```sql
is_deleted = false
deleted_at = NULL
```

restores previous assignments.

Very elegant.

---

# H) `set_staff_active`

Simple activation/deactivation.

Again uses:

* Organization checks
* Audit logging
* Permission enforcement

---

# I) `update_role_permission`

Updates permission matrix.

---

## Only Owners Allowed

```sql
v_caller.role <> 'owner'
```

Hardcoded protection.

---

## Permission Catalog Validation

Ensures permission exists before modification.

Good defensive programming.

---

# 17. Row Level Security (RLS) Policy

This section:

```sql
CREATE POLICY roles_permissions_select
```

controls SELECT access.

---

# What It Does

Normal users:

```text
Only see granted permissions
```

Owners/admins:

```text
Can see denied permissions too
```

Needed for permission matrix UI.

---

# Why RLS Matters

Without RLS:

```text
Any authenticated user
might read sensitive rows
```

RLS is one of Supabase/Postgres strongest security features.

---

# 18. Public Wrappers

These functions:

```sql
public.update_branch()
```

are wrappers around:

```sql
auth_internal.update_branch()
```

Pattern:

```text
Public safe API
    ↓
Internal secure implementation
```

Excellent architecture.

---

# Why Not Expose Internal Functions Directly?

Because internal functions:

* Have elevated privileges
* Contain sensitive logic
* Should not be directly callable

---

# 19. GRANT EXECUTE

Example:

```sql
GRANT EXECUTE ON FUNCTION public.update_branch TO authenticated;
```

Meaning:

```text
Logged-in users may call this function.
```

Without this:

```text
Permission denied
```

---

# 20. Full End-to-End Example

Suppose receptionist updates branch.

---

# Step 1 — Flutter

```dart
await supabase.rpc('update_branch', params: {...});
```

---

# Step 2 — Public Wrapper

```sql
public.update_branch()
```

calls:

```sql
auth_internal.update_branch()
```

---

# Step 3 — Permission Check

```sql
assert_permission('settings.manage_branches')
```

---

# Step 4 — Organization Validation

Ensures branch belongs to clinic.

---

# Step 5 — Validation

Checks:

* Name not empty
* Duplicate code not used

---

# Step 6 — Database Update

```sql
UPDATE public.branches
```

---

# Step 7 — Audit Log

Stores old/new values.

---

# Step 8 — RPC Response

Returns:

```json
{
  "success": true,
  "branch_id": "..."
}
```

---

# 21. Why This Architecture Is Strong

This is actually a very solid architecture.

Strengths:

---

## Security-Centric

Security exists inside database itself.

Not dependent on frontend honesty.

---

## Multi-Tenant Safe

Organization isolation enforced everywhere.

---

## Auditability

Every important action logged.

---

## Centralized Business Rules

Rules live in one place.

---

## Minimal Backend Infrastructure

No large Node.js backend required.

---

## Consistent APIs

All clients use same RPC layer.

---

# 22. Potential Improvements

Even strong architectures can improve.

---

## A) Transactions Around Complex Operations

Some functions update multiple tables.

Could explicitly use transactions for clarity.

(PostgreSQL functions are already transactional by default, but explicit design docs help.)

---

## B) Permission Constants

Permission strings:

```sql
'settings.manage_staff'
```

could eventually become centralized constants.

---

## C) More Granular Audit Logs

Currently some logs only store partial data.

Could store full before/after snapshots.

---

## D) Validation Utilities

Repeated validation patterns could become reusable helper functions.

---

# 23. Important Backend Concepts You Just Learned

You were exposed to many real backend engineering concepts here.

---

## Database Concepts

* Tables
* Indexes
* Unique constraints
* Transactions
* Functions
* Schemas
* Policies

---

## Security Concepts

* Authentication
* Authorization
* RBAC
* Tenant isolation
* RLS
* Elevated privileges

---

## Backend Architecture Concepts

* RPC APIs
* Service layer
* Audit logging
* Soft deletes
* Validation
* UPSERTs

---

# Final Mental Model

Think of this migration as:

```text
A complete secure backend module
implemented directly inside PostgreSQL
using Supabase RPC architecture.
```

The Flutter frontend is only a client.

The actual business authority lives in the database layer.
