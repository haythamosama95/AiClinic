# Contract: Deployment Profile

## Purpose

Defines the minimum local settings contract required for V1-0 startup. Setup guides and validation scripts must stay aligned with this contract.

**Documentation:** [developer-workstation.md](../../../docs/setup/developer-workstation.md), [client-workstation.md](../../../docs/setup/client-workstation.md), [server-node.md](../../../docs/setup/server-node.md)

## Contract shape

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://192.168.1.100:54321",
  "supabase_anon_key": "<anon-public-key>",
  "ai_service_url": "http://192.168.1.100:8090",
  "source_device_role": "client-node"
}
```

## Field rules

| Field                | Required | Rule                                                                   |
| -------------------- | -------- | ---------------------------------------------------------------------- |
| `deployment_mode`    | Yes      | Must be `local` in V1-0.                                               |
| `supabase_url`       | Yes      | Absolute `http://` or `https://` URL for the clinic Kong gateway.      |
| `supabase_anon_key`  | Yes      | Public anon JWT from server `SUPABASE_ANON_KEY`; required for startup. |
| `ai_service_url`     | No       | Reserved for later features; ignored by V1-0 startup logic.            |
| `source_device_role` | No       | `server-node` or `client-node` for documentation; not enforced.        |

## Profile discovery

The Flutter client resolves the first existing file in this order:

1. Path in `AICLINIC_DEPLOYMENT_PROFILE_PATH`
2. `deployment-profile.json` (process working directory)
3. `lib/core/config/deployment-profile.json` (typical when running from `frontend/`)
4. `frontend/lib/core/config/deployment-profile.json` (typical when running from repo root)

Reference implementation: `frontend/lib/core/config/deployment_profile.dart`

## Environment examples

**Developer (stack on same machine):**

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://127.0.0.1:54321",
  "supabase_anon_key": "<from backend/local/.env>"
}
```

**Clinic LAN client:**

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://192.168.1.100:54321",
  "supabase_anon_key": "<same as server SUPABASE_ANON_KEY>",
  "source_device_role": "client-node"
}
```

Server `.env` field `SUPABASE_PUBLIC_URL` must use the same host and port as client `supabase_url`.

## Validation outcomes

- If any required field is missing, startup enters the invalid-configuration state (setup guidance).
- If `deployment_mode` is not `local`, startup enters the invalid-configuration state.
- If the profile is valid but the backend cannot be reached, startup enters a degraded but visible pre-auth state.
- If some probes succeed and others fail, startup shows **degraded** partial availability.

## Stack alignment

| Profile field       | Server source                                 |
| ------------------- | --------------------------------------------- |
| `supabase_url`      | `SUPABASE_PUBLIC_URL` in `backend/local/.env` |
| `supabase_anon_key` | `SUPABASE_ANON_KEY` in `backend/local/.env`   |

Validate the stack before blaming the profile:

```bash
./backend/tests/validate_local_stack.sh
```

## Out of scope

- Cloud deployment profile variants
- Authenticated user/session fields
- `service_role` or other server-side secrets on client devices
- Installer-driven first-run profile creation (later deployment feature)
