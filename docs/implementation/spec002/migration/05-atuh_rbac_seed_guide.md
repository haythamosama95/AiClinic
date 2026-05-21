# Migration 5 of 5 — Initial Data (Permissions + Bootstrap Admin)

### What This Migration Is Responsible For

This migration does not create tables or security rules. Instead, it inserts the initial data the system needs in order to function immediately after installation.

Specifically, it does two major things:

1. Seeds the `roles_permissions` table with the default permission matrix for every role.
2. Creates the very first login account in the system: the bootstrap administrator.

This is called “seed data.” Seed data is starter data that should exist automatically in a fresh database before any user interacts with the app.

Think of migrations 1–4 as building the infrastructure:

* migration 1 created the database structure,
* migration 2 added automatic audit behavior,
* migration 3 added security policies,
* migration 4 added business logic and authentication functions.

Migration 5 finally inserts the first usable records into that infrastructure.

---

### Understanding “Seed Data”

Seed data is predefined data inserted into the database automatically during setup.

Unlike normal app data, which users create through the UI, seed data exists because the system itself requires it.

Examples in this migration:

* predefined permissions,
* predefined roles,
* the first administrator account.

Without this migration:

* no role would have permissions,
* no user could log in,
* no organization could be created.

---

### The Permission Matrix

The first large `INSERT INTO public.roles_permissions` statement defines what each role is allowed to do.

The table being populated is:

```sql
public.roles_permissions
```

Each row represents:

* a role,
* a permission,
* whether that permission is granted.

Conceptually, the table looks like this:

| Role         | Permission            | Granted |
| ------------ | --------------------- | ------- |
| owner        | patients.view         | true    |
| owner        | settings.manage_staff | true    |
| doctor       | visits.create         | true    |
| receptionist | appointments.create   | true    |

This is called a permission matrix.

---

### What Permission Keys Are

Permission keys are simple text identifiers representing actions inside the application.

Examples:

```sql
'patients.view'
'patients.create'
'settings.manage_staff'
'ai.access'
```

These strings act as contracts between:

* the Flutter frontend,
* the backend database,
* the authorization system.

For example:

* Flutter may hide a button if the user lacks `patients.edit`.
* Backend RPCs may reject operations if the user lacks `settings.manage_staff`.

Even though Flutter can hide UI elements, the backend remains the final authority.

---

### Role-by-Role Permission Design

The migration defines permissions for five roles:

| Role          | Purpose                |
| ------------- | ---------------------- |
| owner         | Full clinic control    |
| administrator | Operational management |
| doctor        | Clinical access        |
| receptionist  | Front desk operations  |
| lab_staff     | Limited read access    |

---

### Owner Permissions

The `owner` role receives nearly unrestricted access.

Examples:

* managing staff,
* managing branches,
* creating/editing patients,
* managing invoices,
* viewing analytics,
* accessing AI features.

This is effectively the highest non-system role in the application.

Example rows:

```sql
('owner', 'settings.manage_staff', true)
('owner', 'analytics.view', true)
('owner', 'ai.access', true)
```

---

### Administrator Permissions

Administrators receive almost the same permissions as owners in V1-1.

This simplifies early development because administrators can fully operate the clinic without requiring owner intervention.

Later versions could reduce administrator privileges if needed.

---

### Doctor Permissions

Doctors receive:

* patient access,
* appointment access,
* visit documentation access,
* AI access.

But they do not receive:

* branch management,
* staff management,
* analytics management.

This keeps clinical responsibilities separated from operational administration.

---

### Receptionist Permissions

Receptionists mainly handle:

* patients,
* appointments,
* invoices.

They do not receive:

* clinical editing permissions,
* staff management permissions,
* analytics permissions.

This matches the typical front-desk workflow.

---

### Lab Staff Permissions

Lab staff currently receive only:

```sql
('lab_staff', 'patients.view', true)
```

This means they can read patient information but cannot modify operational data.

The comments indicate this is intentionally minimal for V1-1.

---

### Why Future Permissions Already Exist

Some permissions reference features that do not exist yet.

Examples:

* invoices,
* visits,
* analytics.

The migration intentionally seeds them early so the permission architecture is already stable before those modules ship.

This prevents:

* schema redesign later,
* migration complexity later,
* frontend/backend mismatch later.

---

### Understanding `ON CONFLICT DO UPDATE`

The insert statement ends with:

```sql
ON CONFLICT (role, permission_key) DO UPDATE
```

This is extremely important.

Without it, rerunning the migration could fail due to duplicate rows.

The table has a unique constraint:

```sql
UNIQUE (role, permission_key)
```

Meaning:

* each role/permission pair may exist only once.

If the migration runs again:

* PostgreSQL detects the conflict,
* instead of failing, it updates the existing row.

This makes the migration idempotent.

“Idempotent” means:

> running it multiple times produces the same final result safely.

---

### What `EXCLUDED` Means

Inside:

```sql
SET is_granted = EXCLUDED.is_granted
```

`EXCLUDED` refers to:

> the row PostgreSQL attempted to insert.

So if:

```sql
('doctor', 'patients.view', true)
```

already exists,
PostgreSQL updates the existing row using the new value from the attempted insert.

---

### Why `is_deleted = false` Is Reset

The migration also does:

```sql
is_deleted = false
```

This revives soft-deleted permission rows.

Example:

* someone manually soft-deletes a permission,
* migration runs again,
* permission becomes active again.

This ensures the permission matrix always returns to the expected default state.

---

# Bootstrap Administrator Account

### Why a Bootstrap Account Exists

When the system is first installed:

* there are no users,
* no organizations,
* no branches,
* no owners.

But someone must still be able to log in and perform the first setup.

That is the purpose of the bootstrap administrator.

This account exists before the clinic organization exists.

---

### The `DO $$ ... $$` Block

This section:

```sql
DO $$
...
$$;
```

executes an anonymous PL/pgSQL script immediately.

Unlike functions:

* it is not stored permanently,
* it runs once during the migration.

Think of it as:

> “execute this setup script right now.”

---

### Variables Declared in the Script

The script declares variables:

```sql
v_user_id
v_staff_id
v_email
v_password
v_full_name
```

These act like temporary variables in programming languages.

Example:

```sql
v_email text := 'admin@clinic.local';
```

This stores the bootstrap email address.

---

### Why Fixed UUIDs Are Used

The migration uses hardcoded UUIDs:

```sql
'a0000000-0000-4000-8000-000000000001'
```

and

```sql
'b0000000-0000-4000-8000-000000000001'
```

These are intentionally stable.

Why?

Because local development environments may:

* reset,
* rebuild,
* rerun migrations.

Using fixed UUIDs guarantees:

* the same bootstrap account always exists,
* references remain stable,
* local installs behave consistently.

---

### Creating the Login Account

The migration inserts into:

```sql
auth.users
```

This is Supabase’s internal authentication table.

This creates the actual login credentials:

* email,
* password hash,
* auth metadata.

Important detail:

```sql
encrypted_password
```

does not store the plain password.

Instead:

```sql
extensions.crypt(v_password, extensions.gen_salt('bf'))
```

creates a bcrypt password hash.

This means:

* the original password is not stored,
* only the cryptographic hash is stored,
* Supabase verifies passwords by hashing future login attempts and comparing hashes.

This is standard secure authentication design.

---

### Why `email_confirmed_at` Is Set

The migration sets:

```sql
email_confirmed_at = now()
```

This bypasses email confirmation for the bootstrap account.

Otherwise:

* the user would need email verification infrastructure,
* which may not exist yet during first installation.

---

### What `auth.identities` Does

After creating the auth user, the migration inserts into:

```sql
auth.identities
```

This links the user to an authentication provider.

In this case:

* provider = `email`.

Supabase internally separates:

* users,
* identity providers.

This supports future systems like:

* Google login,
* GitHub login,
* phone login.

Even though only email/password is used now, Supabase still expects an identity row.

---

### Creating the Staff Profile

The migration then creates a row in:

```sql
public.staff_members
```

This is separate from `auth.users`.

Important distinction:

| Table         | Purpose                       |
| ------------- | ----------------------------- |
| auth.users    | Login/authentication          |
| staff_members | Clinic identity/business role |

This separation is critical.

Authentication answers:

> “Who can log in?”

`staff_members` answers:

> “Who is this person inside the clinic system?”

---

### Why the Bootstrap Flag Matters

The inserted staff member has:

```sql
is_bootstrap_admin = true
```

This is extremely important.

Earlier migrations use this flag to allow:

* organization creation before setup,
* branch creation before setup,
* initial installation workflow.

Without this flag:

* nobody could initialize the clinic.

---

### Why the Bootstrap User Is an Administrator, Not Owner

The bootstrap account is created with:

```sql
role = 'administrator'
```

not `owner`.

This is intentional.

The bootstrap admin is:

* an installation/setup actor,
* not necessarily the clinic owner.

Later, real owner accounts can be created through proper workflows.

---

### Why `IF NOT EXISTS` Is Used

The script checks:

```sql
IF NOT EXISTS (...)
```

before inserting rows.

This prevents duplicate bootstrap accounts if migrations are rerun.

Again, this supports idempotency and repeatable local development environments.

---

### The Full Startup Flow Across All Migrations

After all five migrations complete, the system works like this:

1. Database tables exist.
2. Audit triggers automatically track changes.
3. RLS policies protect data access.
4. JWT claims and RPCs implement business logic.
5. Initial permissions and bootstrap admin are inserted.

Then:

* bootstrap admin logs in,
* JWT receives `setup_required = true`,
* admin creates organization,
* admin creates first branch,
* system becomes fully operational,
* additional staff can then be provisioned securely.
