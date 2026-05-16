# Receptionist server node setup

The **server node** is the clinic PC that hosts the local Supabase stack (typically the receptionist workstation). Other clinic devices connect to this machine over the LAN through the Kong gateway on a single HTTP port.

Developers running everything on one machine can follow [developer-workstation.md](./developer-workstation.md) instead; this guide focuses on LAN-ready clinic deployment.

## Responsibilities

The server node:

1. Runs Docker Compose from `backend/local` with restart policy `unless-stopped`.
2. Exposes the Supabase gateway (`SUPABASE_HTTP_PORT`, default **54321**) to the clinic LAN.
3. Holds authoritative secrets in `backend/local/.env` (never commit `.env` to git).
4. Supplies `supabase_url` and `supabase_anon_key` values distributed to client profiles.

V1-0 does **not** include the AI service container; `ai_service_url` in profiles is optional and ignored by startup logic.

## 1. Hardware and OS

Meet the minimums in [deployment and networking](../../docs/architecture/03-deployment-networking.md):

- Windows 10/11 x64 recommended for clinic desktops.
- **8 GB RAM minimum** (16 GB recommended when Docker and the Flutter app run together).
- **20 GB free disk** for Docker images, PostgreSQL data, and file storage volumes.
- Static LAN IP for the receptionist PC (example: `192.168.1.100`).

Assign `source_device_role` in optional profile metadata:

```json
"source_device_role": "server-node"
```

## 2. Install Docker

1. Install Docker Desktop (Windows) or Docker Engine (Linux).
2. Enable automatic start on boot.
3. Verify: `docker compose version`.

## 3. Configure environment

```bash
cd backend/local
cp .env.example .env
```

Edit `.env` for clinic use:

| Variable              | Dev (single PC)            | Clinic LAN server                       |
| --------------------- | -------------------------- | --------------------------------------- |
| `SUPABASE_PUBLIC_URL` | `http://127.0.0.1:54321`   | `http://<receptionist-lan-ip>:54321`    |
| `SUPABASE_HTTP_PORT`  | `54321`                    | `54321` (or clinic-standard if changed) |
| `SUPABASE_SITE_URL`   | loopback or clinic app URL | URL clients use for auth redirects      |

`SUPABASE_PUBLIC_URL` must match what you distribute in client `deployment-profile.json` files. GoTrue reads `API_EXTERNAL_URL` from this value—mismatches cause auth redirect problems.

**Before production PHI:** replace demo JWT secrets and passwords from `.env.example`; see security notes in [troubleshooting.md](./troubleshooting.md).

## 4. Start and validate the stack

```bash
docker compose up -d
```

From repository root:

```bash
./backend/tests/validate_local_stack.sh
```

Confirm Studio locally: `http://127.0.0.1:54323` (default). Restrict Studio to admin networks in production; only the gateway must be LAN-wide.

## 5. Expose the gateway on the LAN

1. Note the receptionist PC static IP (example `192.168.1.100`).
2. Open the host firewall for inbound **TCP** on `SUPABASE_HTTP_PORT`.
3. From another LAN machine:
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' http://192.168.1.100:54321/auth/v1/health
   ```
   Expect `200` or another non-`000` response.

Do **not** expose PostgreSQL port `54322` or Studio `54323` to the general clinic LAN unless your security policy requires it for administrators only.

## 6. Distribute client configuration

Provide each client workstation with a profile (see [client-workstation.md](./client-workstation.md)):

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://192.168.1.100:54321",
  "supabase_anon_key": "<SUPABASE_ANON_KEY from server .env>",
  "source_device_role": "client-node"
}
```

Use the **same** anon key as on the server. Never distribute `SUPABASE_SERVICE_ROLE_KEY` to desktop clients.

## 7. Operate the stack

| Action     | Command                                     |
| ---------- | ------------------------------------------- |
| Status     | `docker compose ps`                         |
| Logs       | `docker compose logs -f kong auth rest`     |
| Restart    | `docker compose restart`                    |
| Stop       | `docker compose down`                       |
| Smoke test | `../../backend/tests/connectivity_smoke.sh` |

Containers use `restart: unless-stopped` so a host reboot brings services back after Docker starts.

## Service diagram

```text
Clinic LAN clients
        │
        ▼
┌───────────────────────────────┐
│ Receptionist PC (server node) │
│  Kong :54321 (public)        │
│    ├─ auth / rest / storage   │
│    └─ realtime                │
│  Postgres :54322 (admin only) │
│  Studio :54323 (admin only)   │
└───────────────────────────────┘
```

## Next steps

- Configure client PCs: [client-workstation.md](./client-workstation.md)
- Complete [verification-checklist.md](./verification-checklist.md)
- Review backups and failure handling: [troubleshooting.md](./troubleshooting.md)
