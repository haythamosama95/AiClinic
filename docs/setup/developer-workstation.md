# Developer workstation setup

This guide prepares a machine for **local development** of AiClinic: run the clinic-local Supabase stack, configure a deployment profile, and launch the Flutter desktop startup experience.

For clinic LAN deployment (receptionist server + client PCs), also read [server-node.md](./server-node.md) and [client-workstation.md](./client-workstation.md).

For V1-1 first-time clinic setup credentials, see [bootstrap-admin.md](./bootstrap-admin.md).

## What you are building

| Role on a dev machine | Typical setup                                                                 |
| --------------------- | ----------------------------------------------------------------------------- |
| Stack host + app      | Docker Compose in `backend/local`, profile points to `http://127.0.0.1:54321` |
| App only              | Profile points at a teammate's or clinic server gateway URL                   |

## 1. Install prerequisites

Install in this order:

1. **Git** — clone `https://github.com/<org>/AiClinic` (or your fork) to a path without spaces when possible.
2. **Docker Engine** — Linux or Windows with WSL2 backend. Verify: `docker compose version`.
3. **Flutter stable** — [flutter.dev](https://docs.flutter.dev/get-started/install) with Windows desktop support:
   ```bash
   flutter config --enable-windows-desktop
   flutter doctor
   ```
4. **curl** — used by backend smoke and validation scripts.
5. **Node.js 22+** — required for `ai-platform/` (Wrangler 4.x). Use [nvm](https://github.com/nvm-sh/nvm):
   ```bash
   nvm install    # reads .nvmrc at repo root
   nvm use
   node -v        # expect v22.x
   ```

Optional: VS Code with the Dart and Flutter extensions (repository settings live in `.vscode/settings.json`).

## 2. Start the local Supabase stack

To bring up the non-Flutter development services together, run this from the
repository root:

```bash
./scripts/start-local.sh
```

The launcher starts or reuses Supabase, applies pending Supabase migrations
without resetting database data, applies the local D1 migrations, and starts
the AI Platform (AP), ABO, and AI Platform Viewer. It installs each module's
Node dependencies with `npm ci` when its `node_modules` directory is missing.
The viewer is optional (`./scripts/start-local.sh --no-viewer`). Use
`./scripts/start-local.sh status` to probe the services, and
`./scripts/start-local.sh stop` to stop the launcher-owned processes. Pressing
Ctrl-C also stops processes started by that launcher run; services that were
already running are left alone.

The launcher uses AP port 8787, ABO port 8788, and Viewer port 5173 by default.
Override them with `AI_PLATFORM_PORT`, `ABO_PORT`, and
`AI_PLATFORM_VIEWER_PORT`. It keeps Wrangler's local state under the ignored
repo-level `.wrangler/dev-stack/` directory. ABO can start with placeholder
provider/key configuration; a running service alone does not configure a
payment provider or provision production issuer keys.

For the manual Supabase-only workflow, continue with:

```bash
cd backend/local
cp -n .env.example .env    # skip if .env already exists
docker compose up -d
docker compose ps
```

From the repository root:

```bash
./backend/tests/validate_local_stack.sh
```

This starts services (unless already running), waits for the gateway, and runs [connectivity_smoke.sh](../../backend/tests/connectivity_smoke.sh).

Default ports (override in `.env`):

| Port  | Service         |
| ----- | --------------- |
| 54321 | Kong gateway    |
| 54322 | PostgreSQL      |
| 54323 | Supabase Studio |

Studio URL: `http://127.0.0.1:54323`

## 3. Configure the deployment profile

Create or edit `frontend/lib/core/config/deployment-profile.json`:

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://127.0.0.1:54321",
  "supabase_anon_key": "<copy SUPABASE_ANON_KEY from backend/local/.env>"
}
```

Copy `supabase_anon_key` from the same `.env` file the stack uses—do not invent a key.

**Profile lookup order** (first existing file wins):

1. `AICLINIC_DEPLOYMENT_PROFILE_PATH` environment variable
2. `deployment-profile.json` (current working directory)
3. `lib/core/config/deployment-profile.json` (when running from `frontend/`)
4. `frontend/lib/core/config/deployment-profile.json` (when running from repo root)

See the [deployment profile contract](../specs/001-project-scaffolding/contracts/deployment-profile.md) for field rules.

## 4. Run the Flutter app

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Expected results:

- Valid profile + running stack → unauthenticated **entry** screen with healthy connectivity.
- Valid profile + stopped stack → entry screen with **degraded** or **unreachable** status (not a crash).
- Missing/invalid profile → **setup guidance**; protected routes remain blocked.

## 5. Daily commands

| Task            | Command                                              |
| --------------- | ---------------------------------------------------- |
| Stack status    | `cd backend/local && docker compose ps`              |
| Follow logs     | `docker compose logs -f kong auth rest`              |
| Stop stack      | `docker compose down`                                |
| Reset data      | `docker compose down -v` (destroys DB volumes)       |
| Quick probe     | `./backend/tests/connectivity_smoke.sh`              |
| Full validation | `./backend/tests/validate_local_stack.sh --no-start` |

## 6. Verify setup

Work through [verification-checklist.md](./verification-checklist.md) and sign off before opening a feature branch that depends on the stack.

## Related guides

- [server-node.md](./server-node.md) — LAN exposure and receptionist PC responsibilities
- [client-workstation.md](./client-workstation.md) — clinic desktops that only run the Flutter app
- [troubleshooting.md](./troubleshooting.md) — connectivity, profile, and backup issues
