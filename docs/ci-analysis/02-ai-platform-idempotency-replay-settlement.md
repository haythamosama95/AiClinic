# Agent B — idempotent replay / settlement / envelope failures (around 771ceed7)

HEAD = `953e5e6e`. All line numbers are HEAD line numbers unless stated otherwise.
Scratch evidence in this folder: `B-771-src.diff`, `B-771-specs.diff`, `B-953.diff`,
`B-admission-before.ts`, `B-quota-do-before.ts` (771ceed7^ versions), `B-extract.js`
(per-test log extractor), `B-keyreuse.js` (key-reuse scanner).

## TL;DR

There are three independent root causes. **None of them needs a product-code change.** The product behaviour at HEAD matches the HEAD spec.

| # | Root cause | Tests | Fix type |
|---|---|---|---|
| A | The test harness builds a **different request body on every call** (`visit_id: randomUUID()`, `recorded_at: new Date()`). Since 771ceed7 the replay is bound to a request fingerprint that includes the filtered context, so the "replay" is a *different request under the same key* → 409 `idempotency_conflict` (correct per FR-015). | S09-068, S09-069, S10-016, S10-018, S10-019, S11-013, S11-014, S11-015, SYS-5.5 (retry half), SYS-5.6, SYS-7.4 | Harness: memoise the visit context per installation (2 edits) |
| B | E2E-P3.4-11 replays with the **same token (same jti)**. 771ceed7 removed the D1 short-circuit that ran before the DO's jti check, so a repeated jti is now 401 (the spec now mandates this). The test was not updated. | E2E-P3.4-11 | Test: mint a fresh token for the idempotency replay |
| C | **Settlement is read before it lands.** Completed and cancelled settlement runs in `waitUntil` after the SSE terminal event. Its last write is `ai_request.payload_pointer`. Tests read after a fixed 150–200 ms sleep, or reuse a row snapshot taken when `state` flipped (state is written earlier, by the broker). | S10-001, S11-002, S11-010, SYS-7.1, SYS-7.3, SYS-8.1, E2E-P3.4-01, SYS-5.5 (first half) | Tests: poll until `payload_pointer` is set (the last settlement write), or re-read the row |

`ci-failure-analysis-run-38695681551.md` says the 409s are a "product bug in replay path" (line 183). **That is wrong.** The product correctly rejects a changed body. See the evidence in A.

---

## 1. Replay path at HEAD and the exact 409 cause

### 1.1 Fingerprint (pipeline)

`ai-platform/src/pipeline/index.ts:462-470`: the fingerprint is SHA-256 (`hashCanonicalJson`) of

```ts
{ capabilityId, capabilityVersion, userIntent, context: filteredContext, transcript, conversationId, turnOrdinal }
```

It is passed to `runAdmission` (line 500) and stored by `createRequestRow` (line 594, then `journal/index.ts:244-273` binds `input.requestFingerprint ?? null`).

`filteredContext` keeps every field declared by the shape. `context/shapes/published/visit.chief_complaint@v1.json` declares `visit_id` (required, uuid), `complaint` and `recorded_at` (optional). So **`visit_id` and `recorded_at` are part of the fingerprint.**

### 1.2 Admission (worker side)

`ai-platform/src/admission/index.ts:636-684`:

```ts
const idempotencyBinding = requestFingerprint === undefined ? undefined : {
  actorId: principal.actorId, branchId: principal.branchId, capabilityId, requestFingerprint };
const journaledBindingMatches = journaled !== null && idempotencyBinding !== undefined &&
  journaled.actor_id === idempotencyBinding.actorId && journaled.branch_id === idempotencyBinding.branchId &&
  journaled.capability_id === idempotencyBinding.capabilityId &&
  journaled.request_fingerprint === idempotencyBinding.requestFingerprint;
...
...(journaled !== null && !journaledBindingMatches ? { journaledConflict: true } : {}),
```

- If the bindings match, a `journaledAnswer` is sent (built by `idempotentFromJournal`, lines 156-170, which carries `traceId: row.trace_id` and `terminalErrorCode`).
- If they don't match, `journaledConflict: true` is sent.

### 1.3 Quota DO

`ai-platform/src/quota-do/index.ts` `admitOnHotRow` (~1244-1290) checks, in order:

1. `hot.replay[jti]` → outcome `replay` → **401 `unauthenticated`**
2. `journaledConflict` → **`idempotency_conflict`**
3. `hot.idempotency[key]` → if `sameIdempotencyBinding` fails → conflict; otherwise the stored answer
4. `journaledAnswer` → `idempotent`

`src/errors.ts` maps `idempotency_conflict` to **409**, not retryable.

### 1.4 Why the failing tests send a different fingerprint

`ai-platform/test/e2e/harness/clinic.ts:17-36` (and its twin `ai-platform/test/system/harness.ts:820-839`):

```ts
"visit.chief_complaint@v1": {
  visit_id: crypto.randomUUID(),          // system harness: randomUuid()
  complaint: "Persistent headache.",
  recorded_at: new Date().toISOString(),
},
```

Every failing replay test calls a body builder **twice**: once for the original request and once for the replay. The second fingerprint ≠ the stored `ai_request.request_fingerprint`, so `journaledConflict` is set and the response is 409.

| Test | Original body | Replay body | 409 at |
|---|---|---|---|
| S09-068 | `happyVisitBody(scenario)` stage-09-admission-journal-compose.test.ts:705 | `happyVisitBody(scenario)` :722 | :725 |
| S09-069 | :753 | :770 | :773 |
| S10-016 | local `postVisit` (stage-10-route-retry-idempotency.test.ts:200-216, always `visitBody(scenario)`, no body param) | same | `assertHttpSse` :379 via :1416 |
| S10-018 / S10-019 | local `postVisit` (stage-10-prose-guard-stream.test.ts:179-193, always `visitBody`) / inline `visitBody(scenario)` :702 | `postVisit` | :653 / :735 |
| S11-013/014/015 | helpers `completeHappyRequest` (:590), `failEmptyChain` (:606, no body param), `cancelInFlight` (:715 `body: visitBody(scenario)`) | `postVisit` → `opts.body ?? visitBody(scenario)` (:388-407) | :922 / :957 / :995 |
| SYS-5.5 retry | `invoke(scenario,…)` default `visitSummaryInvokeBody` | same | quota-admission-interplay.system.test.ts:273 |
| SYS-5.6 | default body / `visitSummaryInvokeBody(cancelledScenario)` :359 | default body | `events[1]` undefined at :323 (409 JSON) |
| SYS-7.4 | helpers / default body | `invoke(scenario,{idempotencyKey})` | settlement-integrity.system.test.ts:469 |

### 1.5 Decisive evidence that this is the body, not the product

- **Every currently-passing replay test reuses one body object. Every failing one regenerates it.** The `B-keyreuse.js` scan of e2e, system and version-matrix found that all within-test key reusers fall into the same split:
  - S08-053 (`const body = happyVisitBody(scenario)` :482, reused at :488 and :496);
  - S09-066 (:581, reused);
  - S09-067 (reuses `const body`);
  - S10-017 (single body);
  - S09-065 (reuses `requestBody`).
  - All of these PASS at HEAD. All tests that rebuild the body FAIL with 409.
- **S09-065** (stage-09-capability-context-preflight.test.ts) passes at HEAD and *asserts* the new semantics:
  - same token + same key → 401;
  - fresh token + same body → stored answer;
  - changed `user_intent` → **409 `idempotency_conflict`**;
  - the conflict token replayed → 401.
- In the pre-771ceed7 run (`artifacts/katest-run-38534344174`, Oct 14 08:20) **all** of the 409 tests passed. Back then the old admission short-circuited on D1 before any binding check (`B-admission-before.ts`: `if (journaled) return idempotentFromJournal(journaled)`), so body changes were invisible.

### 1.6 Correct semantics (from the HEAD spec, changed in 771ceed7)

- specs/068 `spec.md` FR-002/FR-015, `contracts/admission-answer.md`, `contracts/clinic-denial-codes.md`, `data-model.md` §4, `plan.md`, `tasks.md` T011/T015/T022, `quickstart.md`;
- `docs/architecture/ai-billing-orchestration` 03 §6.2 step 1 and 06 E2E-P3.4-11.

Together these say:

- A repeated `jti` → 401 `unauthenticated`, **even if D1 has the answer**.
- A fresh `jti` + the same key + the same `{actor, branch, capability, fingerprint}` → the stored answer, with no new inference, no new journal rows and no credit.
- A fresh `jti` + the same key + a different scope or fingerprint → **409 `idempotency_conflict`**.
- Historical rows with no fingerprint are not replayed: they give a conflict.

Original 03 §6.2 text, replaced in 771ceed7: *"Return a stored answer for a replayed `jti` or idempotency key, without writing."* The test title E2E-P3.4-11 still quotes the old text. `tasks.md` T011 says "The quoted test title is historical".

Excluding `visit_id` or `recorded_at` from the fingerprint would be wrong: a different visit is a different request. Real clients resend the identical body. **The tests are wrong, not the product.**

### 1.7 Inventory

**Tests that assert a conflict (409 / `idempotency_conflict`):**
- S09-065, the changed-`user_intent` leg;
- `test/taxonomy.test.ts` / `test/error-body.test.ts`, the code→409 mapping only.

No other test asserts 409 on replay.

**Tests that assert replay success (stored answer):**
- *e2e:* S08-053, S09-066, S09-067, S09-068, S09-069, S10-016, S10-017, S10-018, S10-019, S11-013, S11-014, S11-015, SX-047 (direct DO RPC with no binding, so unaffected).
- *system:* SYS-5.5, SYS-5.6, SYS-7.4, E2E-P3.4-11.
- *workers/unit:*
  - `pipeline.test.ts` "stage 8 — duplicate idempotency key" (1124-1167; fixed context at 658-667);
  - `worker-request-orchestrator.test.ts` T15 (1168-1189; fixed context, fresh token);
  - `admission-credit.test.ts` `admission_repeated_key_no_second_inference` (719-767) and `grace_idempotency_key_replay_during_do_outage` (no journal row).

---

## 2. E2E-P3.4-11: the 401

`ai-platform/test/system/admission-settlement.system.test.ts:719-775`:

```ts
const token = await mintAat(scenario);
const first = await invoke(scenario, { token, idempotencyKey });
...
const replayIdempotency = await invoke(scenario, { token, idempotencyKey });   // :734
expect(replayIdempotency.status).toBe(first.status);                            // fails: 401
```

1. The same `token` means the same `jti`. After the first request, `hot.replay[jti]` holds that jti, and `admitOnHotRow` step 1 returns `replay`, which maps to 401.
2. Before 771ceed7, admission returned `idempotentFromJournal(journaled)` before calling the DO, which hid the jti replay.
3. The HEAD spec (plan.md, tasks.md T011, 06 E2E-P3.4-11) and S09-065 (`replaySameTokenAndKey` → 401) require 401.
4. Even with a fresh token, the replay body is regenerated (`invoke` default body), so it would hit 409 (root cause A).

The second half of the test (the same jti with a new key → 401, hot row unchanged) already matches the new spec.

A second, latent issue: the replay compares `completed` events, which come from the R2 envelope. If the envelope isn't written yet, `replayIdempotentTerminal` (worker.ts:881-949) serves the placeholder text. So the replay must wait for settlement (root cause C).

---

## 3. Classifying the "null pointer / missing row" failures (root cause C)

### Settlement ordering after the SSE terminal event

1. The broker's `journalTerminalSink` → `recordTerminalState` writes `state = Completed/Cancelled` **first**, during the stream.
2. `worker.ts:1186-1390`, scheduled via `executionCtx.waitUntil` (`runFreshEventSource`, 1008-1030): `await brokerRun; await brokerCredit`.
3. Then `settleCompletedRequest` → `creditUsage` (DO RPC) → `writeSettlementJournal` (717-758, awaits `ctx.drainWaitUntil()`).
4. Then `persistPostResponseDetail` (journal/index.ts:384-442): D1 batch (`ai_attempt` rows + `INSERT OR IGNORE usage_event`) → `r2.put(envelope)` → **`UPDATE ai_request SET payload_pointer` (the last write)**.

On the Failed path, `settleTerminal` runs **before** `recordTerminalState(Failed)` and before the SSE `failed` event, so Failed settlement has no race.

Harness waits are fixed sleeps:
- system `flushBackgroundWork` = 150 ms (harness.ts:863-865);
- e2e = 150 ms (env.ts:130);
- `postVisit` in stage 10 = 200 ms.

### Verified from logs and source (not assumed)

- **No `stage16_post_response_detail_failed` and no `missing_term_admission_for_settlement` appear anywhere in the e2e or system logs.** So the writes don't fail; they are late.
- In S11-010 and SYS-7.3, the **polled** assertions on attempts and usage PASS in the same test. Only the later read of the **stale snapshot's** `payload_pointer` fails. That proves settlement landed, and the test used an old row.
- E2E-P3.4-01, SYS-8.1, SYS-7.1, SYS-7.3, S11-002 and S11-010 **were already failing in the pre-771ceed7 run** (katest-run-38534344174). So they are not caused by the fingerprint work.
- S10-001 passed then and fails now. It is the same 200 ms race. It may have been made more likely by the vitest-pool-workers upgrade in 953e5e6e (0.8.71 → 0.12.21), but that is not proven.
- e1a42092 and cb99ded0 touch only abo/backend/e2e-fullstack/vendor-contracts, not ai-platform. They are irrelevant.

| Test | Decisive line | Class |
|---|---|---|
| S10-001 (stage-10-route-retry-idempotency.test.ts:475-493) | `expect(row.payload_pointer)` null at :493, after `postVisit`'s 200 ms flush. The briefing's "request_reference null" is really `payload_pointer`. | timing (pointer not yet written) |
| S11-002 (stage-11-completed-failed-cancelled.test.ts:811-880) | `requireAiRequest(ref)` :860 → `getAttempts` :862 → `toHaveLength(1)` :863 fails. The `waitForUsageEvent` poll that 953e5e6e added at :866 sits *after* the un-polled read. | timing (poll in the wrong place) |
| S11-010 (1480-1602) | `row` taken at :1537 by `waitForLatestRequestState(...,"Cancelled")`. Attempts (2) and usage (1) polls pass at 1555-1589. `getR2Json(String(row.payload_pointer))` :1591 fails with "R2 object not found: null". 953e5e6e removed the `flushBackgroundWork(350)` before it. | stale snapshot |
| SYS-7.1 (settlement-integrity.system.test.ts:123+) | `payload_pointer` null at :133. `completeRequest` (73-89) has only a 150 ms flush. | timing |
| SYS-7.3 (~255-334) | State poll (stale row) and usage poll OK. `r2Exists(String(request?.payload_pointer))` :330 is false. | stale snapshot |
| SYS-8.1 (cron-retention-interplay.system.test.ts:39-97) | `usageBefore` null at :60 after invoke + 150 ms flush (44-46). | timing |
| E2E-P3.4-01 (admission-settlement.system.test.ts:322-374) | `getUsageEvents` empty at :368-369 after a 150 ms flush. | timing |
| SYS-5.5 first half | `getR2Json(pointer null)` :266 | timing (then root cause A on retry) |

None of these is a fingerprint bug.

---

## 4. Git history

- **771ceed7:**
  - Added the fingerprint binding (pipeline, admission, journal, quota-do, worker `assertAdmissionArgs` 1572-1601), migration `20261014120000_ai_request_idempotency_fingerprint.sql`, and the spec changes listed in §1.6.
  - Removed the D1 short-circuit.
  - Updated S09-065 to the new semantics.
  - Did **not** update the replay tests that regenerate bodies, did not update E2E-P3.4-11, and did not add the migration to the many workers-pool test setups or to `abo/test/system/cross-worker-harness.ts`.
- **953e5e6e:**
  - Upgraded vitest-pool-workers 0.8.71 → 0.12.21 and added `retry: 1` to the workers and e2e configs.
  - Changed waits in stage-11 (removed the `flushBackgroundWork(350)` in S11-010; added `waitForUsageEvent` in S11-002 after the bad read).
  - `retry: 1` cannot rescue deterministic 409s. It only masks some timing failures.
- **e1a42092, cb99ded0:** not ai-platform; no bearing on this scope.

---

## 5. The fix (single coherent change set; test-only)

### F1 — deterministic visit context per installation (fixes root cause A)

Two edits. Both are harness files. The e2e `harness/index.ts` barrel is "frozen" against *new files*; this edits an existing exported function and keeps its signature.

**`ai-platform/test/e2e/harness/clinic.ts` lines 17-36.** Before:

```ts
export function visitSummaryInvokeBody(
  scenario: Scenario,
  ...
): ... {
  ...
      "visit.chief_complaint@v1": {
        visit_id: crypto.randomUUID(),
        complaint: "Persistent headache.",
        recorded_at: new Date().toISOString(),
      },
  ...
}
```

After: add a module-level memo directly above the function, and use it in the context.

```ts
const visitContextByInstallation = new Map<
  string,
  { visitId: string; recordedAt: string }
>();

function visitContextFor(installationId: string): { visitId: string; recordedAt: string } {
  let visit = visitContextByInstallation.get(installationId);
  if (visit === undefined) {
    visit = { visitId: crypto.randomUUID(), recordedAt: new Date().toISOString() };
    visitContextByInstallation.set(installationId, visit);
  }
  return visit;
}
```

and inside `visitSummaryInvokeBody`:

```ts
      "visit.chief_complaint@v1": {
        visit_id: visitContextFor(scenario.installationId).visitId,
        complaint: "Persistent headache.",
        recorded_at: visitContextFor(scenario.installationId).recordedAt,
      },
```

**`ai-platform/test/system/harness.ts` lines 820-839.** Make the identical change, using the file's own `randomUuid()` (defined at :313) in place of `crypto.randomUUID()`.

Why this is safe:
- Each scenario has a unique installation id, so bodies stay unique *across* scenarios.
- Within a scenario, distinct requests already use distinct idempotency keys, so an identical body under a different key is a fresh request.
- S09-065's explicit `user_intent` change still produces 409.
- All currently-passing reusers already send identical bodies (§1.5).
- No test asserts that two default bodies differ. I checked every `visit_id` reference: other files use fixed or own values.

**Fallback F1' (if the coordinator refuses to touch the frozen e2e harness):** thread one `const body = visitBody(scenario)` through each failing test.
- Add a `body?: string` param to:
  - stage-10-route-retry `postVisit` (200-216);
  - stage-10-prose-guard `postVisit` (179-193);
  - stage-11-replay `failEmptyChain` (606) and `cancelInFlight` (677; :715).
- Pass the same body to the original and the replay in:
  - S09-068 (:705/:722), S09-069 (:753/:770);
  - S10-016, S10-018, S10-019 (:702);
  - S11-013/014/015.
- For the system tests, pass `body` into `invoke` and the helpers.

That is about 15 e2e plus 6 system edits. It is more error-prone; F1 is preferred.

### F2 — E2E-P3.4-11 uses a fresh token (fixes root cause B)

**`ai-platform/test/system/admission-settlement.system.test.ts`.** Before (:734):

```ts
    const replayIdempotency = await invoke(scenario, { token, idempotencyKey });
```

After (insert the settlement wait from F3, then mint a new token):

```ts
    await waitForSettledRequest(String(first.events[0]?.data.request_reference));
    const replayIdempotency = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey,
    });
```

`waitForSettledRequest` must be added to this file's harness import. If the test reads the reference differently, use the variable it already has.

Optional, recommended for spec traceability (plan.md / 06 E2E-P3.4-11): also assert `invoke(scenario,{token,idempotencyKey})` → 401. The briefing's semantics are already covered in e2e by S09-065.

### F3 — wait for the last settlement write (fixes root cause C; hardens the A/B replays)

**System harness: new export in `ai-platform/test/system/harness.ts`**, placed after `getUsageEvents` (:1213-1215):

```ts
export async function waitForSettledRequest(
  requestReference: string,
  timeoutMs = 8000,
): Promise<Record<string, unknown>> {
  const started = Date.now();
  for (;;) {
    const row = await getAiRequest(requestReference);
    if (row !== null && typeof row.payload_pointer === "string" && row.payload_pointer.length > 0) {
      return row;
    }
    if (Date.now() - started > timeoutMs) {
      throw new Error(`settlement did not land for ${requestReference}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
```

Adjust the row type to whatever `getAiRequest` returns.

`payload_pointer` is the **last** write of `persistPostResponseDetail`. Once it is set, the `ai_attempt` rows, `usage_event`, the R2 envelope and the credit are all present.

**Call sites (system):**

| File:line (HEAD) | Edit |
|---|---|
| admission-settlement.system.test.ts E2E-P3.4-01, before the reads at ~:365 | `await waitForSettledRequest(ref);` (move the `ref` derivation above it) |
| cron-retention-interplay.system.test.ts SYS-8.1, after :44-46 (before :48) | `await waitForSettledRequest(ref);` |
| quota-admission-interplay.system.test.ts SYS-5.5, before :262 | `const settled = await waitForSettledRequest(ref);` and use `settled.payload_pointer` at :266 |
| quota-admission-interplay SYS-5.6, before the failed and cancelled count snapshots | `await waitForSettledRequest(ref)` (harmless for Failed; needed for Cancelled) |
| settlement-integrity.system.test.ts `completeRequest` (73-89) and `failWithEmptyChain` (91-120) | replace the trailing `flushBackgroundWork()` + row read with `const row = await waitForSettledRequest(ref);` |
| settlement-integrity SYS-7.3, at :330 | `const settled = await waitForSettledRequest(String(request?.request_reference)); expect(await r2Exists(String(settled.payload_pointer))).toBe(true);` |
| settlement-integrity SYS-7.4, ~:419-427 (cancelled row read after flush + 200 ms) | replace the sleep and read with `const cancelledRow = await waitForSettledRequest(cancelledRef);` |

**e2e:** the barrel is frozen, so add **local** helpers, not harness files.

- **`stage-10-route-retry-idempotency.test.ts`.** Add next to the local `requireAiRequest` (~:442):

  ```ts
  async function waitForSettledRow(ref: string): Promise<AiRequestRow> {
    const started = Date.now();
    for (;;) {
      const row = await requireAiRequest(ref);
      if (typeof row.payload_pointer === "string" && row.payload_pointer.length > 0) return row;
      if (Date.now() - started > 8000) throw new Error(`settlement did not land for ${ref}`);
      await flushBackgroundWork(50);
    }
  }
  ```

  Use whatever row type the file's `requireAiRequest` returns.
  - **S10-001:** replace the row read at ~:488 with `const row = await waitForSettledRow(ref);`.
  - **S10-016:** replace :1406 `const firstRow = await requireAiRequest(firstRef);` with `const firstRow = await waitForSettledRow(firstRef);`. Without this, the replay may serve the "Prior request completed." placeholder instead of `FAKE_SUMMARY` (:1421).
- **`stage-11-completed-failed-cancelled.test.ts`:**
  - **S11-002:** at :860, change `const row = await requireAiRequest(ref);` to `const row = await waitForCompletedEnvelope(ref);` (existing in-file helper, 611-635).
  - **S11-010:** at :1591, replace the stale snapshot read with a re-read poll:

    ```ts
    let settledRow = await requireAiRequest(String(row.request_reference));
    const pointerStarted = Date.now();
    while (typeof settledRow.payload_pointer !== "string" && Date.now() - pointerStarted < 8000) {
      await flushBackgroundWork(50);
      settledRow = await requireAiRequest(String(row.request_reference));
    }
    const envelope = await getR2Json(String(settledRow.payload_pointer));
    ```

- **S11-013/014/015, S10-018, S10-019, S09-068:** already wait correctly:
  - `completeHappyRequest` → `waitForCompletedEnvelope`;
  - `waitForFailedSettlement`;
  - `waitForStableCancelledSettlement`;
  - Failed settles before its SSE event.
  - **No change beyond F1.**
- **S09-069:** replays after `flushBackgroundWork(400)` without polling for `Cancelled`. It passed with this wait before 771ceed7; leave it, but it is a residual flake risk (see risks).

### No product changes for these failures

`src/admission`, `src/quota-do`, `src/pipeline` and `src/journal` are behaving per the HEAD spec.

---

## 6. Cross-impact

| Suite | Impact of F1+F2+F3 |
|---|---|
| ai-platform **e2e** | Fixes S09-068/069, S10-016/018/019, S11-013/014/015 (F1) and S10-001, S11-002, S11-010 (F3). S08-053, S09-065/066/067, S10-017 are unchanged: they already reuse a body, and the memo returns the same body. SX-047 replays via direct DO RPC (no binding), so it is unaffected. Default `postRequest` bodies become identical within a scenario. Every multi-request scenario uses distinct keys (`B-keyreuse.js` scan), so this is harmless. |
| ai-platform **system** (npm-test) | Fixes E2E-P3.4-01, E2E-P3.4-11, SYS-8.1, SYS-5.5, SYS-5.6, SYS-7.1, SYS-7.3, SYS-7.4. Other system tests that use `invoke` gain only the deterministic body and are unaffected. |
| ai-platform **unit / workers** | No direct effect (they don't use either harness). **Separate, caused by 771ceed7, out of my scope:** many workers-pool files fail with `D1_ERROR: no such column: request_fingerprint` because their `beforeAll` migration lists lack `20261014120000_ai_request_idempotency_fingerprint.sql`. Once the migration agent fixes that: <br>• `pipeline.test.ts` stage 8 (fixed context 658-667) and `worker-request-orchestrator.test.ts` T15 (fixed context, fresh token) **should pass as written**. <br>• **`admission-credit.test.ts` `admission_repeated_key_no_second_inference` (719-767) will still fail on semantics.** `defaultAdmissionInput` (585-604) has no `requestFingerprint` and `journalAdmittedRequest` writes a NULL fingerprint, so HEAD sends `journaledConflict` and gets `idempotency_conflict`, with one DO fetch, against an expected `fetchCount()===0`. Companion edit: add `requestFingerprint: "f".repeat(64)` to both inputs (extend the overrides type), write the same value into the seeded journal row, and change the expectation to `secondSpy.fetchCount()` = **1** (the spec requires the DO to authorise the fresh jti). The `idempotent`/`priorState` expectation then holds: the DO hot entry matches the binding, so admission calls `selectAiRequestById` → `idempotentFromJournal`. <br>• `migrations.test.ts` schema snapshot drift: migration agent. |
| ai-platform **version-matrix** | `worker-do.system.test.ts` and `channels.system.test.ts` always use `crypto.randomUUID()` keys. Unaffected. |
| ai-platform **eval** | Uses its own conversation/golden harnesses, not `visitSummaryInvokeBody`. Unaffected. |
| **abo** cross-worker/system | Not touched by F1–F3. abo never replays a key (random keys). Its 32 `no such column: request_fingerprint` errors (E2E-P4.9-03, P4.9-05, P4.8-07, P4.4-01) come from `abo/test/system/cross-worker-harness.ts:50-76` `PLATFORM_MIGRATION_SQL` missing the 771ceed7 migration. That belongs to the migration agent. |

---

## 7. Confidence and CI confirmation

| Item | Confidence | CI evidence that confirms the fix |
|---|---|---|
| Root cause A (409s) | **High.** Deterministic; perfect pass/fail split by body reuse; S09-065 asserts 409 on a body change. | After F1, all 11 tests report 200 with `accepted` + the prior terminal. No `idempotency_conflict` in the e2e/system logs for these tests. |
| Root cause B (P3.4-11 401) | **High** | After F2, the replay is 200 and the `completed` event matches the first one. The jti-with-new-key half stays 401. |
| S11-010, SYS-7.3, S11-002 | **High** (same-test polled assertions prove the data landed; only a stale or unpolled read fails) | Passing on the first try (no `retry` in the vitest report) across several runs. |
| S10-001, SYS-7.1, SYS-8.1, E2E-P3.4-01, SYS-5.5 first half | **Medium-high.** No error logs, consistent with a late write; the pool-upgrade latency effect is unproven. | Same, and no `settlement did not land` timeouts. If a timeout fires, look for `stage16_post_response_detail_failed` or credit RPC errors (that would mean a real product failure). |

---

## 8. Open risks

1. **Frozen e2e harness.** F1 edits `test/e2e/harness/clinic.ts`, an existing file; no new files are added. If the coordinator treats the barrel's contents as frozen too, use F1'.
2. **The pool-upgrade latency hypothesis is unproven.** If `waitForSettledRequest` times out at 8 s in CI, settlement is failing silently, not slowly. Investigate `ctx.drainWaitUntil()` under vitest-pool-workers 0.12.21 (`worker.ts:717-758`).
3. **S09-069 residual flake.** It replays after a fixed 400 ms with no poll for `Cancelled`. If D1 still says Admitted, the replay is served as in-flight (accepted only), and the `["accepted","cancelled"]` sequence fails. Optional hardening: `await waitForAiRequestState(ref, "Cancelled")` before the replay.
4. **Latent product bug (not hit by the current failures):** `quota-do/index.ts` `chargeStaleReservations` (1054-1066) writes an idempotent "failed" answer to `hot.idempotency` **without a binding**. A later *bound* replay of that key fails `sameIdempotencyBinding` (undefined vs bound) and gets a 409, though spec FR-015 says it should get the stored failed answer. This needs a product fix: carry the reservation's binding into the swept answer. It's worth a follow-up ticket; no current test exercises it.
5. **`admission-credit.test.ts`.** It stays red after the migration fix unless the companion edit in §6 is applied.
6. **abo cross-worker harness migration list.** The abo failures stay red until the migration agent adds the 771ceed7 migration to `cross-worker-harness.ts:50-76`.
7. **`retry: 1` (953e5e6e).** It masks timing flakes. Once F3 lands, consider removing it so regressions surface.
