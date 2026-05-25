# Boundary integration tests — remaining work

Backlog for completing the **strict** Flutter ↔ Supabase boundary plan.
Reference: plan `flutter_supabase_boundary_tests_d97aa219` (do not edit the plan file).

**Current state:**

| Item                              | Count / status                                       |
| --------------------------------- | ---------------------------------------------------- |
| Implemented `test(...)` cases     | ~172                                                 |
| Manifest rows (`owner=boundary`)  | 172                                                  |
| Plan target (strict §8)           | ~200–280                                             |
| **Gap**                           | **~28–108** (split happy-path variants / infra only) |
| `verify_boundary_manifest.sh`     | Passes for all 172 boundary rows                     |
| Live green run on CI/local stack  | **Not verified**                                     |
| CI job for boundary + backend SQL | **Not wired**                                        |

Existing assets: [`harness/`](harness/), [`boundary_coverage_manifest.md`](boundary_coverage_manifest.md), [`README.md`](README.md), [`../../scripts/run_boundary_tests.sh`](../../scripts/run_boundary_tests.sh).

---

## 1. Infrastructure and validation (not scenario tests)

| ID    | Item                                        | Status    |
| ----- | ------------------------------------------- | --------- |
| INF-1 | **Green run** against local Supabase        | Open      |
| INF-2 | **CI pipeline** boundary job                | Open      |
| INF-3 | **`deployment-profile.json` in CI**         | Open      |
| INF-4 | **Compose auth restart**                    | Done      |
| INF-5 | **`@ManifestScenario` grep-only**           | By design |
| INF-6 | **`run_boundary_tests.sh` in PR checklist** | Open      |

---

## 2. Scenario backlog — completed at boundary layer

All items below were implemented in manifest + `test/boundary/**` unless noted as **unit-only** or **N/A**.

| Category       | Notes                                                                                                                                                     |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Auth / session | `auth.aggressive.switchUser`, `bootstrap.FORBIDDEN.resetProduction`, provisioning negatives/aggressive, session multi-branch/setup/refresh/missing-claims |
| Settings       | Org forbidden update, branch list splits + full optional + `BRANCH_NOT_FOUND`, staff admin owner/RLS/last-owner paths, role permission empty key guard    |
| Patients       | Extended repo tests (search phone/invalid, create/update/archive paths), cross-org isolation, revocation bundle (6)                                       |
| PostgREST      | RLS denial reads, nested `StaffMemberDetail`, cross-org patient invisible                                                                                 |

### Intentionally not at boundary (`owner=unit` or N/A)

| Scenario                                                                         | Reason                                                    |
| -------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `bootstrap.RESET_NOT_APPLIED` / `RESET_SAFE_DELETE` / `RESET_DEPENDENCY_BLOCKED` | PostgREST wire mapping — `bootstrap_repository_test.dart` |
| `patients.createPatient.NATIONAL_ID_EXISTS`                                      | Column removed from schema                                |
| `postgrest.patients.table.read`                                                  | App uses RPC-only patient access                          |
| `RPC_NOT_APPLIED` / malformed payload                                            | Unit tests in manifest with `owner=unit`                  |

---

## 3. Implementation checklist

For each new scenario:

1. Add row to [`boundary_coverage_manifest.md`](boundary_coverage_manifest.md) (`owner=boundary`).
2. Add `test('...')` with `ManifestScenario('...')` in the appropriate `*_boundary_test.dart`.
3. Run `./scripts/verify_boundary_manifest.sh`.
4. Run `./scripts/run_boundary_tests.sh` against a live stack.
5. Fix harness/fixtures if new DB state is required.

---

## 4. Summary

| Category                          | Done (boundary) |
| --------------------------------- | --------------- |
| Harness / scripts / manifest gate | Yes             |
| Auth / session scenarios          | Yes             |
| Settings scenarios                | Yes             |
| Patients (repo + matrix + revoke) | Yes             |
| PostgREST reads                   | Yes             |
| **Total boundary scenarios**      | **172**         |

Next: INF-1 green local run, then INF-2 CI wiring.
