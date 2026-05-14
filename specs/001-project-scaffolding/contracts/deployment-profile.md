# Contract: Deployment Profile

## Purpose

Defines the minimum local settings contract required for V1-0 startup.

## Contract Shape

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://192.168.1.100:54321",
  "supabase_anon_key": "<anon-public-key>",
  "ai_service_url": "http://192.168.1.100:8090"
}
```

## Field Rules

| Field               | Required | Rule                                                           |
| ------------------- | -------- | -------------------------------------------------------------- |
| `deployment_mode`   | Yes      | Must be `local` in V1-0.                                       |
| `supabase_url`      | Yes      | Must point to the clinic LAN Supabase gateway.                 |
| `supabase_anon_key` | Yes      | Must be present before startup can proceed.                    |
| `ai_service_url`    | No       | Reserved for later features and ignored by V1-0 startup logic. |

## Validation Outcomes

- If any required field is missing, startup enters the invalid-configuration state.
- If `deployment_mode` is not `local`, startup enters the invalid-configuration state.
- If the profile is valid but the backend cannot be reached, startup enters a degraded but visible pre-auth state.

## Out of Scope

- Cloud deployment profile variants
- Authenticated user/session fields
- Any secret or server-side credential storage in the client
