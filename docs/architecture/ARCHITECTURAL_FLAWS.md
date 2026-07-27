# Architectural Flaws and Technical Debt

- Purpose: Track known inconsistencies between documentation and code, design risks, and remediation priorities from the 2026-07-02 architecture audit.
- Read this when: planning refactors, onboarding, or assessing release risk.
- Not covered here: feature-level bugs (see specs and QA docs).

> Severity: **Critical** = data/security/production risk; **High** = major functional gap or misleading docs; **Medium** = maintainability or partial feature; **Low** = cleanup/naming.

---

## Critical

| ID | Location | Issue | Impact | Recommendation |
| -- | -------- | ----- | ------ | -------------- |
| C1 | `auth_internal.build_staff_claims` / JWT resolution (`01-principles.md` A12) | Single-org assumption: claims resolve against oldest non-deleted organization, not caller-scoped multi-tenant | Tier 3 shared Supabase Cloud could expose wrong org context if multiple orgs ever exist in one DB | Document one-org-per-instance as hard deployment constraint; add migration guard or explicit org binding before multi-tenant cloud |

---

## High

| ID | Location | Issue | Impact | Recommendation |
| -- | -------- | ----- | ------ | -------------- |
| H1 | Roadmap V1-6 vs `frontend/lib/features/billing/` | ~~Billing marked complete… no presentation layer~~ **Resolved** — presentation layer shipped (list, detail, editor, settings) | Operators can manage invoices in UI | Mark resolved; keep roadmap status aligned |
| H2 | `docs/specs/014-visit-encounter-workspace/` contracts vs migrations `20260702120000`, `20260705120000` | Spec/plan describe `diagnosis_codes`, `visit_plan_details`, related RPCs that were **removed from code** | Agents implementing from stale contracts will build wrong features | Revise spec 014 contracts to match reverted schema; archive dropped contract files |
| H3 | `.github/workflows/ci.yml` | **No backend/SQL tests in CI** — 149 migrations untested on push | Schema/RPC regressions reach main undetected | Add Postgres service job running `run_all_backend_tests.sh` |
| H4 | Multiple docs (historical) | **Offline-first** language contradicted by online-only visit saves and LAN-write-block behavior | Misleading non-functional requirements for clinical features | Resolved in `01-principles.md` (online-first); verify specs still say offline |
| H5 | `VisitDocumentationNotifier` (~1400 lines) | Monolithic notifier: draft, save, safety, attachments, completion | Hard to test and extend; regression risk on 014 changes | Split by concern (documentation save, safety CRUD, attachment queue) |
| H6 | V1-8 installer | **Not built** — no MSI/MSIX, no automated backup scheduler | Tier 1/2 deployment remains manual Docker + dev docs | Prioritize V1-8 or document manual install as interim |
| H7 | `backend/local/docker-compose.yml` | No service healthchecks; no observability stack | Silent partial failures hard to diagnose on clinic LAN | Add healthchecks; optional metrics in V1-8 |
| H8 | `frontend/lib/features/appointments/{presentation/providers,data,domain} queue files vs router.dart:112 | Queue subsystem (~1,500 lines) implemented and tested but no page; docs claim built | Dead weight + previously an idle Realtime channel per client | Build AppointmentQueuePage or delete the subsystem; shell warm removed |

---

## Medium

| ID | Location | Issue | Impact | Recommendation |
| -- | -------- | ----- | ------ | -------------- |
| M1 | `08-automation.md` (historical) | Referenced `workflow_event_queue` and rule tables that **never exist in migrations** | Future automation design based on non-existent schema | Fixed in architecture docs; implement only after new migration |
| M2 | `roles_permissions` seed / billing RPCs | Legacy `owner` role rows and `invoices.apply_discount_above_threshold` may remain in DB; role enum dropped | Confusion in permission matrix UI; dead keys | Migration to purge owner rows and document canonical keys in `09-security-rbac.md` |
| M3 | V1-7 Shifts | Backend complete (`008-shift-management`); frontend routes are placeholders | Shift management unavailable to users | Track as V1-7 frontend; update status table (done in `12-roadmap-phases.md`) |
| M4 | `docs/specs/common/*`, `docs/specs/operations/*` | Placeholder specs referenced by roadmap but **unauthored**; numbered specs are authoritative | Agents load wrong or empty specs | Point roadmap required specs to `002`–`014` paths (partially done) |
| M5 | Tier 2 backup (`01-principles.md` A6) | Backup-only cloud sync **not implemented** — no scheduler | Tier 2 deployment story incomplete | V1-8 installer scope or defer Tier 2 marketing |
| M6 | AI layer (`06-ai.md`) | Documented but **zero implementation** (no Ollama, no chat UI) | `ai.access` permission seeded without feature | Keep docs labeled V2; hide AI nav item until built |
| M7 | Schema churn 014 P3 | Tables created then dropped within days (diagnosis catalog, structured plan) | Wasted migration complexity; test fixtures may reference dropped objects | Document final state in `14-visits-encounter-workspace.md` (done); avoid re-adding without new spec |
| M8 | LAN security | No TLS on self-hosted Supabase (HTTP :54321) | JWT and PHI traverse clinic LAN in cleartext | Accept for trusted LAN or terminate TLS at Kong in V1-8 |
| M9 | `GOTRUE_DISABLE_SIGNUP: "false"` in Compose | Open signup on local stack if exposed | Unintended account creation on misconfigured LAN | Set `true` in production compose; document dev-only default |

---

## Low

| ID | Location | Issue | Impact | Recommendation |
| -- | -------- | ----- | ------ | -------------- |
| L1 | `20260628140000_visit_documentation_redesign.sql` | Legacy `save_soap_note` (public + `auth_internal`) was fully `DROP FUNCTION`'d, not just deprecated; only `save_visit_documentation` exists live | None currently — historical references in test file names (`visit_repository_soap_test.dart`) and old test-results artifacts can mislead grep-based investigation | Rename residual `*_soap_test.dart` files/tests for clarity; no schema action needed |
| L2 | `07-frontend.md` clean architecture | Visits/billing skip use-case layer; repositories called from notifiers | Inconsistent layering vs patients/appointments | Accept for orchestration-heavy modules or refactor incrementally |
| L3 | `foundation_demo/` feature | Dev-only catalog; listed alongside production features | Minor doc noise | Mark dev-only in tree |
| L4 | Bootstrap seed password | Default `admin@admin` / `admin` in migration seed | Dev-only risk if used in production | Installer must force password change (V1-8) |
| L5 | `insurance_providers.organization_id` vs old doc `branch_id` | Doc said branch-level; code is org-scoped | Minor integrator confusion | Fixed in `05-database.md` |
| L6 | Flutter CI only on Windows | No Linux/macOS build verification | Low risk for Windows-first product | Optional matrix job |

---

## Doc/Code Inconsistencies Resolved (2026-07-02 audit)

The following were corrected in this audit pass:

- `05-database.md`: visits tables, billing tables, RPC inventory, four roles
- `07-frontend.md`: visits, billing, setup, `core/ui`, routes
- `01-principles.md`: online-first vs offline-first
- `08-automation.md`: removed fictitious queue table
- `09-security-rbac.md`: permissions and roles
- `11-spec-driven-development.md`: numbered spec pattern
- `12-roadmap-phases.md`: V1-5 detail, V1-6/V1-7 split status, session persistence
- New: `14-visits-encounter-workspace.md`, `15-billing.md`

---

## Summary counts

| Severity | Count |
| -------- | ----- |
| Critical | 1 |
| High | 8 |
| Medium | 9 |
| Low | 6 |
| **Total open** | **24** |
