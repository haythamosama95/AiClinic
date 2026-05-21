### Migration Purpose

This migration implements automatic audit tracking across the database using PostgreSQL triggers.

Its responsibility is to ensure fields like:

- `created_at`
- `updated_at`
- `created_by`
- `updated_by`

are automatically populated and maintained by the database itself.

Instead of trusting the Flutter application to correctly send audit metadata, PostgreSQL enforces it centrally.

This is an important architectural pattern because:

- frontend clients are untrusted,
- APIs may evolve,
- bugs happen,
- malicious users can manipulate requests.

By moving audit logic into the database layer, the system guarantees consistency regardless of which client performs the operation.

---

### High-Level Goal

Without this migration, every insert/update operation would require application code like:

```dart id="dn2m91"
updatedAt = DateTime.now()
updatedBy = currentUserId
```

across:

- Flutter screens,
- repositories,
- services,
- admin scripts,
- imports,
- future APIs.

That approach is fragile because developers eventually forget.

This migration changes the model to:

> “The database automatically manages audit metadata.”

The application no longer controls audit truth.

---

### Core PostgreSQL Concepts

This migration relies heavily on PostgreSQL trigger mechanics.

---

### Trigger

A trigger is code that automatically runs when database events occur.

Examples:

- before insert,
- after insert,
- before update,
- after delete.

Think of triggers as database event listeners.

Instead of application code manually invoking logic, PostgreSQL invokes it automatically when rows change.

---

### BEFORE UPDATE Trigger

A `BEFORE UPDATE` trigger runs before PostgreSQL writes the updated row.

This is important because:

- the trigger can modify the row,
- then PostgreSQL saves the modified version.

That is exactly how `updated_at` is injected automatically.

---

### Trigger Variables

Trigger functions receive special built-in variables from PostgreSQL.

Important ones here:


| Variable | Meaning                                   |
| -------- | ----------------------------------------- |
| `NEW`    | The row about to be written               |
| `OLD`    | The existing row before modification      |
| `TG_OP`  | Operation type (`INSERT`, `UPDATE`, etc.) |


These are automatically available inside trigger functions.

---

### auth.uid()

Supabase provides:

```sql id="0j70xw"
auth.uid()
```

which returns the currently authenticated user’s UUID from the JWT.

This allows PostgreSQL itself to know:

- who is performing the operation,
- without trusting frontend input.

This is one of the key integrations between:

- Supabase Auth,
- JWT claims,
- and PostgreSQL.

---

### SECURITY DEFINER

Some trigger functions use:

```sql id="bpr0mx"
SECURITY DEFINER
```

Meaning:

- the function runs with the privileges of its owner,
- not the calling user.

This is important because:

- triggers may need elevated access,
- RLS may otherwise interfere,
- and auth context must resolve safely.

However, SECURITY DEFINER functions must be carefully written because they bypass normal permission boundaries.

---

### regclass

The migration uses:

```sql id="lvhclj"
regclass
```

This is a PostgreSQL internal type representing a database table reference.

Example:

```sql id="lb0fhg"
'public.organizations'::regclass
```

Unlike plain text:

- PostgreSQL validates the table exists,
- stores the internal object identity,
- and resolves schema references safely.

This is especially useful for dynamic SQL systems.

---

### Function: set_updated_at()

This trigger function automatically updates the `updated_at` column whenever a row changes.

---

### Purpose

Goal:

> “Every update should automatically stamp the current timestamp.”

Without this function:

- developers would need to manually update timestamps,
- which inevitably becomes inconsistent.

---

### Function Definition

```sql id="mln2f9"
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
```

Important detail:

```sql id="m3m6y6"
RETURNS trigger
```

This means:

- the function is not a normal callable function,
- it is specifically designed for PostgreSQL trigger execution.

---

### Trigger Execution Flow

When a row update happens:

```text id="jlwmk3"
UPDATE query
    ↓
Trigger fires
    ↓
NEW.updated_at modified
    ↓
Modified row saved
```

---

### Updating the Timestamp

Core line:

```sql id="cq1fdz"
NEW.updated_at := now();
```

Meaning:

> “Before saving the updated row, replace updated_at with the current timestamp.”

`now()` returns the current PostgreSQL server timestamp.

---

### Returning NEW

```sql id="e0i2rx"
RETURN NEW;
```

This is mandatory in BEFORE triggers.

`NEW` represents the modified row that PostgreSQL should save.

If the function does not return `NEW`:

- the write operation fails,
- or the row is discarded.

---

### Function: set_audit_user()

This function manages:

- `created_by`
- `updated_by`
- `created_at`
- `updated_at`

depending on whether the operation is:

- INSERT
- UPDATE

---

### Why This Function Exists

The previous trigger handled only timestamps.

This function adds:

- user attribution,
- default timestamps,
- insert-specific behavior.

Together, the two triggers form a complete audit automation system.

---

### SECURITY DEFINER + search_path

The function includes:

```sql id="jdr97d"
SECURITY DEFINER
SET search_path = public
```

`search_path` controls where PostgreSQL looks for tables/functions.

Explicitly setting it prevents:

- accidental object shadowing,
- malicious search path injection,
- inconsistent object resolution.

This is considered a security best practice for SECURITY DEFINER functions.

---

### INSERT Logic

The function first checks:

```sql id="9r74je"
IF TG_OP = 'INSERT'
```

Meaning:

> “If this trigger fired during row insertion…”

---

### COALESCE()

The function uses:

```sql id="lkww2u"
COALESCE(value, fallback)
```

This means:

> “Use the first non-null value.”

Example:

```sql id="5x7u7x"
NEW.created_by := COALESCE(NEW.created_by, auth.uid());
```

Meaning:

- if `created_by` was manually supplied, keep it,
- otherwise use the logged-in user.

This provides flexibility while still guaranteeing valid audit data.

---

### INSERT Audit Flow

During insert:

- `created_by`
- `updated_by`
- `created_at`
- `updated_at`

are automatically filled if missing.

This guarantees new rows always contain complete audit metadata.

---

### UPDATE Logic

```sql id="tfr7rj"
ELSIF TG_OP = 'UPDATE'
```

On updates:

```sql id="g7y0pw"
NEW.updated_by := auth.uid();
```

Meaning:

> “Whoever performed this update becomes the updated_by user.”

The system now automatically tracks:

- who last modified the row,
- without trusting frontend input.

---

### Why created_by Is Not Modified on UPDATE

`created_by` represents historical authorship.

Changing it during updates would destroy provenance.

So:

- `created_by` remains permanent,
- `updated_by` changes over time.

---

### Function: apply_standard_audit_triggers()

This is a helper automation function.

Instead of manually attaching triggers to every table, this function dynamically creates them.

Architecturally, this is infrastructure automation inside PostgreSQL itself.

---

### Problem It Solves

Without this helper, every table would require repetitive SQL:

```sql id="0g0yhk"
CREATE TRIGGER ...
CREATE TRIGGER ...
```

repeated many times.

That causes:

- duplication,
- maintenance overhead,
- naming inconsistency,
- migration noise.

This helper centralizes the pattern.

---

### Input Parameter

```sql id="32m9vr"
p_table regclass
```

The caller passes a table reference:

```sql id="h7w0ik"
'public.organizations'::regclass
```

---

### Dynamic SQL

The function uses:

```sql id="pkwn6f"
EXECUTE format(...)
```

This is called dynamic SQL.

Normal SQL cannot parameterize table names directly.

So the function:

1. constructs SQL strings,
2. executes them dynamically.

---

### Variable Purpose

The function creates variables for:

- full table name,
- table-only name,
- generated trigger names.

Example:


| Variable       | Example                            |
| -------------- | ---------------------------------- |
| `v_table_name` | `public.organizations`             |
| `v_table_only` | `organizations`                    |
| `trg_updated`  | `trg_organizations_set_updated_at` |


---

### Why Table Name Extraction Exists

Trigger names cannot contain dots (`.`).

But schema-qualified tables do:

```text id="4d0d4w"
public.organizations
```

So the function extracts:

```text id="w3wruu"
organizations
```

using:

```sql id="5fx5sj"
split_part(...)
```

---

### Trigger Naming Convention

Generated names follow:

```text id="5iho8y"
trg_<table>_set_updated_at
trg_<table>_set_audit_user
```

Example:

```text id="w8q05m"
trg_staff_members_set_updated_at
```

Consistent naming improves:

- debugging,
- maintenance,
- observability.

---

### Dropping Existing Triggers

Before creating triggers:

```sql id="smc8kc"
DROP TRIGGER IF EXISTS
```

is executed.

Why?

Because PostgreSQL does not support:

```sql id="rww8lt"
CREATE OR REPLACE TRIGGER
```

So migrations recreate them safely.

---

### Creating the updated_at Trigger

Generated SQL becomes conceptually:

```sql id="7xjlwm"
CREATE TRIGGER trg_table_set_updated_at
BEFORE UPDATE
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at()
```

Meaning:

- every row update,
- before saving,
- automatically updates timestamp.

---

### FOR EACH ROW

Important detail:

```sql id="jlwm4y"
FOR EACH ROW
```

This means:

- trigger runs separately for every affected row.

If one query updates 500 rows:

- trigger executes 500 times.

This differs from statement-level triggers.

---

### Creating the Audit User Trigger

The second trigger attaches:

```sql id="8wns30"
public.set_audit_user()
```

and runs on:

```sql id="5gg8ep"
BEFORE INSERT OR UPDATE
```

Meaning:

- inserts populate creation metadata,
- updates refresh modification metadata.

---

### Applying Triggers to Tables

At the bottom:

```sql id="tnc0wr"
SELECT public.apply_standard_audit_triggers(...)
```

is executed repeatedly.

This applies audit automation to all major tables.

---

### Tables Receiving Audit Automation

The following tables receive automatic auditing:

- organizations
- branches
- staff_members
- staff_branch_assignments
- roles_permissions
- app_settings

Any insert/update on these tables automatically updates audit columns.

---

### Why audit_log Is Excluded

The migration intentionally excludes:

```text id="gll3ae"
audit_log
```

because the audit log itself is already the historical record.

Adding audit triggers to the audit log would create recursion problems and meaningless metadata inflation.

Example dangerous cycle:

```text id="puk9cn"
Insert audit row
    ↓
Audit trigger fires
    ↓
Creates another audit row
    ↓
Infinite recursion
```

So audit logs are typically append-only and manually controlled.

---

### Architectural Pattern Summary

This migration implements several important infrastructure patterns.

---

### Database-Enforced Audit Integrity

The database becomes the source of truth for:

- timestamps,
- authorship,
- modification tracking.

Clients cannot be trusted to provide accurate audit metadata.

---

### Centralized Cross-Table Behavior

Instead of duplicating audit logic across application code, behavior is centralized into reusable trigger functions.

This ensures:

- consistency,
- maintainability,
- lower bug risk.

---

### Dynamic Infrastructure Automation

`apply_standard_audit_triggers()` demonstrates meta-programming inside PostgreSQL.

The database dynamically generates its own infrastructure configuration.

---

### Security Through Database Ownership

Audit metadata comes from:

- `auth.uid()`
- trigger execution
- database context

not frontend requests.

This prevents spoofing attempts like:

```json id="0qmywo"
{
  "updated_by": "some_other_user"
}
```

because the database overwrites the value automatically.

---

### Defense-in-Depth

This migration contributes another security layer in the overall architecture:


| Layer         | Responsibility          |
| ------------- | ----------------------- |
| Supabase Auth | Identity                |
| JWT           | Caller context          |
| Triggers      | Audit integrity         |
| RLS           | Row authorization       |
| RPCs          | Business workflow rules |
| Constraints   | Data validity           |


Even if frontend or backend code is incorrect, the database still guarantees audit consistency.