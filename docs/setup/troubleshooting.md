# Setup troubleshooting and backup expectations

Use this guide when stack validation, deployment profiles, or startup connectivity fail. It complements the operational scenarios in [deployment and networking](../../docs/architecture/03-deployment-networking.md).

## Quick diagnosis

| Symptom                               | Likely cause                         | First action                                  |
| ------------------------------------- | ------------------------------------ | --------------------------------------------- |
| Smoke script `FAIL` / unreachable     | Stack down or wrong URL              | `cd backend/local && docker compose ps`       |
| Flutter shows **Unreachable**         | Gateway down, firewall, wrong LAN IP | `curl` health URL from client PC              |
| Flutter shows **Degraded**            | Partial service failure              | `docker compose logs kong auth rest`          |
| Setup guidance screen                 | Missing/invalid profile              | Fix `deployment-profile.json` per contract    |
| Auth works on server, fails on client | `SUPABASE_PUBLIC_URL` mismatch       | Align server `.env` and client `supabase_url` |
| `401` on REST but app shows healthy   | Expected for anonymous probe         | Not a failure by itself                       |

## Stack validation commands

```bash
# Full bring-up and validation
./backend/tests/validate_local_stack.sh

# Stack already running
./backend/tests/validate_local_stack.sh --no-start

# Quick endpoint probe
./backend/tests/connectivity_smoke.sh
```

If validation times out, Kong may still be starting upstream services. Wait 30–60 seconds and retry, or inspect logs:

```bash
cd backend/local
docker compose logs -f kong auth rest postgres
```

## Deployment profile issues

### Missing profile

Error references checked paths such as `lib/core/config/deployment-profile.json`.

**Fix:** Create the file with required fields. See [client-workstation.md](./client-workstation.md).

### Invalid JSON or fields

Startup routes to **setup guidance** with a failure banner.

**Fix:**

- Ensure `deployment_mode` is exactly `local`.
- Use absolute `http://` or `https://` URLs with a host for `supabase_url`.
- Copy the full anon key from server `.env` without line breaks.

### Wrong URL on a LAN client

Profile still points at `127.0.0.1` on a remote PC.

**Fix:** Set `supabase_url` to the receptionist PC LAN gateway (for example `http://192.168.1.100:54321`).

### Environment override

```bash
export AICLINIC_DEPLOYMENT_PROFILE_PATH=/absolute/path/deployment-profile.json
```

Useful for per-machine profiles outside the repository.

## Docker and networking

### Port already in use

Change `SUPABASE_HTTP_PORT` (and related bindings) in `backend/local/.env`, restart Compose, and update every `deployment-profile.json`.

### Firewall blocks LAN clients

Open inbound TCP on the gateway port from the clinic subnet. Do not expose Postgres or Studio to all workstations unless policy requires it.

### Kong returns 502 briefly after `up`

Upstream services may still be initializing. Retry smoke tests after health stabilizes.

### Reset local data completely

```bash
cd backend/local
docker compose down -v
docker compose up -d
./../../backend/tests/validate_local_stack.sh
```

This deletes PostgreSQL and storage volumes—use only in development.

## Flutter startup

| Check   | Command                                 |
| ------- | --------------------------------------- |
| Analyze | `cd frontend && flutter analyze`        |
| Tests   | `cd frontend && flutter test`           |
| Run     | `cd frontend && flutter run -d windows` |

**Protected route blocked page** is expected without authentication—use **Return to startup** to recover.

## Local backup expectations (V1-0)

V1-0 documents expectations only; automated backup jobs are not part of this feature.

### Tier 1 — offline local (default scaffolding)

- **What to back up:** PostgreSQL data (`postgres_data` Docker volume) and file storage (`storage_data` volume).
- **How:** Periodic `pg_dump` from the server node; copy dumps to encrypted external media.
- **Frequency:** At least daily for active clinics; before upgrades and schema migrations.
- **Restore test:** Quarterly restore into a non-production Compose stack to verify dumps.

Example manual dump (server node, stack running):

```bash
cd backend/local
docker compose exec -T postgres pg_dump -U postgres postgres > "backup-$(date +%Y%m%d).sql"
```

Store dumps outside the Docker volume path.

### Tier 2 — local + cloud backup (future)

Adds encrypted upload of dumps to cloud storage. Not implemented in V1-0 scaffolding.

### What V1-0 does not provide

- Scheduled backup containers or Windows Task Scheduler jobs
- Point-in-time recovery automation
- Off-site sync verification

Track production backup implementation in later deployment features (`specs/common/deployment-installer.spec.md` when available).

## Security reminders for clinic operators

- Replace demo secrets from `.env.example` before real patient data.
- Never put `SUPABASE_SERVICE_ROLE_KEY` on client workstations.
- Restrict Studio and Postgres to administrator networks.
- Disable open sign-up before production; use provisioned accounts when auth features land.

## Escalation checklist

1. Capture output of `./backend/tests/validate_local_stack.sh`.
2. Capture `docker compose ps` and relevant `docker compose logs`.
3. Note `supabase_url` (redact anon key) and whether failure is server-only or LAN-wide.
4. Confirm checklist progress in [verification-checklist.md](./verification-checklist.md).

## Related guides

- [developer-workstation.md](./developer-workstation.md)
- [server-node.md](./server-node.md)
- [client-workstation.md](./client-workstation.md)
