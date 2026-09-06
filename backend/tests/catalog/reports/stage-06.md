# Stage 06 — Catalog SQL (issuer / pgTAP)

Green after runner iteration 2. All 47 catalog IDs (S06-001 … S06-047) are in
scope for this track and have a recorded test. Worker HTTP tests were not
implemented; `ai-platform/test/e2e/reports/stage-06.md` was left untouched.

Platform HTTP half of S06-041 … S06-047 is **skipped** with Register 5 #17
(Stage 7/9 already execute identity rejection). Clinic mint / claim-shape
halves of those IDs exist and passed — the IDs were not dropped.

## 1. Chunk map

| File | IDs | Writer |
| --- | --- | --- |
| `backend/tests/catalog/stage-06-issuer-guards.sql` | S06-001 … S06-016 | Writer A |
| `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql` | S06-017 … S06-032 | Writer B |
| `backend/tests/catalog/stage-06-verify-and-handoff.sql` | S06-033 … S06-047 | Writer C |

Each file implements Stage 06 Baseline B0 itself (Nadia Haddad doctor, Lina
Khoury administrator, Rami Saleh receptionist + enroll as BOOT). They do
**not** call `catalog_common_setup()` (Stage 02 personas). S06-007 isolates
pre-clinic setup then rebuilds B0.

## 2. Writer outcomes

**Writer A** — created `stage-06-issuer-guards.sql` (S06-001…S06-016).
Session/staff/branch/install/rate guards. S06-007 runs before clinic
bootstrap. [SEED] used only where the catalog says (S06-008/009/011/012/015).

**Writer B** — created `stage-06-happy-path-and-lifecycle.sql`
(S06-017…S06-032). Happy-path claims, ignored `p_scopes`, branch selection,
rotation/revoke/re-enroll, live `ver`/`aud`/lifetime reads. Default lifetime
assertions follow CODE (600 s), not catalog 900 s.

**Writer C** — created `stage-06-verify-and-handoff.sql` (S06-033…S06-047).
033–040 full SQL (`issue_ai_token` / `auth_internal.verify_aat`). 041–047
clinic mint of each token variant plus claim/keystore shape; `detail` cites
Register 5 #17 for the platform HTTP half.

## 3. Iteration count

| Step | Result |
| --- | --- |
| Writers (parallel) | All three files produced; all 47 IDs recorded |
| Runner 1 | Three Stage 06 files aborted. Stage 02 + harness smoke still passed. S06-027: `permission denied for table catalog_s06_text` while `authenticated`. Issuer-guards and verify-and-handoff B0: `INVALID_INPUT` on dotted usernames. |
| Fixers ×3 | Username B0 uses `nadia_h` / `lina_k` / `rami_s` (CODE regex). Temp-table writes after `reset_postgres()`. S06-033 asserts SQLSTATE `22023`. |
| Environment | Controller applied repo migrations `20260905120000`, `20260905120200`, `20260905120300` to `127.0.0.1:54322` (files not modified). Local DB had only `20260905120100`. Lifetime fallback is now 10 min. |
| Runner 2 | Clean pass. Stage declared green from this report, not from fixer self-reports. |

Max iterations used: 1 of 3 fixer rounds (2 runner passes).

## 4. Counts (runner 2)

| Scope | Passed | Skipped | Failed | Missing |
| --- | ---: | ---: | ---: | ---: |
| Files (`run.sh`) | 6 | 0 | 0 | 0 |
| S06-001 … S06-047 | 47 | 0 | 0 | 0 |
| S02-001 … S02-027 | 27 | 0 | 0 | 0 |
| Harness smoke | 3 | 0 | 0 | 0 |

`run.sh` summary: `catalog SQL harness: 6 passed, 0 failed.`

Register 5 handling:

| # | Item | This track |
| --- | --- | --- |
| 10 | Concurrent mint advisory lock | No scenario ID — not invented |
| 12 | PostgREST HTTP shape | Asserted as SQLSTATE `42501` / `P0001`, not HTTP |
| 14 | Non-deterministic kid/jti/JWK | Captured from RPC/issue; no pinned literals |
| 15 | pgsodium | Local Supabase only; enroll/sign/verify ran |
| 16 | jti collision `23505` | Not invented |
| 17 | Platform HTTP of S06-041…047 | **Skipped** (Stage 7/9). Clinic halves **passed** with those IDs |

## 5. Conflicts + harness gaps

Conflicts (tests follow CODE): `backend/tests/catalog/reports/stage-06-conflicts.md`

| ID / area | Catalog claim | Code behavior |
| --- | --- | --- |
| B0 usernames | `nadia.h` / `lina.k` / `rami.s` | `assert_valid_username` is `[a-z0-9_-]` only → `nadia_h` / `lina_k` / `rami_s` |
| S06-019 / 020 / 026 / 032 / 043 | `exp − iat = 900` (seed 15) or restore to 15 | Seed + fallback **10 min → 600 s** |
| S06-019 fingerprints | No public.* / keystore writes | `xmax` / `max(updated_at)` are not issuer writes; counts + ledger kept |
| S06-033 | SQLSTATE `22P02` | jsonb string `::numeric` → **`22023`** |

**Harness gaps**

- `catalog_common_setup()` uses Stage 02 personas. Stage 06 B0 is implemented
  in each file after `\ir harness.sql` (12-arg `bootstrap_finish_setup` +
  enroll as BOOT). Frozen harness was not modified.
- `pg_temp.set_authenticated_session` injects `sub` + `role` (+ optional
  `exp`). Staff-management RPCs overlay `organization_id` / `staff_member_id`.
- Postgres-owned TEMP tables are not writable as `authenticated`; writers
  `reset_postgres()` before stash/inspect.
- Enroll/sign need pgsodium (Register 5 #15) — local Supabase only.
- Local `schema_migrations` was behind the repo at runner 1 (`20260905120000`
  / `20260905120200` / `20260905120300` not applied). Environment gap, not a
  harness API gap.

## 6. Remaining failures

None.

## 7. Files touched (this stage)

Created:

- `backend/tests/catalog/stage-06-issuer-guards.sql`
- `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql`
- `backend/tests/catalog/stage-06-verify-and-handoff.sql`
- `backend/tests/catalog/reports/stage-06-failures.md`
- `backend/tests/catalog/reports/stage-06-conflicts.md`
- `backend/tests/catalog/reports/stage-06.md` (this file)

Not modified: `harness.sql`, `run.sh`, `harness-smoke.sql`,
`backend/supabase/migrations/**`, `ai-platform/**`, existing
`backend/tests/*.sql`, Stage 02 catalog files,
`ai-platform/test/e2e/reports/stage-06.md`.
