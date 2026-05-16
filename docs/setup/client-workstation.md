# Clinic client workstation setup

A **client workstation** runs the Flutter desktop app and connects to the Supabase gateway on the receptionist **server node**. It does not need Docker unless you are also developing the stack locally.

## Before you start

- Server node is running and validated — see [server-node.md](./server-node.md).
- You have the clinic gateway URL and anon key from the server operator.
- Flutter stable with Windows desktop is installed — see [developer-workstation.md](./developer-workstation.md) § prerequisites.

## 1. Install the application prerequisites

On each clinic desktop:

1. Install **Flutter stable** with Windows desktop enabled.
2. Clone or receive a deployment of the application repository (or install a packaged build when available).
3. Install **Git** if building from source.

Docker is **not** required on pure client workstations.

## 2. Create the deployment profile

Place `deployment-profile.json` using one of the supported paths:

| Run context          | Recommended path                                           |
| -------------------- | ---------------------------------------------------------- |
| From `frontend/`     | `lib/core/config/deployment-profile.json`                  |
| From repository root | `frontend/lib/core/config/deployment-profile.json`         |
| Custom location      | Set `AICLINIC_DEPLOYMENT_PROFILE_PATH` to an absolute path |

Example for a LAN client:

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://192.168.1.100:54321",
  "supabase_anon_key": "eyJ...",
  "source_device_role": "client-node"
}
```

### Field reference

| Field                | Required | Notes                                                           |
| -------------------- | -------- | --------------------------------------------------------------- |
| `deployment_mode`    | Yes      | Must be `local` in V1-0.                                        |
| `supabase_url`       | Yes      | Server gateway URL (LAN IP, not `127.0.0.1` on remote clients). |
| `supabase_anon_key`  | Yes      | Must match server `SUPABASE_ANON_KEY`.                          |
| `ai_service_url`     | No       | Reserved; startup ignores it in V1-0.                           |
| `source_device_role` | No       | `server-node` or `client-node` for documentation only.          |

Full rules: [deployment-profile contract](../../specs/001-project-scaffolding/contracts/deployment-profile.md).

## 3. Verify network access

Before launching the app, confirm the gateway responds from the client PC:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://192.168.1.100:54321/auth/v1/health
```

A timeout or `000` means firewall, wrong IP, or stopped stack—fix networking before debugging Flutter.

## 4. Launch the startup experience

```bash
cd frontend
flutter pub get
flutter run -d windows
```

Expected behavior:

| Condition                         | Startup UI                                    |
| --------------------------------- | --------------------------------------------- |
| Valid profile + gateway reachable | Entry screen, connectivity **Healthy**        |
| Valid profile + partial gateway   | Entry screen, **Degraded** notice             |
| Valid profile + gateway down      | Entry screen, **Unreachable** notice          |
| Missing/invalid profile           | **Setup guidance** (protected routes blocked) |

Protected navigation (for example `/protected/demo`) redirects back to the startup experience until authentication ships in a later feature.

## 5. Retry and environment overrides

- **Retry bootstrap** on the setup or entry screen re-runs profile load and health probes.
- Set `AICLINIC_DEPLOYMENT_PROFILE_PATH` when deploying profiles outside the repo tree (for example `C:\ProgramData\AiClinic\deployment-profile.json`).

## 6. Verify the workstation

Use the LAN client section of [verification-checklist.md](./verification-checklist.md).

## Related guides

- [server-node.md](./server-node.md) — gateway exposure and secrets on the receptionist PC
- [troubleshooting.md](./troubleshooting.md) — degraded startup and profile errors
- [developer-workstation.md](./developer-workstation.md) — full stack on one machine for development
