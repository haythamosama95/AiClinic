# Backend

- Purpose: Describe the Supabase-based backend boundary, ownership rules, and API access patterns.
- Read this when: implementing backend-facing logic, deciding whether a rule belongs in PostgreSQL or Flutter, or reviewing Supabase access patterns.
- Canonical for: Supabase responsibilities, business logic placement, edge-function boundaries, and SDK usage patterns.
- Usually paired with: `docs/architecture/05-database.md`, `docs/architecture/09-security-rbac.md`, and the feature spec being implemented.
- Not covered here: frontend state management, deployment topology, or roadmap sequencing.

---

## Backend Architecture

### Backend = Supabase

There is no custom backend server. Supabase provides the entire backend:

| Supabase Component | Role in This System                                                                                                                      |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **GoTrue (Auth)**  | User authentication, JWT token issuance, session management, password resets                                                             |
| **PostgREST**      | Auto-generated REST API from the database schema. Handles CRUD for all tables. Enforces RLS on every request.                            |
| **PostgreSQL RPC** | Complex business logic exposed as database functions callable via `supabase.rpc()`. This is the primary mechanism for domain operations. |
| **Storage API**    | File uploads/downloads for visit attachments (PDFs, scans, lab reports, examination documents)                                           |
| **Realtime**       | WebSocket subscriptions for live UI updates (appointment queue changes, new patient check-ins)                                           |
| **RLS Policies**   | Row-level authorization. Every table has policies that restrict access based on the authenticated user's organization, branch, and role. |

### Business Logic Distribution

Business logic is distributed across two locations, with clear ownership rules:

#### PostgreSQL Functions (via RPC) -- Source of Truth for Domain Rules

These functions ARE the backend business logic. They run inside PostgreSQL and are invoked via `supabase.rpc('function_name', params)`.

Responsibilities:
- Appointment conflict detection and creation
- Invoice generation and validation
- Shift overlap validation and creation
- Visit creation linked to appointments
- Patient deduplication checks
- Permission-gated discount application
- Any operation requiring atomicity or sequential consistency

Design rules:
- Every domain write operation that requires validation has a corresponding PostgreSQL function.
- Functions accept parameters, validate, and return structured results (success/error).
- Functions are defined in SQL migration files, versioned alongside the schema.
- Functions run within a transaction, ensuring atomicity.

#### Flutter Service Layer -- Orchestration and UI Logic

Responsibilities:
- Multi-step workflow orchestration (e.g., "create visit" that calls the RPC, then navigates to SOAP form)
- Client-side pre-validation (field presence, format checks) for fast UX feedback
- Composing multiple RPC calls into a logical user action
- Caching and optimistic UI updates
- Error handling and user-facing error mapping

The Flutter service layer NEVER contains canonical business rules. If a rule matters for data integrity, it lives in a PostgreSQL function.

### Supabase Edge Functions (Cloud-Only, Optional)

For Tier 3 (cloud-connected) deployments, Supabase Edge Functions (Deno-based serverless functions) may be used for:

- Webhook receivers (e.g., incoming WhatsApp status callbacks)
- Scheduled jobs (e.g., subscription validation, overdue invoice checks)
- Third-party API integrations that require server-side secrets

Edge Functions are NOT used for core business logic. They are supplementary. The system must function fully without them (Tier 1/2 proof).

### API Access Patterns

Flutter interacts with Supabase through these patterns:

| Pattern                                    | When to Use                                        | Example                               |
| ------------------------------------------ | -------------------------------------------------- | ------------------------------------- |
| `supabase.from('table').select()`          | Simple reads with RLS filtering                    | Fetch patient list for current branch |
| `supabase.from('table').insert()`          | Simple inserts where DB constraints are sufficient | Create a new patient record           |
| `supabase.rpc('function_name', params)`    | Complex operations requiring validation logic      | Book appointment with conflict check  |
| `supabase.storage.from('bucket').upload()` | File operations                                    | Upload visit attachment (scan PDF)    |
| `supabase.auth.signIn()`                   | Authentication                                     | Staff login                           |
| `supabase.channel('topic').on(...)`        | Realtime subscriptions                             | Listen for appointment queue changes  |

---
