# Quickstart: Project Scaffolding

This quickstart describes the implementation and verification flow for `V1-0: Project Scaffolding`. Detailed workstation guides live under [`docs/setup/`](../../docs/setup/).

## 1. Prepare the workstation

Follow the guide that matches your role:

| Role                                   | Guide                                                                 |
| -------------------------------------- | --------------------------------------------------------------------- |
| Developer (stack + app on one machine) | [developer-workstation.md](../../docs/setup/developer-workstation.md) |
| Receptionist / server node             | [server-node.md](../../docs/setup/server-node.md)                     |
| Clinic desktop (app only)              | [client-workstation.md](../../docs/setup/client-workstation.md)       |

**Prerequisites:** Flutter stable (Windows desktop), Docker Engine, Git, and `curl`.

Sign off with [verification-checklist.md](../../docs/setup/verification-checklist.md) when setup is complete.

## 2. Initialize the desktop application foundation

The Flutter desktop scaffold and directory layout are checked in under `frontend/`:

- `frontend/lib/app`
- `frontend/lib/core`
- `frontend/lib/shared`
- `frontend/lib/features`
- `frontend/test/unit`, `widget`, `integration`

Shared theme, error/failure, configuration, and widget foundations are in place for startup and later features.

## 3. Add local deployment configuration handling

Startup loads `deployment-profile.json` per [contracts/deployment-profile.md](./contracts/deployment-profile.md).

Required fields:

- `deployment_mode` = `local`
- `supabase_url` — Kong gateway (loopback for dev, LAN IP for clinic clients)
- `supabase_anon_key` — matches `SUPABASE_ANON_KEY` on the server node

Missing or invalid configuration routes to setup guidance instead of protected flows.

**Profile paths** (first match wins): `AICLINIC_DEPLOYMENT_PROFILE_PATH`, then `deployment-profile.json`, `lib/core/config/deployment-profile.json`, `frontend/lib/core/config/deployment-profile.json`.

## 4. Prepare the local Supabase stack

Stack configuration: `backend/local/` (Docker Compose).

```bash
cd backend/local
cp -n .env.example .env
docker compose up -d
```

Validate from repository root:

```bash
./backend/tests/validate_local_stack.sh
./backend/tests/connectivity_smoke.sh
```

**Clinic LAN:** set `SUPABASE_PUBLIC_URL` on the server to the receptionist PC LAN address, open firewall for `SUPABASE_HTTP_PORT`, and distribute matching `supabase_url` / `supabase_anon_key` in client profiles. See [server-node.md](../../docs/setup/server-node.md).

## 5. Build the pre-auth startup experience

Implemented under `frontend/lib/features/startup/`:

- Connection status on the unauthenticated entry screen
- Setup guidance when the profile is missing or invalid
- Guarded routing that redirects protected destinations to startup
- Degraded/unreachable states when the backend is down or partial

The authenticated application shell is out of scope for V1-0.

## 6. Add the minimal CI/CD skeleton

Planned in User Story 3: baseline workflow for analyze, tests, and Windows build verification (`.github/workflows/ci.yml`). Not required to validate User Story 2.

## 7. Verify acceptance

### User Story 1 — safe pre-auth entry

- Launch with a valid local deployment profile and reach the unauthenticated entry experience.
- Launch with missing or invalid configuration and confirm setup guidance appears.
- Launch with an unreachable local backend and confirm degraded status without exposing protected routes.
- Attempt protected navigation without auth context and confirm redirection to startup.

```bash
cd frontend && flutter test
```

### User Story 2 — repeatable workstation setup

- A new operator completes [verification-checklist.md](../../docs/setup/verification-checklist.md) using only linked guides.
- `./backend/tests/validate_local_stack.sh` exits successfully with the stack running.
- Client and server profiles use consistent gateway URL and anon key.

### Quality gates (when CI is added)

```bash
cd frontend && flutter analyze && flutter test
```

For setup failures, see [troubleshooting.md](../../docs/setup/troubleshooting.md).
