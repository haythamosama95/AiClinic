# Glossary

- Purpose: Keep shared platform and architecture terminology consistent across documents and specs.
- Read this when: you need a precise shared definition for an architecture term used across multiple docs or specs.
- Canonical for: shared terminology used throughout the architecture set.
- Usually paired with: any architecture document that uses the term in question.
- Not covered here: implementation steps, feature requirements, or roadmap sequencing.

---

## Glossary

| Term                     | Definition                                                                                                                                     |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **PostgREST**            | An auto-generated REST API layer from a PostgreSQL schema. Part of Supabase.                                                                   |
| **RLS**                  | Row Level Security. PostgreSQL feature that restricts which rows a user can access, enforced at the database level.                            |
| **RPC**                  | Remote Procedure Call. In this context, calling PostgreSQL functions via `supabase.rpc()`.                                                     |
| **GoTrue**               | Supabase's authentication service. Handles sign-up, sign-in, JWT issuance.                                                                     |
| **JWT**                  | JSON Web Token. Used for stateless authentication between Flutter and Supabase.                                                                |
| **Ollama**               | A local AI inference runtime that supports running LLMs on CPU without GPU.                                                                    |
| **SOAP**                 | Subjective, Objective, Assessment, Plan. A medical documentation format.                                                                       |
| **GGUF**                 | A model file format used by llama.cpp and Ollama for quantized model weights.                                                                  |
| **WAL**                  | Write-Ahead Logging. PostgreSQL durability mechanism that ensures data survives crashes.                                                       |
| **Kong**                 | API gateway used by self-hosted Supabase as the single entry point for all services.                                                           |
| **auth_internal**        | Private PostgreSQL schema holding SECURITY DEFINER business logic. Not exposed via PostgREST.                                                  |
| **Bootstrap Admin**      | The first staff account (seeded in migrations) with `is_bootstrap_admin = true`. Can create the organization and first branch.                 |
| **Deployment Profile**   | A JSON file (`deployment-profile.json`) defining the Supabase URL, anon key, AI service URL, and device role for the Flutter app.              |
| **rpc_result**           | PostgreSQL composite type `(success boolean, data jsonb, error_code text, error_message text)` returned by all domain RPC functions.           |
| **Username**             | Staff login identifier stored in GoTrue's `email` field. No `@` allowed; 3–32 chars, `[a-z0-9_-]`.                                             |
| **Idle Timeout**         | Configurable inactivity timer that auto-signs-out the staff user from the workstation (default 15 minutes).                                    |
| **Working schedule**     | JSON on `branches.working_schedule` defining per-weekday open/close times. Required for branch create/update; appointments must fit within it. |
| **Phone confirmation**   | Reception advances a planned appointment from `scheduled` to `confirmed` after calling the patient; required before check-in in V1-4.          |
| **Branch slot conflict** | V1-4 rule: no overlapping appointment times at the same branch regardless of doctor assignment (enforced in `appointment_has_overlap`).        |
| **Encounter workspace**  | Spec 014 UI shell: phased visit documentation (Intake → Findings → Treatment → Summary) with stepper and expert accordion modes.               |
| **visit_clinical_notes** | Sectioned clinical documentation table (`complaint`, `history`, `examination`, `diagnosis`, `plan`); replaced legacy `soap_notes`.              |
| **EmptyLocalStorage**    | Supabase Flutter auth storage adapter that never persists sessions to disk — staff must sign in on every app launch.                            |
| **Deferred attachment**  | Pattern: file held in `VisitEncounterDraft` until save; then Storage upload + `register_visit_attachment` RPC. |
| **ForUI**                | Third-party Flutter UI kit integrated via `core/ui/theme/forui_theme.dart` alongside custom `App*` components. |
| **Expert mode**          | Encounter workspace accordion layout toggled via `workspace_mode_provider`; preference cached per staff in SharedPreferences. |
| **STALE_DOCUMENTATION**  | RPC error when `save_visit_documentation` detects `updated_at` mismatch (optimistic concurrency). |
| **uiPendingPlaceholder** | Router pattern rendering "coming soon" shell for routes whose presentation layer is not yet built (billing, shifts). |
| **Bootstrap finish setup** | Atomic RPC `bootstrap_finish_setup` provisioning org, branch, and initial staff in one transaction via `features/setup/`. |
