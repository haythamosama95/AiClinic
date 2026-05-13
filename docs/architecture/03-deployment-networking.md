# Deployment and Networking

- Purpose: Define runtime tiers, hardware needs, self-hosted infrastructure, LAN topology, and operational networking behavior.
- Read this when: working on environment setup, installers, Docker packaging, clinic LAN behavior, or infrastructure recovery paths.
- Canonical for: deployment tiers, Docker composition, local networking, and workstation/server responsibilities.
- Usually paired with: `docs/architecture/07-frontend.md`, `docs/architecture/10-resilience-and-scale.md`, and any deployment-related spec.
- Not covered here: database schema design, RBAC rules, or feature-specific business logic.

---

## Deployment Architecture

### Deployment Tiers

All tiers share the same application code, the same database schema, and the same PostgreSQL functions. The only variable is where Supabase runs and whether cloud connectivity is used.

#### Tier 1 -- Offline Local

```
┌─────────── Receptionist PC ───────────┐    ┌─── Other Clinic PC ───┐
│                                       │    │                       │
│  ┌─────────────────────────────────┐  │    │  ┌─────────────────┐  │
│  │   Flutter Desktop App           │  │    │  │ Flutter Desktop  │  │
│  └──────────┬──────────┬──────────┘  │    │  │     App          │  │
│             │          │              │    │  └────┬────────┬───┘  │
│             │          │              │    │       │        │      │
│  ┌──────────▼───┐  ┌──▼───────────┐  │    │       │        │      │
│  │  Supabase    │  │  AI Service  │  │    │       │        │      │
│  │  (Docker)    │  │  (Ollama)    │  │    │       │        │      │
│  │  Port 54321  │  │  Port 8090   │  │    │       │        │      │
│  └──────────────┘  └──────────────┘  │    │       │        │      │
│                                       │    │       │        │      │
│  Local backups: pg_dump to disk       │    │       │        │      │
└───────────────────────────────────────┘    └───────┼────────┼──────┘
                                                     │        │
                          LAN ◄──────────────────────┘        │
                          (static IP: 192.168.x.x:54321)      │
                          (static IP: 192.168.x.x:8090) ◄────┘
```

- No internet required for daily operations.
- Periodic local `pg_dump` backups to a configurable local directory (external drive recommended).
- Subscription validation cached locally with a 7-14 day grace period.

#### Tier 2 -- Local + Cloud Backup

Identical to Tier 1, plus:

- A background scheduler runs encrypted `pg_dump` and uploads to Supabase Cloud Storage.
- Upload frequency is configurable (daily recommended).
- Disaster recovery: download snapshot from cloud, restore into local Supabase.
- Internet is required periodically for backup uploads and subscription validation.

#### Tier 3 -- Cloud Connected

```
┌─── Any Clinic PC ─────┐         ┌──────────────────────────┐
│                        │         │   Supabase Cloud          │
│  ┌──────────────────┐  │  HTTPS  │                          │
│  │ Flutter Desktop  ├──┼────────►│  Auth + DB + Storage     │
│  │     App          │  │         │  + Realtime              │
│  └────────┬─────────┘  │         └──────────────────────────┘
│           │             │
│           │ HTTP (LAN)  │         ┌──────────────────────────┐
│           └─────────────┼────────►│  AI Service (Ollama)     │
│                         │         │  On receptionist PC      │
└─────────────────────────┘         │  or dedicated local node │
                                    └──────────────────────────┘
```

- Supabase Cloud is the primary database. No local Supabase instance needed.
- AI Service still runs locally on the LAN (AI inference remains local regardless of tier).
- Supports remote access and centralized analytics.
- Internet required for all database operations. Connectivity loss degrades gracefully: Flutter queues writes locally and retries (V2+ enhancement).

### Hardware Requirements

| Component                             | Minimum (8GB RAM) | Recommended (16GB RAM) |
| ------------------------------------- | ----------------- | ---------------------- |
| OS (Windows)                          | 2 GB              | 2 GB                   |
| Self-hosted Supabase (Docker)         | 800 MB - 1 GB     | 1.5 GB                 |
| AI Service (Ollama + quantized model) | 2 - 3 GB          | 3 - 4 GB               |
| Flutter Desktop App                   | 200 - 400 MB      | 200 - 400 MB           |
| Headroom                              | ~1.5 GB           | ~8 GB                  |
| **Total**                             | **~5.5 - 6.5 GB** | **~7 - 8 GB**          |

Notes:
- On 8GB RAM machines, use the smallest quantized models (e.g., Phi-3 mini Q4).
- Supabase Studio (admin UI) is optional and can be disabled to save ~200MB.
- Other clinic PCs (non-server) only run the Flutter app (~400MB).
- Disk: 20GB minimum for Supabase data + Docker images + AI models.

### Docker Composition (Receptionist PC, Tier 1/2)

The self-hosted Supabase stack is deployed as a Docker Compose configuration with these services:

| Service           | Image                | Port  | Purpose                          |
| ----------------- | -------------------- | ----- | -------------------------------- |
| postgres          | supabase/postgres    | 5432  | Database engine                  |
| rest              | postgrest/postgrest  | 3000  | Auto-generated REST API          |
| auth              | supabase/gotrue      | 9999  | Authentication (JWT-based)       |
| storage           | supabase/storage-api | 5000  | File storage API                 |
| realtime          | supabase/realtime    | 4000  | Realtime subscriptions           |
| kong              | kong                 | 54321 | API gateway (single entry point) |
| studio (optional) | supabase/studio      | 54323 | Admin dashboard                  |

All services are exposed to the LAN through Kong on port 54321. The Flutter app connects to `http://<receptionist-ip>:54321`.

---

## Local Networking Architecture

### LAN Topology

```
Clinic LAN (e.g., 192.168.1.0/24)
│
├── Receptionist PC (192.168.1.100) -- CLINIC SERVER NODE
│   ├── Docker: Supabase stack (port 54321)
│   ├── Docker/Service: AI Service (port 8090)
│   └── Flutter desktop app
│
├── Doctor PC 1 (192.168.1.101)
│   └── Flutter desktop app → connects to 192.168.1.100:54321 and :8090
│
├── Doctor PC 2 (192.168.1.102)
│   └── Flutter desktop app → connects to 192.168.1.100:54321 and :8090
│
└── Lab PC (192.168.1.103)
    └── Flutter desktop app → connects to 192.168.1.100:54321 and :8090
```

### Configuration

Each non-server clinic PC stores a local configuration file:

```json
{
  "deployment_mode": "local",
  "supabase_url": "http://192.168.1.100:54321",
  "supabase_anon_key": "eyJ...",
  "ai_service_url": "http://192.168.1.100:8090"
}
```

This is configured during the initial setup wizard on each device. The setup wizard can optionally auto-detect the server via a simple network scan (broadcast ping) or manual IP entry.

### Server Node Responsibilities

The receptionist PC serves as the clinic's local server. It runs:

1. **Docker Engine** with the Supabase stack (always running as a Windows service).
2. **AI Service** (Ollama as a system service + HTTP wrapper).
3. **Flutter desktop app** (the receptionist also uses the application).

A simple **system tray application** or **Windows service manager** monitors the health of Docker containers and Ollama, providing basic status indicators (green/red) and restart capability.

### Network Resilience

| Scenario            | Behavior                                                                                                         |
| ------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Server PC restarts  | Docker containers auto-restart (restart policy: `always`). Clients retry connections automatically.              |
| Client PC loses LAN | Flutter shows "connection lost" banner. User can view cached data. Writes are blocked until connection restores. |
| Server disk full    | PostgreSQL enters read-only mode. Flutter shows warning. Admin must free space.                                  |
| Power outage        | On power restore, Docker + Ollama auto-start. Clients reconnect. PostgreSQL WAL ensures no data corruption.      |

---
