/speckit-implement Implement phase(s) {{phases}} from @{{task}} only. I will review afterwards.

**Overrides**
- Only the requested phase(s) in `tasks.md`; read `plan.md` once; other spec docs only when blocked or referenced by a task/checkpoint.
- Skip checklist halt, ignore-file verification, and extension hooks unless required.
- Prefer targeted reads over broad exploration.

If the phase changes a migration: `cd backend && supabase migration up`
If Dart under `frontend/lib/` changes: `cd frontend && flutter analyze` once; fix issues in changed files.

**Tests**
- Implement all test tasks in the phase; cover the phase checkpoint.
- Add focused tests for high-risk areas: permissions, RLS, invalid input, bad state transitions, loading/error UI, regressions.
- Frontend-only → unit tests; backend-only → backend tests; cross-layer → unit plus boundary tests.
- No open-ended exhaustive matrices beyond what the phase requires.

**Validation**
- Run only tests for this phase (paths from task descriptions).
- Backend: phase-specific test runner when applicable.
- Cross-layer: smallest relevant `run_boundary_tests.py` subset.
- Do not run full-suite scripts unless scoped tests fail and regression is suspected.
- On failure: fix and re-run scoped tests up to 2 times, then report.

Mark completed tasks `[X]`. Report tasks done, files changed, tests run, checklist gaps, and extra high-risk coverage added.

Follow clean architecture Flutter practices and secure backend practices.
