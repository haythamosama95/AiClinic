# Backend Review — Third Pass (CONFIG, INFRA & TEST BLIND SPOTS)

**Date:** 2026-07-05  
**Scope:** `backend/local/` (Docker/Kong/PostgREST), `backend/supabase/seed.sql`, env defaults, `.github/workflows/ci.yml`, test harness & integration blind spots  
**Prior art:** [backend-architecture-review.md](./backend-architecture-review.md), [backend-architecture-review-second-pass.md](./backend-architecture-review-second-pass.md)  
**Method:** Cross-check config artifacts against test runners and Flutter client dependencies; exclude all first/second-pass Critical/High IDs (C-01/C-02, H-01–H-25).

---

## Executive Summary

**New finding count: 6 (1 Critical, 5 High)**

Prior passes covered RLS bypasses, missing `auth_internal` grants, superuser SQL tests, CI gaps, open signup, Kong rate limits (Medium), and seed/pre-request drift (Medium). This pass adds **compose-path production failures** that tests mask: **incoherent JWT config**, **hardcoded pre-request without seed**, **missing Realtime publication**, **PostgREST running as DB superuser**, **LAN-exposed Postgres with default password**, and **zero PostgREST coverage for billing/shifts/catalog**.

---

## 1. Critical Issues

### C-03 — PostgreSQL superuser port published on host with default password *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | Critical (Tier 1 LAN clinic deployment) |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/local/.env.example` |
| **Evidence** | Postgres binds `"${SUPABASE_DB_PORT}:5432"` (line 15) to the host (default `0.0.0.0`). Default `POSTGRES_PASSWORD=postgres` (`.env.example:14`). Tier 1 target is LAN clinic workstations connecting to a server (`docs/architecture/03-deployment-networking.md:30-51`). |
| **Why it's a problem** | Any device on the clinic LAN can connect directly as `postgres` superuser, bypassing Kong, JWT, RLS, and all RPC guards. |
| **Potential impact** | Full database compromise from the LAN; read/modify all PHI; forge staff rows; disable audit. |
| **Recommended solution** | Do not publish Postgres to the host in deployment compose; use internal Docker network only. Require strong generated password; fail compose if `POSTGRES_PASSWORD` is default on non-solo-dev. |

---

## 2. High Priority Issues

### H-26 — JWT secret and API keys incoherent in committed `.env.example` *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/local/.env.example`, `frontend/config/local/deployment-profile.json`, `docs/implementation/spec001/backend-implementation.md` |
| **Evidence** | `.env.example` sets `SUPABASE_JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long` (line 17) but ships standard Supabase **demo** `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` (lines 20–23) signed for a different secret. Docs state: *"If you change the secret, regenerate … keys … or Auth and PostgREST will reject tokens"* (`backend-implementation.md:282`). `validate_local_stack.sh:87-90` auto-copies `.env.example` → `.env`. |
| **Why it's a problem** | Fresh compose setup produces invalid JWTs. HTTP auth/REST/Storage fail; SQL tests still pass as `postgres` superuser (`run_all_backend_tests.sh:22`). |
| **Potential impact** | Flutter client cannot authenticate; false green backend test runs; onboarding broken until keys manually regenerated. |
| **Recommended solution** | Regenerate anon/service keys signed with the committed JWT secret, or revert JWT secret to match demo keys. Add `validate_local_stack.sh` step: sign-in smoke with anon key must succeed. |

---

### H-27 — Appointment Realtime never configured in migrations *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/local/docker-compose.yml`, `frontend/lib/features/appointments/data/appointment_queue_realtime.dart`, all `backend/supabase/migrations/*.sql` |
| **Evidence** | Flutter subscribes to `public.appointments` postgres changes (`appointment_queue_realtime.dart:44-48`). Repository-wide grep: **zero** `ALTER PUBLICATION`, `supabase_realtime`, or `REPLICA IDENTITY` in migrations. Realtime service runs in compose (`docker-compose.yml:87-107`); Kong routes `/realtime/v1/` (`kong.yml:45-51`). Spec FR-016 requires live queue updates. |
| **Why it's a problem** | Self-hosted compose path likely never broadcasts appointment changes; queue stays stale unless manually refreshed. |
| **Potential impact** | Live queue feature non-functional on deployment stack; spec SC-007 unmet; UI degrades silently (`AppointmentQueueRealtimeConnection.degraded`). |
| **Recommended solution** | Migration: `ALTER PUBLICATION supabase_realtime ADD TABLE public.appointments`; set `REPLICA IDENTITY FULL` (or default) for UPDATE payloads; add Realtime RLS check; websocket integration test in CI. |

---

### H-28 — PostgREST connects as `postgres` superuser, not `authenticator` *(NEW)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/local/init.sql` |
| **Evidence** | `PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres` (line 54). `init.sql` creates `anon`/`authenticated`/`service_role` but **not** `authenticator`. No `FORCE ROW LEVEL SECURITY` in any migration. `seed.sql:21-24` references `authenticator` role from Supabase image but compose never uses it for PostgREST. |
| **Why it's a problem** | Violates Supabase least-privilege model. API layer DB connection is superuser-capable; defense relies entirely on PostgREST always switching to JWT role correctly. |
| **Potential impact** | PostgREST misconfiguration or future CVE could expose superuser access; harder to audit DB privilege separation for clinic LAN deployments. |
| **Recommended solution** | Use `authenticator` role in `PGRST_DB_URI`; grant `authenticated`/`anon` membership; revoke direct superuser API path. |

---

### H-29 — Compose hardcodes `PGRST_DB_PRE_REQUEST` without applying `seed.sql` *(NEW — elevates M-06 impact)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/local/docker-compose.yml`, `backend/supabase/seed.sql` |
| **Evidence** | Compose sets `PGRST_DB_PRE_REQUEST: public.local_dev_pre_request` (line 57). Function defined only in `seed.sql:7-14`. Compose mounts only `init.sql` (lines 17–18); no seed step. Migrations contain no `local_dev_pre_request`. Flutter boundary harness must recreate it via raw SQL (`frontend/test/boundary/harness/sql_fixture_helper.dart:42-54`). |
| **Why it's a problem** | Migrations-only compose bring-up (documented path) leaves pre-request function missing → PostgREST errors on **every** request, not just `dev_reset`. Prior review scoped impact to dev tooling (M-06 Medium). |
| **Potential impact** | Total REST/RPC API outage on compose stack until seed manually applied; `validate_local_stack.sh` may still pass auth health checks while REST is broken. |
| **Recommended solution** | Move `local_dev_pre_request` into a guarded migration, or remove `PGRST_DB_PRE_REQUEST` from compose until seed runs; add REST smoke that calls an RPC and expects 200. |

---

### H-30 — Billing, shifts, and service catalog have zero PostgREST HTTP test coverage *(NEW — extends H-13/L-01)*

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/tests/run_billing_tests.sh`, `run_shift_management_tests.sh`, `run_service_catalog_tests.sh`, `frontend/test/boundary/` |
| **Evidence** | All three sub-runners use `psql -U postgres` only. Flutter boundary suite covers auth/patients/appointments/settings via live PostgREST; **grep finds no** billing/shift/catalog boundary tests. Only appointments have grant regression SQL (`appointment_management_grants.sql`). Known missing grants (C-02, H-09, H-10, H-22) therefore cannot be caught for those domains. |
| **Why it's a problem** | INVOKER grant chain failures are the highest-risk production bug class; 3 of 4 major feature domains have no PostgREST-path verification at all. |
| **Potential impact** | Billing, shifts, and catalog ship broken via API while SQL superuser tests stay green. |
| **Recommended solution** | Add `*_grants.sql` per domain; add boundary or curl-based RPC smoke per feature; wire into `run_all_backend_tests.sh` and CI. |

---

## 3. What Was Checked (No New Critical/High)

| Area | Checked | Result |
|------|---------|--------|
| Kong auth/rest rate limits | `kong.yml` | Already flagged M-07 (Medium) — not duplicated |
| Storage/realtime Kong rate limits | `kong.yml:37-51` | Same — Medium in 2nd pass |
| Storage RLS policies | visit-attachments insert/select migrations | Policies org/branch-scoped; DELETE RPC-only (M-13 Medium) |
| Open signup | `docker-compose.yml:35` | H-19 |
| CI backend job | `.github/workflows/ci.yml` | H-17 — Flutter-only |
| Superuser SQL tests | `run_all_backend_tests.sh` | H-13 |
| GoTrue soft-fail | `auth_flow_smoke.sh:94-98, 217-218` | H-16 |
| `dev_seed_*` grants | migrations | H-25 |
| `assert_patient_branch_scope` grant | encounter migration | H-24 |
| Compose migration automation | `docker-compose.yml` | H-18 |
| Connectivity smoke | `connectivity_smoke.sh` | No realtime probe; accepts 401/404 as pass — Medium scope |
| Bootstrap admin `admin/admin` | seed migration | Documented dev-only; no new finding |
| Studio service-role exposure | compose studio service | Medium for LAN; subsumed under C-03 LAN exposure theme |

---

## 4. Test Blind-Spot Summary (New vs Prior)

| Blind spot | Prior pass | Third pass |
|------------|------------|------------|
| Superuser psql vs PostgREST grants | H-13 | **H-30**: 3 domains have zero PostgREST tests |
| GoTrue HTTP soft-fail | H-16 | **H-26**: root cause = JWT/key incoherence |
| Seed/pre-request drift | M-06 | **H-29**: total REST outage, not just dev_reset |
| Realtime | M-07 (rate limit only) | **H-27**: publication never configured |
| Compose DB identity | — | **H-28**, **C-03** |

---

## 5. Recommended Remediation (New Items Only)

| Priority | Action | ID |
|----------|--------|-----|
| P0 | Remove Postgres host port publish for deployment; enforce non-default password | C-03 |
| P0 | Fix JWT secret ↔ anon/service key coherence; add sign-in validation to stack check | H-26 |
| P1 | Migration: Realtime publication + REPLICA IDENTITY for `appointments` | H-27 |
| P1 | Switch PostgREST to `authenticator` DB role | H-28 |
| P1 | Resolve pre-request/seed coupling (migrate function or conditional compose env) | H-29 |
| P1 | Grant regression + PostgREST smoke for billing, shifts, catalog | H-30 |

---

## Finding Count

| Severity | New in third pass |
|----------|-------------------|
| Critical | **1** (C-03) |
| High | **5** (H-26 – H-30) |
| **Total** | **6** |

---

*End of third-pass review. All findings traced to `backend/local/`, `backend/supabase/seed.sql`, `backend/tests/`, and `.github/workflows/ci.yml` as of 2026-07-05.*
