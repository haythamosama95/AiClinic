# Quickstart: Project Scaffolding

This quickstart describes the intended implementation and verification flow for `V1-0: Project Scaffolding`.

## 1. Prepare the workstation

Install and verify the tools required by the active spec:

- Flutter stable with Windows desktop support enabled
- Docker for the local Supabase stack
- Supabase CLI or the repository-approved local stack wrapper

Document these steps under `docs/setup/` as part of the feature deliverable.

## 2. Initialize the desktop application foundation

Create the Flutter desktop project structure and establish the planned directories:

- `frontend/lib/app`
- `frontend/lib/core`
- `frontend/lib/shared`
- `frontend/lib/features`
- `frontend/test/unit`
- `frontend/test/widget`
- `frontend/test/integration`

Implement the shared theme, error/failure, configuration, and widget foundations before any domain workflows.

## 3. Add local deployment configuration handling

Implement startup resolution for a clinic-local deployment profile that validates:

- `deployment_mode=local`
- `supabase_url`
- `supabase_anon_key`

Missing or invalid configuration must route users to setup guidance instead of protected flows.

## 4. Prepare the local Supabase stack

Check in the local stack configuration under `backend/` and document how the receptionist PC exposes the gateway to clinic devices on the LAN.

The implementation must support:

- the receptionist PC acting as the clinic server node
- client access through the LAN-exposed Supabase gateway
- visible degraded startup behavior when the backend cannot be reached

## 5. Build the pre-auth startup experience

Implement the unauthenticated entry experience with:

- connection status visibility
- next-step/setup guidance
- guarded routing that redirects protected destinations back to the startup experience
- shared loading and error patterns

Do not expose the authenticated application shell in this feature.

## 6. Add the minimal CI/CD skeleton

Create a baseline workflow that verifies:

- lint/static analysis
- automated tests
- desktop build readiness

Keep release automation, signing, installers, and deployment promotion out of scope.

## 7. Verify acceptance

Confirm the feature using the following checks:

- Launch with a valid local deployment profile and reach the unauthenticated entry experience.
- Launch with missing or invalid configuration and confirm setup guidance appears.
- Launch with an unreachable local backend and confirm degraded status appears without exposing protected routes.
- Attempt protected navigation without auth context and confirm redirection back to the startup experience.
- Run the baseline quality commands and confirm analysis, tests, and desktop build verification all pass.
