# AI Platform E2E Scenario Catalog

Complete scenario catalog for the whole AI Platform data journey — every stage
from platform boot to request settlement, support, and retention. The catalog
lives in this directory as one file per stage plus a registers file.

- **Code is authoritative.** Every scenario was derived from `ai-platform/src/`,
  `ai-platform/migrations/`, `ai-platform/manifests/`, `ai-platform/control/`,
  and `backend/supabase/migrations/`. The data-journey docs were orientation
  only; disagreements are recorded in the Doc-Drift Register.
- **Scenarios mimic production, not branch coverage.** Each scenario is a
  full-path journey through the real stage pipeline with realistic payloads and
  honestly-built prior state. Direct seeding is marked `[SEED]` with
  justification.
- **Cross-stage references** use stage + behavior (e.g. "Stage 4 entitle happy
  path") because chapters were authored in parallel; within-chapter references
  use exact scenario IDs.

## Table of Contents

1. [Stage 00 — Platform configuration and boot](stage-00-platform-boot.md)
2. [Stage 01 — Token contract baseline](stage-01-token-contract.md)
3. [Stage 02 — Clinic keypair enrollment (Supabase side)](stage-02-clinic-keypair.md)
4. [Stage 03 — Platform installation enrollment (control plane lifecycle)](stage-03-installation-enrollment.md)
5. [Stage 04 — Entitlement and capability grants](stage-04-entitlement-capability-grants.md)
6. [Stage 05 — Routing policy (publish, canary, promote, rollback, kill switch)](stage-05-routing-policy.md)
7. [Stage 06 — Minting an AAT (Supabase token issuer)](stage-06-minting-an-aat.md)
8. [Stage 07 — Discovery (GET /v1/capabilities)](stage-07-discovery.md)
9. [Stage 08 — Request ingress (POST /v1/requests adapter gate + context provider RPC)](stage-08-request-ingress.md)
10. [Stage 09 — The Guard (pre-accept pipeline, stages 1–10 in order)](stage-09-the-guard.md)
11. [Stage 10 — Accept, route, invoke, stream](stage-10-accept-route-invoke-stream.md)
12. [Stage 11 — Terminal settlement (credit, journal, envelope, acceptance recording)](stage-11-terminal-settlement.md)
13. [Stage 12 — Lookup and support](stage-12-lookup-and-support.md)
14. [Stage X — Cron-driven behaviors and alternative/failure journeys](stage-X-cron-and-failure-journeys.md)
15. [Registers](registers.md) (cross-chapter, compiled after the chapters):
    - Error-Code Inventory
    - Auth-Boundary Matrix
    - Input-Field Appendix
    - Doc-Drift Register
    - Non-Automatable Register

Scenario counts per chapter: S00=37, S01=31, S02=27, S03=83, S04=104, S05=85,
S06=47, S07=52, S08=69, S09=85, S10=34, S11=29, S12=72, SX=63 (total 818).
