# Quickstart: Context Resolver registry, first context RPC, and client contract test (E3)

E3 lands the Flutter Context Resolver — a generic key-list registry that assembles clinic context payloads under caller RLS — the first ordinary `visit.chief_complaint@v1` context provider RPC, and a Flutter client contract suite that fails when any active manifest declares a key the Resolver cannot satisfy.

**Scope rule:** This quickstart documents **this slice only**. It lists only files E3 added or modified, only E3 test files, and only commands that run E3 tests.

## 1. Architecture context

- **Delivery plan row E3** ([`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.6): Context Resolver registry, first context RPC, and client contract test in band E.
- **Architecture sections implemented** ([`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)):
  - §4.1 — Context Resolver: generic key → resolver registry, key list in / payload or typed failure out, screen-scoped cache
  - §5.2 — Context key vocabulary and published shapes (`visit.chief_complaint@v1`)
  - §4.2 — First ordinary context provider read RPC under caller RLS with no AI knowledge
  - §13.5 — Client contract tests against C1-shaped active manifests
- **Spec delivered** ([`spec.md`](spec.md)): frozen Context Resolver key-list API, screen-scoped cache, first context provider RPC, and client contract suite; thirteen FRs; ten named tests (E3-T01–E3-T10).
- **Plan scoped** ([`plan.md`](plan.md)): three Dart library modules under `frontend/lib/core/ai/`, Flutter unit + contract tests, one Supabase migration, one SQL/RLS suite, trust-runner wiring, and two frozen contracts.

## 2. What was implemented

- `frontend/lib/core/ai/context_resolver.dart` — Context Resolver: `resolve(List<String> keys)` → assembled payload or typed unknown-key failure; instance cache discarded on `dispose()`; no capability-id parameter.
- `frontend/lib/core/ai/context_registration.dart` — closed static map registering `visit.chief_complaint@v1`.
- `frontend/lib/core/ai/context_provider_port.dart` — injectable clinic-read port for resolver functions.
- `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql` — ordinary `get_visit_chief_complaint` RPC returning the A5-published shape under caller RLS.
- Flutter client contract suite in `context_contract_test.dart` — asserts every declared manifest context key is resolvable; fails on synthetic unregistered-key manifests.
- Frozen contracts: [`contracts/context-resolver.md`](contracts/context-resolver.md), [`contracts/context-provider-rpc.md`](contracts/context-provider-rpc.md).

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `frontend/lib/core/ai/context_resolver.dart` | Key-list API, screen-scoped cache, typed failure |
| `frontend/lib/core/ai/context_registration.dart` | Closed static key → resolver map |
| `frontend/lib/core/ai/context_provider_port.dart` | Injectable clinic-read port |
| `frontend/test/unit/core/ai/context_resolver_test.dart` | E3-T01–E3-T04 |
| `frontend/test/unit/core/ai/context_contract_test.dart` | E3-T09–E3-T10 |
| `frontend/test/unit/core/ai/fakes.dart` | Fake clinic-read port + C1-shaped manifest source |
| `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql` | First context provider RPC |
| `backend/tests/context_provider_rpc.sql` | E3-T05–E3-T08 |
| `specs/037-context-resolver-registry/contracts/context-resolver.md` | Frozen Resolver key-list API |
| `specs/037-context-resolver-registry/contracts/context-provider-rpc.md` | Frozen first RPC return shape |

## 4. Prerequisites

- Flutter / Dart SDK (`frontend/pubspec.yaml` declares SDK `^3.11.5`).
- Local Supabase PostgreSQL for the SQL/RLS suite (`backend/local/.env` sets `SUPABASE_DB_PORT`).

## 5. Run the automated suite

From the repository root:

```bash
cd frontend
flutter test test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart
```

Expected: **6 passing tests** for this slice only (E3-T01–E3-T04 and E3-T09–E3-T10).

SQL/RLS suite (requires migration applied and local Supabase):

```bash
source backend/local/.env
export PGPASSWORD="${POSTGRES_PASSWORD:-postgres}"
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 \
  -f backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 \
  -f backend/tests/context_provider_rpc.sql
```

Or run only this slice's SQL file via the trust runner (after migration):

```bash
bash backend/tests/run_ai_platform_trust_tests.sh
```

## 6. Inspect the changes

Read the frozen contracts:

```bash
cat specs/037-context-resolver-registry/contracts/context-resolver.md
cat specs/037-context-resolver-registry/contracts/context-provider-rpc.md
```

Open the registration map and Resolver API:

```bash
grep -n 'visit.chief_complaint@v1\|resolve\|dispose' frontend/lib/core/ai/context_*.dart
```

Confirm E1 architecture guard still passes for new Flutter AI paths:

```bash
cd frontend
dart run tool/architecture_guard/architecture_guard.dart
```
