# CI fix plan — runs 38716221458 and 38716225051 (commit `368a33e`)

Self-contained implementation plan. This records only evidence available from the
two CI artifacts, the checkout, and repository history. It intentionally leaves
unobserved causes as unknown; do not turn an inferred failure mode into a product
or security change.

---

## 1. TL;DR

Two workflow runs exercised the same commit:

| Run | Total failures | Frontend | E2E-fullstack | Important qualification |
|---|---:|---:|---:|---|
| `38716221458` | 61 | 18 | 42 | Full frontend test list was attempted; 10 Flutter fullstack cases timed out serially. |
| `38716225051` | 60 | 17 | 42 | Duplicate result except for one fewer frontend failure. |

The durable failure diagnosis is therefore concentrated in **Frontend**, while
runtime diagnosis also includes **E2E-fullstack**. The confirmed code defect is
the patient-update RPC response contract: the database function captures the
updated row but returns only `patient_id`, whereas the Flutter repository requires
`updated_at`. The other Frontend findings need either narrow test setup or a
corroborating authorization trace. The primary recurring E2E cost is also
confirmed: the runner resets local Supabase before every Node step when
`HFS_RESET_SUPABASE=1`.

Do these fixes in dependency order:

1. repair the confirmed patient RPC contract and its contract coverage;
2. resolve the narrowly scoped Frontend authorization/test-fixture discrepancies;
3. add operation-level visibility and cleanup to stalled fullstack startup paths;
4. establish safe isolation boundaries before reducing database resets; and
5. only then tune timeouts using the new evidence.

This plan does **not** recommend raising any timeout. It recommends a lower
startup/readiness timeout only after cleanup and diagnostics make failure reporting
reliable. It does not currently recommend lowering the Flutter per-case cap or the
Node outer-suite timeout.

## 2. Evidence and confidence ledger

| Finding | Evidence | Status | Consequence for implementation |
|---|---|---|---|
| Patient updates reject a successful RPC reply without `updated_at`. | `frontend/lib/features/patients/data/patient_repository.dart` reads `data['updated_at']` and throws the exact reported text when absent. `auth_internal.update_patient` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` uses `RETURNING * INTO v_new`, then returns `rpc_success(jsonb_build_object('patient_id', p_patient_id))` in both definitions. | **Confirmed** | Return `v_new.updated_at` in the success payload; retain `patient_id` and all existing error outcomes. |
| Five patient cases fail in the same way. | CI artifacts report the admin, doctor, receptionist, `updatePatient.success`, and `updatePatient.acknowledgeDuplicate` cases with the identical missing-`updated_at` message. | **Confirmed symptom and root cause** | One contract fix should cover all five; add/update focused response-contract expectations. |
| Unauthenticated cases expected `FORBIDDEN` but received `RPC_NOT_CONFIGURED`. | `frontend/lib/core/rpc/app_rpc_invoker.dart` maps PostgreSQL `42501` and text containing `permission denied` to `RPC_NOT_CONFIGURED`. The CI artifacts do not retain the raw SQLSTATE/message for the affected calls. | **Likely, not confirmed** | Capture the actual response first; then use only an auth-aware mapping or align the test contract. Do not broaden `anon` execute grants. |
| `INVALID_PERMISSION` is bypassed without an active organization. | In `backend/supabase/migrations/20261002150000_tenant_scoping.sql`, `auth_internal.update_role_permission` returns success when `current_org_id()` is null before it validates the permission key. The reported test bootstraps an administrator without binding a clinic/organization. | **Confirmed source behavior; test setup diagnosis is high confidence** | Bind an organization in that test's fixture. Do not reorder tenant-scoped production validation merely to make an unbound fixture fail. |
| Ten attempted Flutter fullstack cases consume exact 600-second windows. | Run `38716221458` contains only `testStart` and generic timeout records, in serial order: five billing cases then the remaining billing/subscription cases. The campaign spans 10:10:08–11:50:41 UTC; 14 cases were inventoried and 10 attempted. | **Confirmed timeout pattern; blocking operation unknown** | Instrument startup, fixture, RPC, and UI-wait boundaries, with bounded operation timeouts. Do not infer that one application operation is slow. |
| Per-file Supabase resets dominate repeated E2E work. | `e2e/fullstack/run_campaigns.py` runs `supabase db reset --local` before each Node step whenever `HFS_RESET_SUPABASE=1`; `.github/workflows/ci.yml` sets that value to `1` for `e2e-fullstack`. The artifacts show two resets in `all-ci` and 33 in `all-manual`; the campaigns took 13m14s and 38m21s respectively. | **Confirmed systematic cost** | Preserve isolation first, then group only proven-compatible files or use targeted cleanup. |
| P5.1 and P5.2 cannot make ABO `:8788` ready. | Their readiness loops poll `/v1/offers` for up to 120 seconds; the artifacts show both never become ready. The Node campaign configs set `test_timeout_ms` to 360000. The log's `Address already in use: 0.0.0.0:8787` is a clue, not proof of the `8788` cause. | **Confirmed symptom; root cause unknown** | Ensure partial startup is cleaned up and emit child-process/port diagnostics before selecting a remedy. |
| P5 partial startup can escape the normal teardown path. | `p5-1.test.mjs` and `p5-2.test.mjs` assign the global `stack` only after `startStack()` returns; their `after` hook calls `stack?.stop()`. A throw while constructing the stack therefore bypasses that normal stack teardown. | **Confirmed cleanup gap** | Make `startStack()` exception-safe with ownership-aware cleanup for every resource already started. |
| `all-manual` did not produce a complete result. | It exited 130 and its output ends at `p7-3-05`; no final campaign result is present. | **Confirmed incompleteness** | Treat it as a runtime/observability issue, not proof that later cases passed or failed. |

### Current-checkout qualification

This plan is about artifacts from `368a33e`; the checkout is later (`6cbf3e78`).
For example, current P5 files already include a 120-second HTTP wait and
process-group shutdown helper, while their `startStack()` functions still need a
failure-path ownership review. Reconfirm exact hunks against the implementation
baseline before editing. Repository history confirms that `368a33e` added
machine output and fullstack attribution, and `6cbf3e78` subsequently added
per-test campaign status logging.

## 3. Ground rules for the implementer

1. Start from the intended implementation commit and a clean tree. This plan is
   an analysis artifact, not authorization to modify unrelated CI plumbing.
2. Keep application correctness and authorization in PostgreSQL. The patient
   response change is a database RPC contract correction; Flutter consumes it.
3. Do not grant `anon` broad execute permission, weaken RLS, or treat a missing
   migration/permission configuration error as an authorization denial without
   recording the original error.
4. Preserve E2E isolation. A reset reduction must name the file group, its
   shared state, its cleanup mechanism, and the test proving no cross-file leak.
5. Add diagnostics before timeout reductions. A shorter timeout without a
   progress marker merely hides the blocking boundary.
6. Keep changes phase-local and independently reviewable. No speculative
   refactors, global timeout changes, or concurrent rework of the same harness
   function.

### Constitution gate

The proposed work introduces no service, queue, or new architecture. It preserves
the Flutter/Supabase/PostgreSQL boundary, keeps tenant/authorization behavior in
the backend, and improves failure cleanup in the existing local test harness.
Any proposed authorization change must be rechecked against the backend-authority
and tenant-isolation principles before merge.

## 4. Phased plan

### P1 — Correct the patient-update RPC response contract

**Depends on:** none.
**Confidence:** confirmed.

1. Locate every live `auth_internal.update_patient` definition introduced or
   replaced by `20261007180000_issuer_key_custody.sql`; the current migration has
   two matching success-return paths.
2. Change only the successful `rpc_success` data to include the timestamp from
   the `RETURNING * INTO v_new` row, alongside the existing `patient_id`.
   Preserve duplicate, concurrency, validation, not-found, authorization, and
   audit behavior.
3. Update the RPC response contract and focused test expectations so a successful
   update verifies a parseable `updated_at`, not merely a non-null payload.
4. Confirm the Flutter repository continues to parse the UTC timestamp without a
   client-side fallback or locally generated time.

**Why this is first:** it is the only direct source-to-symptom match and unblocks
five failures without changing permission or test-harness behavior.

**Exit criterion:** all five affected cases observe the persisted server timestamp;
error payloads remain unchanged.

### P2 — Resolve Frontend contract/setup discrepancies without weakening auth

**Depends on:** P1 may be merged independently; P2.1 and P2.2 are otherwise
independent.

#### P2.1 — Unauthorized RPC classification

1. Add test-visible, non-secret diagnostic capture of the raw PostgREST code and
   relevant message/classification for the two failing unauthenticated calls.
2. Reproduce/inspect the response and decide between these mutually exclusive
   outcomes:
   - if an authenticated/anonymous access denial reaches the client as `42501` or
     `permission denied`, map that narrowly to the documented authorization
     result for unauthenticated callers; or
   - if the grant/function really is absent or misconfigured, retain
     `RPC_NOT_CONFIGURED` and correct the test expectation/configuration.
3. Scope any mapping by authorization context and documented RPC semantics. Do
   not map every `42501` to `FORBIDDEN`, because that would conceal deployment
   misconfiguration.

**Exit criterion:** the two tests have an evidenced expected code and a missing
function/grant still produces an actionable configuration classification.

#### P2.2 — Tenant-bound role-permission fixture

1. Change only the failing test fixture to bootstrap and bind an organization/
   clinic before requesting an invalid permission.
2. Assert `INVALID_PERMISSION` with a valid tenant context.
3. Keep the existing null-organization early success behavior unless a separate
   product requirement says that unbound administrative calls must fail.

**Exit criterion:** the test exercises the catalog-validation branch it claims to
cover, and existing unbound-session behavior is not silently changed.

### P3 — Make Flutter fullstack timeouts diagnosable

**Depends on:** none, but complete before any Flutter timeout adjustment.

1. In `administrator_billing_fullstack_test.dart` and
   `administrator_subscription_fullstack_test.dart`, add concise progress markers
   around stack readiness, login/fixture setup, each remote operation, and each
   polling/UI wait. Markers must identify the case and operation, never emit
   tokens, patient data, or credential material.
2. Wrap known potentially blocking operations in targeted timeouts with an error
   naming the operation and its configured bound. Do not apply one blanket short
   timeout to an entire test case.
3. Ensure marker emission survives `--machine` output parsing and that a failed
   operation is attributed to the current test rather than treated as an opaque
   runner stall.
4. First use the collected marker timeline to identify the blocked boundary. It
   is currently unknown whether the cause is a stack startup, RPC, fixture,
   poll, or UI synchronization operation.

**Exit criterion:** another timeout points to one bounded operation rather than
only `testStart` followed by a generic timeout.

### P4 — Make E2E P5 startup failure-safe and observable

**Depends on:** none; complete before P5 or P6.

1. In P5.1/P5.2 startup code, register every worker, spawned child, mock, and
   temporary resource as soon as it is created. On any later startup failure,
   stop/dispose resources in reverse order, then rethrow the original error.
2. Preserve the normal `after` cleanup while making it idempotent; a failed
   startup must not leave a worker holding `8787`, `8788`, or an inspector port.
3. Add bounded startup diagnostics: command/config identity (not secrets), child
   exit code/signal, last stdout/stderr tail, selected port bindings, and the
   readiness endpoint/status. Capture enough to distinguish an early child exit,
   incorrect host/header, and a port collision.
4. Keep the P5 readiness endpoint (`/v1/offers`), host header, and accepted
   unauthenticated response statuses explicit. Do not change them simply because
   readiness currently fails.
5. Investigate the reported `0.0.0.0:8787` address-in-use line only after this
   instrumentation exists. It may describe a platform-worker collision and does
   not establish why ABO `:8788` never became ready.

**Exit criterion:** a P5 startup failure cleans up all started resources and the
log identifies whether the fault was spawn, bind, boot, or readiness behavior.

### P5 — Reduce E2E reset cost only within proven isolation domains

**Depends on:** P4, plus a written state inventory for every proposed group.

1. Inventory each `all-ci` and `all-manual` file's Supabase mutations, expected
   initial state, process-owned state (`.wrangler`, ports, D1 persistence), and
   cleanup behavior.
2. Partition files into compatibility groups only where targeted fixture cleanup
   demonstrably replaces a full `supabase db reset --local`. Retain the full reset
   between groups and for any file that cannot prove isolation.
3. Implement a group boundary in `e2e/fullstack/run_campaigns.py`; keep the
   reset behavior opt-in through `HFS_RESET_SUPABASE=1` and leave Frontend outside
   that path.
4. Emit reset/group timing and a clear group label so future CI artifacts can
   distinguish reset overhead from test execution time.

**Exit criterion:** selected compatible groups run without cross-file state leaks;
incompatible files still receive a clean database. Compare total reset count and
elapsed time to the baseline (two resets in `all-ci`, 33 in `all-manual`).

### P6 — Decide timeout changes from post-diagnostic evidence

**Depends on:** P3 for Flutter, P4 for P5/Node, and P5 before judging overall
E2E runtime.

#### Timeout distinction and recommendation

| Layer | Observed/configured value | What it bounds | Recommendation now | Reason and dependency |
|---|---|---|---|---|
| Flutter fullstack case | The failing artifact shows exact **600s / 10m** case windows. The later checkout explicitly passes `flutter test --timeout 6m` in `frontend/tool/run_campaigns.py`; `frontend/tool/campaigns/fullstack.json` has no timeout override. | A Flutter test case / runner behavior, not E2E Node startup. | **Do not lower yet.** | The 600s enforcement mechanism at `368a33e` is not fully established and the blocking operation is unknown. P3 must identify it first; otherwise a smaller cap can mask a legitimate cold start. |
| E2E Node outer suite | `all-ci.json` and `all-manual.json` specify `test_timeout_ms: 360000` (**6m**). | The Node `--test` suite ceiling. | **Do not lower yet.** | P5.1/P5.2 can spend a 120s readiness wait and then suffer leaked workers; the outer cap is currently absorbing a startup failure, not measuring normal test work. Re-evaluate after P4. |
| P5 ABO readiness | `waitForHttp` defaults to **120s** while polling `http://127.0.0.1:8788/v1/offers`. | A specific, known startup boundary. | **Lower only after P4, initially to a measured normal-startup budget with diagnostic output (provisional candidate: 30s).** | This is the one boundary where failure should be fast once process cleanup and child diagnostics exist. Retain enough headroom for an intentional cold local Worker start; select the final value from several clean runs, not from the failure artifact. |

The order matters: P4 cleanup/diagnostics → establish normal P5 startup latency →
shorten the readiness wait if the latency budget supports it → rerun P5 → only
then reconsider the 360-second Node ceiling. P3 follows the analogous sequence
for Flutter. Never lower all three settings together; that would make the
resulting failure source ambiguous.

**Exit criterion:** every changed timeout names the operation it protects,
documents normal-run latency evidence, and fails with an actionable diagnostic.

## 5. Shared-file and conflict checks

| Change area | Potential interaction | Required guard |
|---|---|---|
| Patient RPC payload and Flutter repository | Backend returns a new success field; client already requires it. | Preserve `patient_id` and error shape; version/contract test the new field. |
| Auth mapping and RPC grants | A broad mapping or an `anon` grant could mislabel unsafe access/configuration behavior. | Inspect raw failure first; use context-specific mapping; do not broaden grants. |
| Role fixture and tenant function | A production-function reorder would alter unbound-session semantics. | Bind an organization in the test instead; leave production behavior untouched. |
| Flutter instrumentation and timeout | New operation-level bounds could create a shorter effective cap. | Add markers first and record each bound; do not change the global case cap in P3. |
| P5 cleanup and readiness timeout | Cleanup changes process lifetime; a shorter readiness wait changes observed failure timing. | Land/validate cleanup and diagnostics before adjusting the 120-second wait. |
| E2E grouping and reset reduction | Reused Supabase state can contaminate later tests. | Require a state inventory and targeted cleanup per group; retain reset barriers where uncertain. |
| P5 process cleanup and other fullstack files | Shared ports/persistence can make stale children affect P7 or Flutter runs. | Dispose by owned process/resource, use idempotent cleanup, and log port ownership. |

The proposed P1, P2.1, P2.2, P3, P4, and P5 edits do not inherently conflict:
they affect distinct contracts, fixtures, or harness scopes. The principal risk is
sequencing, not a textual merge conflict. Keep P4 and P6 separate so a timeout
reduction cannot conceal a cleanup regression.

## 6. Success criteria

1. The five patient-update cases receive a server-generated, parseable
   `updated_at` and preserve all current error behavior.
2. The two unauthenticated assertions have a raw-error-backed expected result;
configuration failures remain distinguishable from access denials.
3. `INVALID_PERMISSION` is tested with an active organization and reaches the
catalog validation path.
4. A Flutter fullstack failure identifies its last completed operation; no test
remains a ten-minute opaque `testStart`/timeout sequence.
5. P5.1/P5.2 startup failures clean up every child/resource and contain enough
diagnostics to identify the failed phase. The actual cause of `:8788` readiness
is either fixed with evidence or remains explicitly recorded as unresolved.
6. E2E reset count/time falls only where isolation tests demonstrate safety; no
file relies on accidental state from a predecessor.
7. Any timeout reduction fails faster with a specific operation name and does
not reject measured healthy cold starts.
8. `all-manual` reaches a final result rather than exit 130 with a truncated
artifact.

## 7. Later validation — list only, do not run as part of this planning task

Run these after the relevant implementation phases, in the listed order. They
are intentionally not executed while authoring this document.

```bash
# Static/targeted checks after P1/P2/P3/P4/P5 edits
git diff --check
python -m py_compile frontend/tool/run_campaigns.py e2e/fullstack/run_campaigns.py
node --check e2e/fullstack/test/p5-1.test.mjs
node --check e2e/fullstack/test/p5-2.test.mjs

# Focused campaign validation through the repository governor
python3 test/run_campaigns.py frontend all
python3 test/run_campaigns.py frontend fullstack
python3 test/run_campaigns.py e2e-fullstack p5-1
python3 test/run_campaigns.py e2e-fullstack p5-2
python3 test/run_campaigns.py e2e-fullstack all-ci
python3 test/run_campaigns.py e2e-fullstack all-manual

# CI/manual-campaign equivalents once targeted work is ready
gh workflow run manual-campaign.yml --ref <implementation-branch> -f area=frontend -f subcampaign=fullstack
gh workflow run manual-campaign.yml --ref <implementation-branch> -f area=e2e-fullstack -f subcampaign=all-ci
gh workflow run manual-campaign.yml --ref <implementation-branch> -f area=e2e-fullstack -f subcampaign=all-manual
```

For each run, inspect the machine/log artifacts rather than counts alone:

- patient cases: payload contains `updated_at` and no altered error codes;
- authorization: raw source error and final app error classification agree;
- Flutter: progress markers identify each bounded operation;
- P5: startup diagnostic and child cleanup appear on both success and failure;
- E2E: report reset/group count, total elapsed time, and full final result;
- `all-manual`: verify a terminal campaign summary and no exit-130 truncation.

## 8. Unknowns and stop conditions

- The source of the historical Flutter 600-second cap at `368a33e` is not fully
  proven by the later checkout. Do not change that cap until P3 shows the command
  and operation timeline from a comparable run.
- The SQLSTATE/message behind the two `RPC_NOT_CONFIGURED` results is absent from
  the supplied artifacts. Do not change grants or global mapping before it is
  captured.
- The reason ABO never becomes ready on `:8788` is unknown. `:8787` address
  contention is only a lead. Stop and report if diagnostics show a different
  child exit/bind/configuration cause.
- `all-manual` has no final result. Do not classify unreported later tests as
  passing, failing, or skipped.
- If a proposed reset group cannot state its expected initial data and cleanup,
  keep the reset; optimization is not justified.
