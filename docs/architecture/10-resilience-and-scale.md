# Resilience and Scale

- Purpose: Describe backup policy, subscription validation, failure recovery, and scalability boundaries.
- Read this when: working on backup/restore, offline behavior, failure handling, subscription enforcement, or scaling assumptions.
- Canonical for: backup strategy, resilience expectations, failure modes, and operational data integrity guarantees.
- Usually paired with: `docs/architecture/03-deployment-networking.md`, `docs/architecture/04-backend.md`, and relevant deployment or analytics specs.
- Not covered here: feature-specific UI structure or low-level domain modeling outside resilience concerns.

---

## Sync and Data Resilience

### Backup Strategy by Tier

#### Tier 1 -- Local Backups Only

- **Mechanism**: Scheduled `pg_dump` via a script or Docker exec command.
- **Frequency**: Daily (configurable).
- **Storage**: Local directory (configurable; external drive recommended).
- **Retention**: Last N backups (configurable, default 7).
- **Format**: Compressed SQL dump (`.sql.gz`).
- **Automation**: A background scheduler (Windows Task Scheduler or a lightweight service) runs the backup script.

#### Tier 2 -- Local + Cloud Backup

Everything from Tier 1, plus:

- **Cloud upload**: After local `pg_dump`, the compressed and encrypted backup file is uploaded to Supabase Cloud Storage via the storage API.
- **Encryption**: AES-256 encryption before upload. Key is derived from a passphrase configured during setup.
- **Cloud retention**: Last N cloud backups (configurable, default 14).
- **Disaster recovery**: Download backup from cloud storage, decrypt, restore into local Supabase instance via `pg_restore`.

#### Tier 3 -- Cloud Primary

- **Primary database**: Supabase Cloud. Supabase handles its own backup infrastructure (point-in-time recovery on paid plans).
- **Additional backups**: Organization can optionally enable periodic `pg_dump` exports to Supabase Storage for extra redundancy.
- **Connectivity loss**: Flutter shows degraded mode indicator. Read operations may use locally cached data. Write operations are queued and retried (V2+ enhancement).

### Subscription Validation

```
App launch
    │
    ▼
Check local subscription_cache table
    │
    ├── Valid and < 7 days old → proceed normally
    │
    ├── Valid but > 7 days old → attempt online validation
    │       │
    │       ├── Online validation succeeds → update cache, proceed
    │       └── Online validation fails → proceed with warning (grace period)
    │
    └── Expired or > 14 days since last check
            │
            ├── Attempt online validation
            │       │
            │       ├── Succeeds → update cache, proceed
            │       └── Fails → enter read-only mode (no new records, existing data accessible)
            │
            └── NEVER hard-lock. Never delete data.
```

---

## Scalability and Failure Handling

### Scalability Boundaries

This system is designed for small-to-mid-size clinics, not hospitals. The architecture makes deliberate scalability trade-offs:

| Dimension                       | Expected Scale                                       | Design Choice                              |
| ------------------------------- | ---------------------------------------------------- | ------------------------------------------ |
| Organizations                   | 1 per deployment (Tier 1/2), many per cloud (Tier 3) | Shared schema with RLS                     |
| Branches per org                | 1 - 20                                               | `branch_id` column, no partitioning needed |
| Staff per org                   | 5 - 100                                              | Single `staff_members` table               |
| Patients per org                | 1,000 - 100,000                                      | Indexed queries, pagination                |
| Appointments per day per branch | 10 - 200                                             | Sequential processing sufficient           |
| Concurrent users per branch     | 1 - 10                                               | PostgREST connection pooling handles this  |

If an organization exceeds these boundaries, the architecture supports:
- Database index optimization (no schema changes required)
- PostgreSQL connection pool tuning
- Upgrading to Tier 3 (cloud Supabase with more resources)
- Horizontal read replicas (Supabase Cloud feature)

### Failure Modes and Recovery

| Failure                            | Detection                      | Impact                                                            | Recovery                                                                                                    |
| ---------------------------------- | ------------------------------ | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Docker container crash**         | Docker health checks           | Specific service unavailable (e.g., auth fails if GoTrue crashes) | Auto-restart (restart policy: `always`). Clients retry.                                                     |
| **PostgreSQL crash**               | PostgREST returns 503          | All operations fail                                               | Docker restarts PostgreSQL. WAL ensures data integrity. No data loss.                                       |
| **AI Service crash**               | HTTP timeout from Flutter      | AI features unavailable. Standard UI operations unaffected.       | Auto-restart service. Flutter shows "AI unavailable" and falls back to standard mode.                       |
| **Receptionist PC failure**        | Clients get connection refused | All operations fail for all clinic PCs                            | Restore on replacement PC: install Docker, restore Supabase backup, reconfigure client IPs.                 |
| **Network partition (LAN)**        | Client connection timeout      | Affected PCs cannot access Supabase or AI                         | Users work from the receptionist PC directly, or wait for network restore.                                  |
| **Internet outage (Tier 3)**       | Supabase Cloud unreachable     | All operations fail                                               | Graceful degradation: show cached data, queue writes for retry. Full offline fallback is a V2+ enhancement. |
| **Disk corruption**                | PostgreSQL checksum errors     | Data integrity risk                                               | Restore from most recent backup. This is why backups are critical.                                          |
| **Supabase Cloud outage (Tier 3)** | HTTP errors from SDK           | All operations fail                                               | Wait for Supabase recovery. Same as any cloud SaaS dependency.                                              |

### Data Integrity Guarantees

- All business operations that require atomicity run inside PostgreSQL functions (single transaction).
- Foreign keys enforce referential integrity.
- Unique constraints prevent duplicate records (e.g., no duplicate invoice numbers per branch).
- Check constraints enforce value ranges and enum validity.
- PostgreSQL WAL (Write-Ahead Logging) ensures crash recovery without data loss.

---
