# CI Failure Digest (mechanical extraction)

Source: `failures.txt` under `C:/Users/haosama/AppData/Local/Temp/ci-art-full`. Read-only extraction; no interpretation of causes.

---

## Subcampaign: `campaign-abo-38695681551\governor\20261015T065913Z-244b6d47\abo\cross-worker`

- label: `abo/cross-worker` — passed=69 failed=4 exit=1

### Last 60 lines of output.log

```
 ❯ test/system/console-relays.cross-worker.test.ts:1876:28
       |                    ^
    1220|     method: "POST",

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
    1221|     headers: {
Serialized Error: { remote: true }
 ❯ test/system/console-relays.cross-worker.test.ts:1876:28
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[3/4]⎯


⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
 FAIL  test/system/grant.cross-worker.test.ts > grant cross-worker > E2E-P4.4-01 paid grant activates the term and completes an issuer request
Serialized Error: { remote: true }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[3/4]⎯

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 FAIL  test/system/grant.cross-worker.test.ts > grant cross-worker > E2E-P4.4-01 paid grant activates the term and completes an issuer request
 ❯ platformHttpInvoke test/system/grant.cross-worker.test.ts:907:20
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/grant.cross-worker.test.ts:907:20
    905|   const token = await mintIssuerAiToken(org);
    906|   const nowIso = await aboHarnessNowIso();
    905|   const token = await mintIssuerAiToken(org);
    907|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
    906|   const nowIso = await aboHarnessNowIso();
       |                    ^
    908|     method: "POST",
    907|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
    909|     headers: {
       |                    ^
 ❯ test/system/grant.cross-worker.test.ts:1212:30
    908|     method: "POST",
    909|     headers: {

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
 ❯ test/system/grant.cross-worker.test.ts:1212:30
Serialized Error: { remote: true }

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[4/4]⎯
Serialized Error: { remote: true }

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[4/4]⎯



 Test Files  3 failed | 7 passed (10)
      Tests  4 failed | 69 passed (73)
 Test Files  3 failed | 7 passed (10)
   Start at  06:59:16
      Tests  4 failed | 69 passed (73)
   Start at  06:59:16
   Duration  103.34s (transform 2.49s, setup 0ms, collect 20.41s, tests 420.54s, environment 2ms, prepare 7.11s)

   Duration  103.34s (transform 2.49s, setup 0ms, collect 20.41s, tests 420.54s, environment 2ms, prepare 7.11s)

[vpw:debug] Shutting down runtimes...
[vpw:debug] Shutting down runtimes...

```

### Failed / not-recorded tests (5)

#### `NOT_RECORDED` test/system/checkout-throw.cross-worker.test.ts > checkout throw fallback > E2E-P4.2-03 throw and transient use coverage_view

- failure source: `none`

(no matching test in vitest-report.json; no per-test log or log had no error detail; no mention found in output.log)

#### `FAIL` test/system/configuration-relays.cross-worker.test.ts > configuration relays cross-worker > E2E-P4.9-03 issuer-key register, token accept/reject within TTL, retire

- per-test log: `tests/074-test-system-configuration-relays-cross-worker-te.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/system/configuration-relays.cross-worker.test.ts):
```
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
Serialized Error: { remote: true }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[2/4]⎯

 FAIL  test/system/console-relays.cross-worker.test.ts > console relays cross-worker > E2E-P4.8-07 suspend refuses admission and resume restores it
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/console-relays.cross-worker.test.ts:1219:20
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/configuration-relays.cross-worker.test.ts:1224:20
    1222|   });
    1223|   const nowIso = await currentHarnessClockIso();
    1224|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
       |                    ^
    1225|     method: "POST",
    1226|     headers: {
 ❯ test/system/configuration-relays.cross-worker.test.ts:1805:22

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
Serialized Error: { remote: true }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[2/4]⎯

 FAIL  test/system/console-relays.cross-worker.test.ts > console relays cross-worker > E2E-P4.8-07 suspend refuses admission and resume restores it
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/console-relays.cross-worker.test.ts:1219:20
    1217|   });
    1218|   const nowIso = await currentHarnessClockIso();
    1217|   });
    1219|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
       |                    ^
    1218|   const nowIso = await currentHarnessClockIso();
    1220|     method: "POST",
```

#### `FAIL` test/system/configuration-relays.cross-worker.test.ts > configuration relays cross-worker > E2E-P4.9-05 routing publish, canary, fake provider, promote, rollback

- per-test log: `tests/075-test-system-configuration-relays-cross-worker-te.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/system/configuration-relays.cross-worker.test.ts):
```
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
Serialized Error: { remote: true }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[2/4]⎯

 FAIL  test/system/console-relays.cross-worker.test.ts > console relays cross-worker > E2E-P4.8-07 suspend refuses admission and resume restores it
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/console-relays.cross-worker.test.ts:1219:20
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/configuration-relays.cross-worker.test.ts:1224:20
    1222|   });
    1223|   const nowIso = await currentHarnessClockIso();
    1224|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
       |                    ^
    1225|     method: "POST",
    1226|     headers: {
 ❯ test/system/configuration-relays.cross-worker.test.ts:1805:22

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
Serialized Error: { remote: true }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[2/4]⎯

 FAIL  test/system/console-relays.cross-worker.test.ts > console relays cross-worker > E2E-P4.8-07 suspend refuses admission and resume restores it
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/console-relays.cross-worker.test.ts:1219:20
    1217|   });
    1218|   const nowIso = await currentHarnessClockIso();
    1217|   });
    1219|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
       |                    ^
    1218|   const nowIso = await currentHarnessClockIso();
    1220|     method: "POST",
```

#### `FAIL` test/system/console-relays.cross-worker.test.ts > console relays cross-worker > E2E-P4.8-07 suspend refuses admission and resume restores it

- per-test log: `tests/076-test-system-console-relays-cross-worker-test-ts.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/system/console-relays.cross-worker.test.ts):
```
    1218|   const nowIso = await currentHarnessClockIso();
    1217|   });
    1219|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
       |                    ^
    1218|   const nowIso = await currentHarnessClockIso();
    1220|     method: "POST",
    1221|     headers: {
    1219|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
 ❯ test/system/console-relays.cross-worker.test.ts:1876:28
       |                    ^
    1220|     method: "POST",

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
    1221|     headers: {
Serialized Error: { remote: true }
 ❯ test/system/console-relays.cross-worker.test.ts:1876:28
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[3/4]⎯


⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
 FAIL  test/system/grant.cross-worker.test.ts > grant cross-worker > E2E-P4.4-01 paid grant activates the term and completes an issuer request
Serialized Error: { remote: true }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[3/4]⎯

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 FAIL  test/system/grant.cross-worker.test.ts > grant cross-worker > E2E-P4.4-01 paid grant activates the term and completes an issuer request
 ❯ platformHttpInvoke test/system/grant.cross-worker.test.ts:907:20
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/grant.cross-worker.test.ts:907:20
    905|   const token = await mintIssuerAiToken(org);
    906|   const nowIso = await aboHarnessNowIso();
```

#### `FAIL` test/system/grant.cross-worker.test.ts > grant cross-worker > E2E-P4.4-01 paid grant activates the term and completes an issuer request

- per-test log: `tests/077-test-system-grant-cross-worker-test-ts-grant-cro.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/system/grant.cross-worker.test.ts):
```
    905|   const token = await mintIssuerAiToken(org);
    906|   const nowIso = await aboHarnessNowIso();
    905|   const token = await mintIssuerAiToken(org);
    907|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
    906|   const nowIso = await aboHarnessNowIso();
       |                    ^
    908|     method: "POST",
    907|   const response = await env.PLATFORM_HTTP.fetch(`${GATEWAY_ORIGIN}/v1…
    909|     headers: {
       |                    ^
 ❯ test/system/grant.cross-worker.test.ts:1212:30
    908|     method: "POST",
    909|     headers: {

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
 ❯ test/system/grant.cross-worker.test.ts:1212:30
Serialized Error: { remote: true }

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[4/4]⎯
Serialized Error: { remote: true }

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[4/4]⎯



 Test Files  3 failed | 7 passed (10)
      Tests  4 failed | 69 passed (73)
 Test Files  3 failed | 7 passed (10)
   Start at  06:59:16
      Tests  4 failed | 69 passed (73)
```

---

## Subcampaign: `campaign-abo-38695681551\governor\20261015T065913Z-244b6d47\abo\import-boundary`

- label: `abo/import-boundary` — passed=2 failed=0 exit=0

---

## Subcampaign: `campaign-abo-38695681551\governor\20261015T065913Z-244b6d47\abo\system`

- label: `abo/system` — passed=23 failed=0 exit=0

---

## Subcampaign: `campaign-abo-38695681551\governor\20261015T065913Z-244b6d47\abo\version-matrix`

- label: `abo/version-matrix` — passed=1 failed=0 exit=0

---

## Subcampaign: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\e2e`

- label: `ai-platform/e2e` — passed=525 failed=11 exit=1

### Last 60 lines of output.log

```

 FAIL  test/e2e/stage-11-replay-envelope-grace.test.ts > Stage 11 — replay, envelope, grace (S11-012…S11-021) > S11-015 — idempotent replay after Cancelled
AssertionError: expected 409 to be 200 // Object.is equality

- Expected
+ Received

- 200
+ 409

 ❯ assertHttpSse test/e2e/stage-11-replay-envelope-grace.test.ts:410:25
    408| 
    409| function assertHttpSse(result: InvokeResult): void {
    410|   expect(result.status).toBe(200);
       |                         ^
    411|   expect(result.headers.get("content-type")).toContain("text/event-str…
    412| }
 ❯ test/e2e/stage-11-replay-envelope-grace.test.ts:995:7

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[12/22]⎯


 Test Files  5 failed | 31 passed (36)
      Tests  11 failed | 525 passed | 29 skipped (565)
   Start at  06:58:56
   Duration  83.19s (transform 8.88s, setup 384.15s, collect 144.38s, tests 958.15s, environment 11ms, prepare 53.53s)

JSON report written to /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T065855Z-999179fa/ai-platform/e2e/.vitest-report-raw.json
[vpw:debug] Shutting down runtimes...
[vpw:debug] Disposing remote proxy sessions...
 FAIL  test/e2e/stage-11-replay-envelope-grace.test.ts > Stage 11 — replay, envelope, grace (S11-012…S11-021) > S11-015 — idempotent replay after Cancelled
AssertionError: expected 409 to be 200 // Object.is equality

- Expected
+ Received

- 200
+ 409

 ❯ assertHttpSse test/e2e/stage-11-replay-envelope-grace.test.ts:410:25
    408| 
    409| function assertHttpSse(result: InvokeResult): void {
    410|   expect(result.status).toBe(200);
       |                         ^
    411|   expect(result.headers.get("content-type")).toContain("text/event-str…
    412| }
 ❯ test/e2e/stage-11-replay-envelope-grace.test.ts:995:7

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[12/22]⎯


 Test Files  5 failed | 31 passed (36)
      Tests  11 failed | 525 passed | 29 skipped (565)
   Start at  06:58:56
   Duration  83.19s (transform 8.88s, setup 384.15s, collect 144.38s, tests 958.15s, environment 11ms, prepare 53.53s)

JSON report written to /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T065855Z-999179fa/ai-platform/e2e/.vitest-report-raw.json
[vpw:debug] Shutting down runtimes...
[vpw:debug] Disposing remote proxy sessions...

```

### Failed / not-recorded tests (11)

#### `FAIL` test/e2e/stage-09-admission-journal-compose.test.ts > Stage 09 — admission, journal, compose (S09-066…S09-085) > S09-068 — idempotent replay after failed

- per-test log: `tests/1108-test-e2e-stage-09-admission-journal-compose-test.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts:725:27
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts:725:27
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-09-admission-journal-compose.test.ts > Stage 09 — admission, journal, compose (S09-066…S09-085) > S09-069 — idempotent replay after cancelled

- per-test log: `tests/1110-test-e2e-stage-09-admission-journal-compose-test.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts:773:27
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts:773:27
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-10-prose-guard-stream.test.ts > Stage 10 — prose guards, regenerating, heartbeat (S10-018…S10-034) > S10-018 — idempotent replay of a failed prior request

- per-test log: `tests/1112-test-e2e-stage-10-prose-guard-stream-test-ts-sta.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:365:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:653:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:365:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:653:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-10-prose-guard-stream.test.ts > Stage 10 — prose guards, regenerating, heartbeat (S10-018…S10-034) > S10-019 — idempotent replay of a cancelled prior request

- per-test log: `tests/1114-test-e2e-stage-10-prose-guard-stream-test-ts-sta.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:365:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:735:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:365:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:735:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-10-route-retry-idempotency.test.ts > Stage 10 — accept, route, invoke, stream (S10-001…S10-017) > S10-001 — single-target chain success settles completed

- per-test log: `tests/1116-test-e2e-stage-10-route-retry-idempotency-test-t.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected null to be 'request/55a2ff13-97e1-49d7-8117-6af0f…' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts:493:33
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected null to be 'request/296f4162-88d5-4922-9643-8abdf…' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts:493:33
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-10-route-retry-idempotency.test.ts > Stage 10 — accept, route, invoke, stream (S10-001…S10-017) > S10-016 — idempotent replay of completed prior returns placeholder

- per-test log: `tests/1118-test-e2e-stage-10-route-retry-idempotency-test-t.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts:379:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts:1416:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts:379:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts:1416:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-11-completed-failed-cancelled.test.ts > Stage 11 — terminal settlement completed/failed/cancelled (S11-001…S11-011) > S11-002 — Ledger cost from pricing table

- per-test log: `tests/1120-test-e2e-stage-11-completed-failed-cancelled-tes.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected [] to have a length of 1 but got +0
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1257:20)
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1029:14)
    at Proxy.methodWrapper (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/.vite/vitest/da39a3ee5e6b4b0d3255bfef95601890afd80709/deps_ssr/vitest___@vitest_expect___chai.js:1601:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts:863:26
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected [] to have a length of 1 but got +0
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1257:20)
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1029:14)
    at Proxy.methodWrapper (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/.vite/vitest/da39a3ee5e6b4b0d3255bfef95601890afd80709/deps_ssr/vitest___@vitest_expect___chai.js:1601:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts:863:26
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-11-completed-failed-cancelled.test.ts > Stage 11 — terminal settlement completed/failed/cancelled (S11-001…S11-011) > S11-010 — Cancel after truncation fallback

- per-test log: `tests/1122-test-e2e-stage-11-completed-failed-cancelled-tes.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: R2 object not found: null
    at getR2Json (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/harness/d1.ts:351:11)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts:1591:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: R2 object not found: null
    at getR2Json (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/harness/d1.ts:351:11)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts:1591:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-11-replay-envelope-grace.test.ts > Stage 11 — replay, envelope, grace (S11-012…S11-021) > S11-013 — idempotent replay after Completed

- per-test log: `tests/1124-test-e2e-stage-11-replay-envelope-grace-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:410:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:922:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:410:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:922:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-11-replay-envelope-grace.test.ts > Stage 11 — replay, envelope, grace (S11-012…S11-021) > S11-014 — idempotent replay after Failed

- per-test log: `tests/1126-test-e2e-stage-11-replay-envelope-grace-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:410:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:957:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:410:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:957:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/e2e/stage-11-replay-envelope-grace.test.ts > Stage 11 — replay, envelope, grace (S11-012…S11-021) > S11-015 — idempotent replay after Cancelled

- per-test log: `tests/1128-test-e2e-stage-11-replay-envelope-grace-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:410:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:995:7
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at assertHttpSse (/home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:410:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts:995:7
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

---

## Subcampaign: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\eval`

- label: `ai-platform/eval` — passed=24 failed=0 exit=0

---

## Subcampaign: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\eval-all`

- label: `ai-platform/eval-all` — passed=39 failed=0 exit=0

---

## Subcampaign: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\load`

- label: `ai-platform/load` — passed=0 failed=0 exit=1

### Last 60 lines of output.log

```
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ runWorker test/load/happy-path.ts:497:24

Caused by: Caused by: Error: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:140:24
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ runWorker test/load/happy-path.ts:497:24

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[1/1]⎯


 Test Files  1 failed (1)
      Tests  10 skipped (10)
   Start at  07:01:29
   Duration  2.69s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
 ❯ runAdmission src/admission/index.ts:636:21

 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ runWorker test/load/happy-path.ts:497:24

Caused by: Caused by: Error: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:140:24
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ runWorker test/load/happy-path.ts:497:24

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[1/1]⎯


 Test Files  1 failed (1)
      Tests  10 skipped (10)
   Start at  07:01:29
   Duration  2.69s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)

JSON report written to /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T065855Z-999179fa/ai-platform/load/.vitest-report-raw.json
JSON report written to /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T065855Z-999179fa/ai-platform/load/.vitest-report-raw.json
[vpw:debug] Shutting down runtimes...
[vpw:debug] Disposing remote proxy sessions...
[vpw:debug] Shutting down runtimes...
[vpw:debug] Disposing remote proxy sessions...
× load: runner stalled (no progress) 0ms
harness: runner exited with code 1 before reporting a result
× load: runner stalled (no progress) 0ms
× load: runner stalled (no progress) 0ms
harness: runner exited with code 1 before reporting a result

```

### Failed / not-recorded tests (10)

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > d1_write_headroom_measured > measures one hot-path ai_request INSERT per request (finite, no ceiling)

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > do_throughput_per_installation_measured > measures time-dimensioned DO throughput against one pinned installation

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > exactly_one_r2_class_a_per_request_under_load > counts exactly one R2 Class A operation per request (max and average)

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > exactly_two_durable_object_requests_per_request_under_load > counts exactly two Quota DO fetches per request — admission and credit

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > guard_p95_within_tens_of_ms_at_target_concurrency > drives N=20 happy-path requests via a bounded pool with real overlap

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > load_suite_introduces_no_per_request_server_state > keeps load tooling under test/load; composition lives in src/pipeline

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > load_suite_joins_ci_permanently > wires load into CI via the ai-platform root campaign job

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > no_prompt_provider_model_in_flutter_from_load_suite > introduces no Flutter client files under the load suite tree

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > no_second_quota_do_round_trip_beyond_two > proves no third Quota DO fetch occurs per request under load

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > no_second_r2_object_per_request > proves no second R2 Class A op is written per request under load

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
 Test Files  1 failed (1)

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
      Tests  10 skipped (10)

   Start at  07:01:29
 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
   Duration  2.67s (transform 748ms, setup 1.16s, collect 187ms, tests 135ms, environment 0ms, prepare 112ms)
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR

 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19

⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯
 ❯ cloudflare-internal:d1-api:323:39

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    177|   const row = await db
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
       |               ^
```

---

## Subcampaign: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`

- label: `ai-platform/npm-test` — passed=1375 failed=81 exit=1

### Last 60 lines of output.log

```
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[80/157]⎯

 FAIL  test/system/settlement-integrity.system.test.ts > settlement integrity > SYS-7.4 — Exactly-once under replay
 FAIL  test/system/settlement-integrity.system.test.ts > settlement integrity > SYS-7.4 — Exactly-once under replay
AssertionError: expected 409 to be 200 // Object.is equality
 FAIL  test/system/settlement-integrity.system.test.ts > settlement integrity > SYS-7.4 — Exactly-once under replay

- Expected
+ Received

- 200
+ 409

 ❯ test/system/settlement-integrity.system.test.ts:469:31
    467|           idempotencyKey: terminal.idempotencyKey,
    468|         });
    469|         expect(replay.status).toBe(200);
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  76.79s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)

JSON report written to /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T065855Z-999179fa/ai-platform/npm-test/.vitest-report-workers.json
[vpw:debug] Shutting down runtimes...
[vpw:debug] Disposing remote proxy sessions...
AssertionError: expected 409 to be 200 // Object.is equality

- Expected
+ Received

- 200
+ 409

 ❯ test/system/settlement-integrity.system.test.ts:469:31
    467|           idempotencyKey: terminal.idempotencyKey,
    468|         });
    469|         expect(replay.status).toBe(200);
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  76.79s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)

JSON report written to /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T065855Z-999179fa/ai-platform/npm-test/.vitest-report-workers.json
[vpw:debug] Shutting down runtimes...
[vpw:debug] Disposing remote proxy sessions...

```

### Failed / not-recorded tests (91)

#### `FAIL` test/admission-credit.test.ts > admission_exactly_one_do_fetch_per_request > makes exactly one Durable Object fetch per pipeline admission call

- per-test log: `tests/2345-test-admission-credit-test-ts-admission-exactly.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:707:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:707:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > admission_expired_token_same_key_unauthenticated > rejects unauthenticated when the token expired outside skew before idempotency replay

- per-test log: `tests/2349-test-admission-credit-test-ts-admission-expired.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:779:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:779:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > admission_missing_entitlement_fail_closed > rejects coverage_lapsed on config-cache miss instead of throwing or grace

- per-test log: `tests/2375-test-admission-credit-test-ts-admission-missing.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1314:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1314:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > admission_rejection_counted_not_journaled > maps concurrency_exhausted onto concurrency_limited and tallies that code

- per-test log: `tests/2371-test-admission-credit-test-ts-admission-rejectio.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1227:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1227:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > admission_rejection_counted_not_journaled > rejects a repeated jti as replay without an ai_request row

- per-test log: `tests/2369-test-admission-credit-test-ts-admission-rejectio.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1198:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1198:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > admission_rejection_counted_not_journaled > tallies allowance_exhausted to bucketed platform_counter without an ai_request row

- per-test log: `tests/2367-test-admission-credit-test-ts-admission-rejectio.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1143:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1143:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > admission_rejection_counted_not_journaled > tallies fallback-cap rejection as coverage_unknown, not quota_exhausted

- per-test log: `tests/2373-test-admission-credit-test-ts-admission-rejectio.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1263:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1263:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > admission_repeated_key_no_second_inference > returns idempotent priorState with one DO fetch per call and no duplicate inference

- per-test log: `tests/2347-test-admission-credit-test-ts-admission-repeated.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:727:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:727:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > exactly_two_durable_object_round_trips_per_request > makes exactly two DO fetches for admission then credit

- per-test log: `tests/2379-test-admission-credit-test-ts-exactly-two-durabl.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1383:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1383:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > fallback_reconcile_drains_pending_rows > keeps pending fallback rows when settleFallback is skipped

- per-test log: `tests/2365-test-admission-credit-test-ts-fallback-reconcile.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1083:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1083:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > fallback_reconcile_drains_pending_rows > settles pending fallback_admission via settleFallback on the five-minute drain

- per-test log: `tests/2363-test-admission-credit-test-ts-fallback-reconcile.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1042:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1042:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > grace_cap_refusal_distinct_from_quota_exhausted > rejects at the fallback cap with coverage_unknown while entitlement budget remains

- per-test log: `tests/2353-test-admission-credit-test-ts-grace-cap-refusal.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:859:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:859:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > grace_durable_cap_across_isolate_maps > rejects a sixth grace admit after isolate maps are wiped because D1 pending count holds the cap

- per-test log: `tests/2355-test-admission-credit-test-ts-grace-durable-cap.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:893:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:893:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > grace_idempotency_key_replay_during_do_outage > returns the same graceRequestId and keeps a single pending D1 row

- per-test log: `tests/2357-test-admission-credit-test-ts-grace-idempotency.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:931:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:931:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > grace_rejects_when_ledger_quota_exhausted > rejects coverage_unknown when mirror fallback is unavailable

- per-test log: `tests/2361-test-admission-credit-test-ts-grace-rejects-when.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1024:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1024:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > grace_rejects_when_ledger_quota_exhausted > rejects quota_exhausted when request_quota is already 0 on the entitlement snapshot

- per-test log: `tests/2359-test-admission-credit-test-ts-grace-rejects-when.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:982:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:982:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > guard_rejection_debits_nothing_and_writes_no_journal_row > does not invoke credit or write ai_request when credit budget is exhausted at admission

- per-test log: `tests/2377-test-admission-credit-test-ts-guard-rejection-de.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1338:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:1338:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/admission-credit.test.ts > quota_do_unavailable_capped_grace_then_rejection > admits under grace for 5 calls then rejects when DO stays unavailable

- per-test log: `tests/2351-test-admission-credit-test-ts-quota-do-unavailab.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:819:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/admission-credit.test.ts:819:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/cohort-activate-promote.test.ts > T-J3-05 journal_records_serving_version_under_cohort_split > journaled prompt hash and capability version match each cohort build

- per-test log: `tests/2381-test-cohort-activate-promote-test-ts-t-j3-05-jou.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/cohort-activate-promote.test.ts:761:31
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/cohort-activate-promote.test.ts:761:31
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > context_requested_leg_credited_with_actual_usage > credits a leg terminating as AwaitingContext with actual usage

- per-test log: `tests/2389-test-conversational-journaling-test-ts-context-r.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:899:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:899:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > conversation_id_and_turn_ordinal_written_per_leg > writes client-supplied conversation_id and turn_ordinal on each conversational leg

- per-test log: `tests/2383-test-conversational-journaling-test-ts-conversat.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:741:18
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:741:18
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > each_leg_admitted_and_credited_independently > produces N admissions and N usage credits for N legs

- per-test log: `tests/2387-test-conversational-journaling-test-ts-each-leg.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:844:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:844:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > no_conversation_table_and_no_per_request_state_object > has no conversation entity table and only ordinary ai_request rows

- per-test log: `tests/2391-test-conversational-journaling-test-ts-no-conver.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:937:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:937:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > no_second_r2_object_and_no_second_quota_do_round_trip_from_h3 > writes one R2 object and one DO fetch per leg

- per-test log: `tests/2395-test-conversational-journaling-test-ts-no-second.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:1031:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:1031:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > one_indexed_query_returns_whole_conversation_ordered > returns all legs ordered by turn_ordinal via listConversationLegs

- per-test log: `tests/2385-test-conversational-journaling-test-ts-one-index.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:788:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:788:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > platform_held_no_state_between_legs > holds no conversation state between terminal leg 1 and leg 2 submit

- per-test log: `tests/2393-test-conversational-journaling-test-ts-platform.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:966:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:966:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > run_guard_writes_conversational_grouping_from_body > writes conversation_id and turn_ordinal when runGuard receives a conversational body

- per-test log: `tests/2399-test-conversational-journaling-test-ts-run-guard.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:1177:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:1177:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/conversational-journaling.test.ts > single_shot_unaffected_by_h3 > writes null conversation_id and turn_ordinal for single_shot rows

- per-test log: `tests/2397-test-conversational-journaling-test-ts-single-sh.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:1073:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runConversationalLeg (/home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:611:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/conversational-journaling.test.ts:1073:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > d1_write_headroom_measured > measures one hot-path ai_request INSERT per request (finite, no ceiling)

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > do_throughput_per_installation_measured > measures time-dimensioned DO throughput against one pinned installation

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > exactly_one_r2_class_a_per_request_under_load > counts exactly one R2 Class A operation per request (max and average)

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > exactly_two_durable_object_requests_per_request_under_load > counts exactly two Quota DO fetches per request — admission and credit

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > guard_p95_within_tens_of_ms_at_target_concurrency > drives N=20 happy-path requests via a bounded pool with real overlap

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > load_suite_introduces_no_per_request_server_state > keeps load tooling under test/load; composition lives in src/pipeline

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > load_suite_joins_ci_permanently > wires load into CI via the ai-platform root campaign job

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > no_prompt_provider_model_in_flutter_from_load_suite > introduces no Flutter client files under the load suite tree

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > no_second_quota_do_round_trip_beyond_two > proves no third Quota DO fetch occurs per request under load

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `NOT_RECORDED` test/load/load-and-cost.test.ts > no_second_r2_object_per_request > proves no second R2 Class A op is written per request under load

- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/load/load-and-cost.test.ts):
```
       |                               ^
    470| 
    471|         expect(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[81/157]⎯


 Test Files  11 failed | 37 passed (48)
      Tests  78 failed | 535 passed | 10 skipped (623)
   Start at  07:07:23
   Duration  75.56s (transform 14.51s, setup 660.50s, collect 190.72s, tests 941.42s, environment 14ms, prepare 87.98s)


⎯⎯⎯⎯⎯⎯ Failed Suites 1 ⎯⎯⎯⎯⎯⎯⎯

 FAIL  test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ D1DatabaseSessionAlwaysPrimary._sendOrThrow cloudflare-internal:d1-api:139:19
 ❯ cloudflare-internal:d1-api:323:39
 ❯ selectAiRequestByKey src/admission/index.ts:177:15
    175|   idempotencyKey: string,
    176| ): Promise<JournaledRequestRow | null> {
    177|   const row = await db
       |               ^
    178|     .prepare(
    179|       `SELECT request_id, request_reference, state, terminal_error_cod…
 ❯ runAdmission src/admission/index.ts:636:21
 ❯ Module.runGuard src/pipeline/index.ts:494:21
 ❯ test/load/happy-path.ts:564:25
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
 ❯ Object.withRequest test/load/binding-spies.ts:101:14
```

#### `FAIL` test/manifest.test.ts > T-A4-15 manifest_is_data_not_code > export surface contains only data declarations and load/hashManifest/verifyPublishedRegistry

- per-test log: `tests/1002-test-manifest-test-ts-t-a4-15-manifest-is-data-n.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: export hashCanonicalJson must be data, not executable wiring: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/manifest.test.ts:269:76
    at file:///home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/migrations.test.ts > T-A5-13 schema_snapshot_matches > post-migration CREATE TABLE DDL equals ai-platform/schema.snap.sql

- per-test log: `tests/1003-test-migrations-test-ts-t-a5-13-schema-snapshot.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 'CREATE TABLE ai_attempt (\n  attempt_…' to be 'CREATE TABLE ai_attempt (\n  attempt_…' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/migrations.test.ts:201:30
    at file:///home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/migrations.test.ts > schema_snapshot_matches > post-migration snapshot matches DDL and includes G1 catalogue entities

- per-test log: `tests/1004-test-migrations-test-ts-schema-snapshot-matches.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 'CREATE TABLE ai_attempt (\n  attempt_…' to be 'CREATE TABLE ai_attempt (\n  attempt_…' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/migrations.test.ts:389:30
    at processTicksAndRejections (node:internal/process/task_queues:103:5)
    at file:///home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_compose_stream_flag > passes streamFlag true and the request deadline into composeRequest

- per-test log: `tests/2413-test-pipeline-test-ts-pipeline-compose-stream-fl.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1348:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1348:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_soft_threshold_exposes_degraded_routing_tier > returns routingTier degraded on GuardFreshSuccess after usage crosses soft_threshold

- per-test log: `tests/2415-test-pipeline-test-ts-pipeline-soft-threshold-ex.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1385:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1385:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_stage_failures > stage 10 — compose failure → Failed terminal + internal_error

- per-test log: `tests/2409-test-pipeline-test-ts-pipeline-stage-failures-st.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1239:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1239:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_stage_failures > stage 8 — duplicate idempotency key → idempotent success with priorState

- per-test log: `tests/2403-test-pipeline-test-ts-pipeline-stage-failures-st.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1135:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1135:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_stage_failures > stage 8 — quota exhausted → quota_exhausted; no journal

- per-test log: `tests/2401-test-pipeline-test-ts-pipeline-stage-failures-st.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1106:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1106:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_stage_failures > stage 9 — D1 insert failure → internal_error + release; key reusable

- per-test log: `tests/2407-test-pipeline-test-ts-pipeline-stage-failures-st.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1207:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1207:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_stage_failures > stage 9 — journals resolvePromptVersion into prompt_artifact_hash, not the artifact ref

- per-test log: `tests/2405-test-pipeline-test-ts-pipeline-stage-failures-st.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1174:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1174:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/pipeline.test.ts > pipeline_transcript_threading > threads validatedTranscript into composeRequest and GuardSuccess

- per-test log: `tests/2411-test-pipeline-test-ts-pipeline-transcript-thread.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1283:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runGuard (/home/runner/work/AiClinic/AiClinic/ai-platform/src/pipeline/index.ts:494:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/pipeline.test.ts:1283:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > below_threshold_traffic_unaffected > keeps standard tier without degraded_notice below the soft threshold

- per-test log: `tests/2421-test-soft-threshold-routing-test-ts-below-thresh.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:891:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:891:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > hard_exhaustion_quota_exhausted_admin_path_no_lock > returns quota_exhausted with period_reset and does not journal an AI request

- per-test log: `tests/2419-test-soft-threshold-routing-test-ts-hard-exhaust.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:868:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:868:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > quota_exhausted_only_error_code_on_hard_exhaustion > emits only quota_exhausted from hard exhaustion and no error on soft path

- per-test log: `tests/2427-test-soft-threshold-routing-test-ts-quota-exhaus.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1002:18
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1002:18
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > soft_threshold_cost_dimension_selects_degraded > crosses soft threshold on creditsUsed / credit_budget and routes degraded

- per-test log: `tests/2433-test-soft-threshold-routing-test-ts-soft-thresho.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1120:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1120:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > soft_threshold_just_below_boundary_unaffected > keeps standard tier at 79/100 just below the >= soft boundary

- per-test log: `tests/2435-test-soft-threshold-routing-test-ts-soft-thresho.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1144:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1144:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > soft_threshold_no_second_quota_do_round_trip > uses exactly one Quota DO fetch for soft-threshold admission

- per-test log: `tests/2425-test-soft-threshold-routing-test-ts-soft-thresho.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:985:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:985:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > soft_threshold_persists_routing_tier > writes degraded and standard routing_tier via createRequestRow

- per-test log: `tests/2423-test-soft-threshold-routing-test-ts-soft-thresho.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:946:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:946:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > soft_threshold_selects_degraded_target > admits with degraded flag, routes degraded tier, and emits degraded_notice

- per-test log: `tests/2417-test-soft-threshold-routing-test-ts-soft-thresho.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:840:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:840:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > soft_threshold_token_dimension_selects_degraded > crosses soft threshold on creditsUsed / credit_budget and routes degraded

- per-test log: `tests/2431-test-soft-threshold-routing-test-ts-soft-thresho.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1092:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1092:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/soft-threshold-routing.test.ts > soft_threshold_zero_never_degrades > keeps standard routing when soft_threshold is 0 with positive budgets

- per-test log: `tests/2429-test-soft-threshold-routing-test-ts-soft-thresho.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1037:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at D1DatabaseSessionAlwaysPrimary._sendOrThrow (cloudflare-internal:d1-api:139:19)
    at cloudflare-internal:d1-api:323:39
    at selectAiRequestByKey (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:177:15)
    at Module.runAdmission (/home/runner/work/AiClinic/AiClinic/ai-platform/src/admission/index.ts:636:21)
    at runSoftThresholdPipeline (/home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:717:27)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/soft-threshold-routing.test.ts:1037:21
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/admission-settlement.system.test.ts > admission settlement against terms > E2E-P3.4-01 CP-B paid grant then issuer token lists the plan and completes a request charged to the term

- per-test log: `tests/2485-test-system-admission-settlement-system-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected [] to have a length of 1 but got +0
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1257:20)
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1029:14)
    at Proxy.methodWrapper (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/.vite/vitest/da39a3ee5e6b4b0d3255bfef95601890afd80709/deps_ssr/vitest___@vitest_expect___chai.js:1601:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/admission-settlement.system.test.ts:369:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected [] to have a length of 1 but got +0
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1257:20)
    at Proxy.<anonymous> (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/expect/dist/index.js:1029:14)
    at Proxy.methodWrapper (home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/.vite/vitest/da39a3ee5e6b4b0d3255bfef95601890afd80709/deps_ssr/vitest___@vitest_expect___chai.js:1601:25)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/admission-settlement.system.test.ts:369:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/admission-settlement.system.test.ts > admission settlement against terms > E2E-P3.4-11 A replayed jti or idempotency key returns the stored answer

- per-test log: `tests/2487-test-system-admission-settlement-system-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 401 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/admission-settlement.system.test.ts:735:38
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 401 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/admission-settlement.system.test.ts:735:38
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/cron-retention-interplay.system.test.ts > cron retention interplay > SYS-8.1 — Retention purge keeps usage_event money row

- per-test log: `tests/2489-test-system-cron-retention-interplay-system-test.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected null to be truthy
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/cron-retention-interplay.system.test.ts:60:25
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected null to be truthy
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/cron-retention-interplay.system.test.ts:60:25
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/quota-admission-interplay.system.test.ts > quota admission interplay > SYS-5.5 — Idempotent replay of completed

- per-test log: `tests/2491-test-system-quota-admission-interplay-system-tes.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: R2 object not found: null
    at getR2Json (/home/runner/work/AiClinic/AiClinic/ai-platform/test/system/harness.ts:1345:11)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/quota-admission-interplay.system.test.ts:266:28
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/quota-admission-interplay.system.test.ts:273:27
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/quota-admission-interplay.system.test.ts > quota admission interplay > SYS-5.6 — Replay of failed and cancelled

- per-test log: `tests/2493-test-system-quota-admission-interplay-system-tes.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected undefined to be 'failed' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/quota-admission-interplay.system.test.ts:323:43
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected undefined to be 'failed' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/quota-admission-interplay.system.test.ts:323:43
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/settlement-integrity.system.test.ts > settlement integrity > SYS-7.1 — Completed settlement columns and envelope

- per-test log: `tests/2495-test-system-settlement-integrity-system-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected null to be 'request/fa906603-e645-4419-a2b1-7fe1d…' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/settlement-integrity.system.test.ts:133:38
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected null to be 'request/80eda24c-807d-428c-97b9-c4dd9…' // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/settlement-integrity.system.test.ts:133:38
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/settlement-integrity.system.test.ts > settlement integrity > SYS-7.3 — Cancelled settlement after accepted

- per-test log: `tests/2497-test-system-settlement-integrity-system-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/settlement-integrity.system.test.ts:330:64
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/settlement-integrity.system.test.ts:330:64
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/system/settlement-integrity.system.test.ts > settlement integrity > SYS-7.4 — Exactly-once under replay

- per-test log: `tests/2499-test-system-settlement-integrity-system-test-ts.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 409 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/settlement-integrity.system.test.ts:469:31
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 409 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/system/settlement-integrity.system.test.ts:469:31
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > ai_request_written_before_invoke > T2 — one journal insert before provider work

- per-test log: `tests/2443-test-worker-request-orchestrator-test-ts-ai-requ.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1046:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1046:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > cancel_disconnect_aborts_cancelled_credits_partial > T16 — disconnect aborts in-flight invoke; journal Cancelled; partial credit

- per-test log: `tests/2471-test-worker-request-orchestrator-test-ts-cancel.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1560:29
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1560:29
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > cancel_disconnect_aborts_cancelled_credits_partial > writes ai_attempt and usage_event when cancel has accrued usage

- per-test log: `tests/2473-test-worker-request-orchestrator-test-ts-cancel.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1672:29
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected false to be true // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1672:29
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > completed_attempt_and_usage_event_cost_agree > prices ai_attempt.cost and usage_event.cost from the same helper

- per-test log: `tests/2449-test-worker-request-orchestrator-test-ts-complet.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1086:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1086:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > exactly_one_terminal_event_on_every_live_path > T22 — every exercised path has exactly one terminal

- per-test log: `tests/2469-test-worker-request-orchestrator-test-ts-exactly.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1479:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1479:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > exactly_two_do_round_trips_admit_and_credit > T4 — admit + credit only

- per-test log: `tests/2453-test-worker-request-orchestrator-test-ts-exactly.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1156:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1156:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > idempotency_repeat_returns_prior_no_second_inference > T15 — repeated key returns prior state

- per-test log: `tests/2455-test-worker-request-orchestrator-test-ts-idempot.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1171:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1171:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > live_grace_admission_routing_tier_matches_router > routes the degraded chain when grace admission journals routing_tier degraded

- per-test log: `tests/2481-test-worker-request-orchestrator-test-ts-live-gr.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
AssertionError: expected 500 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1889:31
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

AssertionError: expected 500 to be 200 // Object.is equality
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1889:31
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > live_post_happy_path_accepted_stream_completed > T1 — accepted, fake chunks, exactly one completed

- per-test log: `tests/2439-test-worker-request-orchestrator-test-ts-live-po.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1003:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1003:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > live_post_happy_path_accepted_stream_completed > journals promptVersion content hash into prompt_artifact_hash, not the ref (4.4)

- per-test log: `tests/2441-test-worker-request-orchestrator-test-ts-live-po.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1014:26
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1014:26
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > live_soft_threshold_degraded_notice_and_routing_agree > emits degraded_notice, journals degraded, and routes the degraded cost class

- per-test log: `tests/2479-test-worker-request-orchestrator-test-ts-live-so.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1845:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1845:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > no_per_request_server_side_state > T17 — Quota DO is installation-scoped only (no per-request DO name)

- per-test log: `tests/2475-test-worker-request-orchestrator-test-ts-no-per.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1714:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1714:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > one_r2_envelope_after_response > T3 — exactly one R2 envelope after terminal

- per-test log: `tests/2445-test-worker-request-orchestrator-test-ts-one-r2.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1060:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1060:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > one_r2_envelope_after_response > stores a non-empty raw provider body per attempt in the envelope

- per-test log: `tests/2447-test-worker-request-orchestrator-test-ts-one-r2.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1069:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1069:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > post_guard_failed_terminal_provider_unavailable > T20 — provider_unavailable as one failed terminal

- per-test log: `tests/2457-test-worker-request-orchestrator-test-ts-post-gu.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1231:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1231:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > post_guard_failed_terminal_provider_unavailable > writes a diagnostic attempt row when routing yields an empty chain

- per-test log: `tests/2459-test-worker-request-orchestrator-test-ts-post-gu.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1315:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1315:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > post_guard_failed_terminal_validation_failed > T21 — validation_failed as one failed terminal

- per-test log: `tests/2461-test-worker-request-orchestrator-test-ts-post-gu.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1382:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1382:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > prose_safety_markers_on_live_path > fails validation_failed when the model echoes the injection needle

- per-test log: `tests/2465-test-worker-request-orchestrator-test-ts-prose-s.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at postWithFakeOutput (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1435:24)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1455:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at postWithFakeOutput (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1435:24)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1455:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > prose_safety_markers_on_live_path > fails validation_failed when the model leaks the composed system instruction

- per-test log: `tests/2467-test-worker-request-orchestrator-test-ts-prose-s.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at postWithFakeOutput (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1435:24)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1467:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at postWithFakeOutput (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1435:24)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1467:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > prose_safety_markers_on_live_path > fails validation_failed when the model opens with a refusal prefix

- per-test log: `tests/2463-test-worker-request-orchestrator-test-ts-prose-s.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at postWithFakeOutput (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1435:24)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1443:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at postWithFakeOutput (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1435:24)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1443:20
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > provider_selection_only_via_routing_policy > T18 — routing-policy edit changes selection without orchestrator code change

- per-test log: `tests/2477-test-worker-request-orchestrator-test-ts-provide.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1729:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1729:19
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > routing_decision_persisted_at_stage_10 > writes the router decision onto the existing ai_request row before invoke

- per-test log: `tests/2483-test-worker-request-orchestrator-test-ts-routing.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1967:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1967:24
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > usage_event_term_id_from_admission > journals term_id from admission, not an entitlement period string

- per-test log: `tests/2451-test-worker-request-orchestrator-test-ts-usage-e.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1132:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at fetchLivePost (/home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:692:20)
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:1132:5
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

#### `FAIL` test/worker-request-orchestrator.test.ts > worker_supplies_production_event_source > T23 — live route is not the missing-eventSource 503 shell

- per-test log: `tests/2437-test-worker-request-orchestrator-test-ts-worker.log`
- failure source: `vitest-report.json`

From vitest-report.json (first 25 lines):
```
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:776:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20

Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
    at /home/runner/work/AiClinic/AiClinic/ai-platform/test/worker-request-orchestrator.test.ts:776:22
    at home/runner/work/AiClinic/AiClinic/ai-platform/node_modules/@vitest/runner/dist/chunk-hooks.js:752:20
```

---

## Subcampaign: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\version-matrix`

- label: `ai-platform/version-matrix` — passed=2 failed=0 exit=0

---

## Subcampaign: `campaign-backend-38695681551\governor\20261015T070018Z-295be2f6\backend\all`

- label: `backend/all` — passed=73 failed=0 exit=0

---

## Subcampaign: `campaign-backend-38695681551\governor\20261015T070018Z-295be2f6\backend\catalog`

- label: `backend/catalog` — passed=8 failed=0 exit=0

---

## Subcampaign: `campaign-e2e-fullstack-38695681551\governor\20261015T070039Z-78af63ae\e2e-fullstack\all-ci`

- label: `e2e-fullstack/all-ci` — passed=0 failed=2 exit=1

### Last 60 lines of output.log

```
#     at \#cachedDefaultResolve (node:internal/modules/esm/loader:747:20)
#     at \#resolveAndMaybeBlockOnLoaderThread (node:internal/modules/esm/loader:783:38)
#     at \#resolveAndMaybeBlockOnLoaderThread (node:internal/modules/esm/loader:783:38)
#     at nextStep (node:internal/modules/customization_hooks:189:26)
#     at nextStep (node:internal/modules/customization_hooks:189:26)
#     at resolveBaseSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/node_modules/tsx/dist/register-nyXW-TH3.mjs:2:11092)
#     at resolveBaseSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/node_modules/tsx/dist/register-nyXW-TH3.mjs:2:11092)
#     at resolveDirectorySync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/node_modules/tsx/dist/register-nyXW-TH3.mjs:2:12398)
#     at resolveDirectorySync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/node_modules/tsx/dist/register-nyXW-TH3.mjs:2:12398)
#     at resolveTsPathsSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/node_modules/tsx/dist/register-nyXW-TH3.mjs:2:13605) {
#     at resolveTsPathsSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/node_modules/tsx/dist/register-nyXW-TH3.mjs:2:13605) {
#   code: 'ERR_MODULE_NOT_FOUND'
# }
#   code: 'ERR_MODULE_NOT_FOUND'
# Node.js v22.23.3
# }
# Node.js v22.23.3
# Subtest: test/p5-2.test.mjs
# Subtest: test/p5-2.test.mjs
not ok 1 - test/p5-2.test.mjs
  ---
  duration_ms: 665.119373
not ok 1 - test/p5-2.test.mjs
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p5-2.test.mjs:1:1'
  failureType: 'testCodeFailure'
  exitCode: 1
  signal: ~
  error: 'test failed'
  code: 'ERR_TEST_FAILURE'
  ...
1..1
# tests 1
# suites 0
# pass 0
# fail 1
# cancelled 0
# skipped 0
# todo 0
# duration_ms 670.478652
  ---
  duration_ms: 665.119373
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p5-2.test.mjs:1:1'
  failureType: 'testCodeFailure'
  exitCode: 1
  signal: ~
  error: 'test failed'
  code: 'ERR_TEST_FAILURE'
  ...
1..1
# tests 1
# suites 0
# pass 0
# fail 1
# cancelled 0
# skipped 0
# todo 0
# duration_ms 670.478652

```

### Failed / not-recorded tests (2)

#### `FAIL` test/p5-1.test.mjs

- per-test log: `tests/001-test-p5-1-test-mjs.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/p5-1.test.mjs):
```
  code: 'ERR_TEST_FAILURE'
  ...
1..1
# tests 1
# suites 0
# pass 0
# fail 0
# cancelled 1
not ok 1 - test/p5-1.test.mjs
# skipped 0
# todo 0
# duration_ms 180092.265221
  ---
  duration_ms: 180087.360908
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p5-1.test.mjs:1:1'
  failureType: 'testTimeoutFailure'
  error: 'test timed out after 180000ms'
  code: 'ERR_TEST_FAILURE'
  ...
1..1
# tests 1
# suites 0
# pass 0
# fail 0
# cancelled 1
# skipped 0
# todo 0
# duration_ms 180092.265221
Reset fullstack wrangler persist: e2e/fullstack/.wrangler
== p5-2 ==
```

#### `FAIL` test/p5-2.test.mjs

- per-test log: `tests/002-test-p5-2-test-mjs.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/p5-2.test.mjs):
```
  error: 'test failed'
  code: 'ERR_TEST_FAILURE'
  ...
1..1
# tests 1
# suites 0
# pass 0
# fail 1
# cancelled 0
# skipped 0
# todo 0
# duration_ms 670.478652
  ---
  duration_ms: 665.119373
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p5-2.test.mjs:1:1'
  failureType: 'testCodeFailure'
  exitCode: 1
  signal: ~
  error: 'test failed'
  code: 'ERR_TEST_FAILURE'
  ...
1..1
# tests 1
# suites 0
# pass 0
# fail 1
# cancelled 0
# skipped 0
# todo 0
# duration_ms 670.478652
```

---

## Subcampaign: `campaign-e2e-fullstack-38695681551\governor\20261015T070039Z-78af63ae\e2e-fullstack\all-manual`

- label: `e2e-fullstack/all-manual` — passed=4 failed=12 exit=130

### Last 60 lines of output.log

```
# env.WEBAUTHN_RP_ID ("ops.vendor.test")                                                     Environment Variable      local
# env.WEBAUTHN_ORIGIN ("https://ops.vendor.test")                                            Environment Variable      local
# env.HEARTBEAT_URL ("https://heartbeat.test/ping")                                          Environment Variable      local
# env.ALERT_EMAIL_TO ("alerts@clinic.invalid")                                               Environment Variable      local
# env.ISSUER_ID ("issuer-test")                                                              Environment Variable      local
# env.PLATFORM_SIGNING_KEY ("{"kid":"platform-test","pkcs8":"MC4CA...")                      Environment Variable      local
# Your Worker has access to the following bindings:
# Binding                                                                                    Resource                  Mode
# env.DO (GatewayObject)                                                                     Durable Object            local
# env.CONFIG_CACHE_TTL_MS ("100")                                                            Environment Variable      local
# env.SEND_EMAIL (alerts@clinic.invalid)                                                     Send Email                local
# env.ACCESS_TEAM_DOMAIN ("access.test")                                                     Environment Variable      local
# env.DB (ai-platform-development)                                                           D1 Database               local
# env.ACCESS_AUD ("vendor-access-aud")                                                       Environment Variable      local
# env.R2 (ai-platform-development)                                                           R2 Bucket                 local
# env.WEBAUTHN_RP_ID ("ops.vendor.test")                                                     Environment Variable      local
# env.RATE_LIMITER_INSTALLATION (600 requests/60s)                                           Rate Limit                local
# env.WEBAUTHN_ORIGIN ("https://ops.vendor.test")                                            Environment Variable      local
# env.RATE_LIMITER_INSTALLATION_ACTOR (120 requests/60s)                                     Rate Limit                local
# env.HEARTBEAT_URL ("https://heartbeat.test/ping")                                          Environment Variable      local
# env.RATE_LIMITER_INSTALLATION_CAPABILITY (300 requests/60s)                                Rate Limit                local
# env.ALERT_EMAIL_TO ("alerts@clinic.invalid")                                               Environment Variable      local
# env.BUILD_SHA ("local")                                                                    Environment Variable      local
# env.ISSUER_ID ("issuer-test")                                                              Environment Variable      local
# env.PLATFORM_SIGNING_KEY ("{"kid":"platform-test","pkcs8":"MC4CA...")                      Environment Variable      local
# env.ENVIRONMENT ("development")                                                            Environment Variable      local
# Your Worker has access to the following bindings:
# env.LOG_VERBOSITY ("2")                                                                    Environment Variable      local
# Binding                                                                                    Resource                  Mode
# env.DO (GatewayObject)                                                                     Durable Object            local
# env.CONFIG_CACHE_TTL_MS ("100")                                                            Environment Variable      local
# env.SEND_EMAIL (alerts@clinic.invalid)                                                     Send Email                local
# env.DB (ai-platform-development)                                                           D1 Database               local
# env.ACCESS_TEAM_DOMAIN ("access.test")                                                     Environment Variable      local
# env.R2 (ai-platform-development)                                                           R2 Bucket                 local
# env.RATE_LIMITER_INSTALLATION (600 requests/60s)                                           Rate Limit                local
# env.RATE_LIMITER_INSTALLATION_ACTOR (120 requests/60s)                                     Rate Limit                local
# env.ACCESS_AUD ("vendor-access-aud")                                                       Environment Variable      local
# env.RATE_LIMITER_INSTALLATION_CAPABILITY (300 requests/60s)                                Rate Limit                local
# env.BUILD_SHA ("local")                                                                    Environment Variable      local
# env.WEBAUTHN_RP_ID ("ops.vendor.test")                                                     Environment Variable      local
# env.ENVIRONMENT ("development")                                                            Environment Variable      local
# env.LOG_VERBOSITY ("2")                                                                    Environment Variable      local
# env.WEBAUTHN_ORIGIN ("https://ops.vendor.test")                                            Environment Variable      local
# env.CONFIG_CACHE_TTL_MS ("100")                                                            Environment Variable      local
# env.HEARTBEAT_URL ("https://heartbeat.test/ping")                                          Environment Variable      local
# env.ACCESS_TEAM_DOMAIN ("access.test")                                                     Environment Variable      local
# env.ACCESS_AUD ("vendor-access-aud")                                                       Environment Variable      local
# env.WEBAUTHN_RP_ID ("ops.vendor.test")                                                     Environment Variable      local
# env.ALERT_EMAIL_TO ("alerts@clinic.invalid")                                               Environment Variable      local
# env.WEBAUTHN_ORIGIN ("https://ops.vendor.test")                                            Environment Variable      local
# env.ISSUER_ID ("issuer-test")                                                              Environment Variable      local
# env.HEARTBEAT_URL ("https://heartbeat.test/ping")                                          Environment Variable      local
# env.ALERT_EMAIL_TO ("alerts@clinic.invalid")                                               Environment Variable      local
# env.PLATFORM_SIGNING_KEY ("{"kid":"platform-test","pkcs8":"MC4CA...")                      Environment Variable      local
# env.ISSUER_ID ("issuer-test")                                                              Environment Variable      local
# env.PLATFORM_SIGNING_KEY ("{"kid":"platform-test","pkcs8":"MC4CA...")                      Environment Variable      local
# *** Fatal uncaught kj::Exception: kj/async-io-unix.c++:945: failed: ::bind(sockfd, &addr.generic, addrlen): Address already in use; toString() = 127.0.0.1:8787
# *** Fatal uncaught kj::Exception: kj/async-io-unix.c++:945: failed: ::bind(sockfd, &addr.generic, addrlen): Address already in use; toString() = 127.0.0.1:8787

```

### Failed / not-recorded tests (12)

#### `FAIL` test/p5-1.test.mjs

- per-test log: `tests/001-test-p5-1-test-mjs.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/p5-1.test.mjs):
```
not ok 1 - test/p5-1.test.mjs
  ---
  duration_ms: 180060.059423
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p5-1.test.mjs:1:1'
  failureType: 'testTimeoutFailure'
  error: 'test timed out after 180000ms'
  code: 'ERR_TEST_FAILURE'
  ...
# node:internal/modules/package_json_reader:314
#   throw new ERR_MODULE_NOT_FOUND(packageName, fileURLToPath(base), null);
#         ^
  ---
  duration_ms: 180060.059423
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p5-1.test.mjs:1:1'
  failureType: 'testTimeoutFailure'
  error: 'test timed out after 180000ms'
  code: 'ERR_TEST_FAILURE'
  ...
# node:internal/modules/package_json_reader:314
#   throw new ERR_MODULE_NOT_FOUND(packageName, fileURLToPath(base), null);
#         ^
# Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'vendor-contracts' imported from /home/runner/work/AiClinic/AiClinic/ai-platform/src/vendor/entrypoint.ts
#     at Object.getPackageJSONURL (node:internal/modules/package_json_reader:314:9)
# Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'vendor-contracts' imported from /home/runner/work/AiClinic/AiClinic/ai-platform/src/vendor/entrypoint.ts
#     at packageResolve (node:internal/modules/esm/resolve:772:81)
#     at moduleResolve (node:internal/modules/esm/resolve:859:18)
#     at Object.getPackageJSONURL (node:internal/modules/package_json_reader:314:9)
#     at defaultResolve (node:internal/modules/esm/resolve:989:11)
#     at packageResolve (node:internal/modules/esm/resolve:772:81)
```

#### `FAIL` test/p5-2.test.mjs

- per-test log: `tests/002-test-p5-2-test-mjs.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/p5-2.test.mjs):
```
  failureType: 'testCodeFailure'
  exitCode: 1
  signal: ~
  error: 'test failed'
  code: 'ERR_TEST_FAILURE'
  ...
# Subtest: E2E-P5.2-03 Stored dates pass to grace then lapsed while workers are stopped, then stale and status_stale
ok 3 - E2E-P5.2-03 Stored dates pass to grace then lapsed while workers are stopped, then stale and status_stale
  ---
  duration_ms: 1161.519426
  type: 'test'
  ---
  duration_ms: 1537.115764
  type: 'test'
  ...
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p5-2.test.mjs:1:1'
  failureType: 'testCodeFailure'
  exitCode: 1
  signal: ~
  error: 'test failed'
  code: 'ERR_TEST_FAILURE'
  ...
# Subtest: E2E-P5.2-03 Stored dates pass to grace then lapsed while workers are stopped, then stale and status_stale
ok 3 - E2E-P5.2-03 Stored dates pass to grace then lapsed while workers are stopped, then stale and status_stale
# Subtest: E2E-P5.2-04 ends_soon at 7, 3, and 1 days when queued_count is 0, staff status has no prices, and staff billing is FORBIDDEN_ROLE
ok 4 - E2E-P5.2-04 ends_soon at 7, 3, and 1 days when queued_count is 0, staff status has no prices, and staff billing is FORBIDDEN_ROLE
  ---
  duration_ms: 800.490483
  type: 'test'
  ...
# Subtest: E2E-P5.2-09 SQL subscription ref equals the package vector and the ABO and platform values
```

#### `FAIL` E2E-P7.2-07

- per-test log: `tests/007-e2e-p7-2-07.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-07"):
```
# Subtest: E2E-P7.2-08
not ok 8 - E2E-P7.2-08
  ---
  duration_ms: 181.400897
  type: 'test'
  ...
# Subtest: E2E-P5.2-11 Band 90 raises allowance_low for every role
ok 6 - E2E-P5.2-11 Band 90 raises allowance_low for every role
  ---
  duration_ms: 177.130738
  type: 'test'
  ...
# (node:12886) ExperimentalWarning: SQLite is an experimental feature and might change at any time
# (Use `node --trace-warnings ...` to show where the warning was created)
# Subtest: E2E-P7.2-07
not ok 7 - E2E-P7.2-07
  ---
  duration_ms: 0.890955
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-credential-isolation.test.mjs:164:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] duplicate column name: canary_installation_ids: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-44_939.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
```

#### `FAIL` E2E-P7.2-08

- per-test log: `tests/008-e2e-p7-2-08.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-08"):
```
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] duplicate column name: canary_installation_ids: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-44_939.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-credential-isolation.test.mjs:37:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# Subtest: E2E-P7.2-08
not ok 8 - E2E-P7.2-08
  ---
  duration_ms: 2731.389337
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:66:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table grace_admission_queue already exists at offset 154: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
```

#### `FAIL` E2E-P7.2-01

- per-test log: `tests/009-e2e-p7-2-01.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-01"):
```
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-44_939.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-credential-isolation.test.mjs:37:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# (node:13026) ExperimentalWarning: SQLite is an experimental feature and might change at any time
# (Use `node --trace-warnings ...` to show where the warning was created)
# Subtest: E2E-P7.2-01
not ok 9 - E2E-P7.2-01
  ---
  duration_ms: 0.86101
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:148:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table grace_admission_queue already exists at offset 154: SQLITE_ERROR
  ---
  duration_ms: 2731.389337
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:66:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table grace_admission_queue already exists at offset 154: SQLITE_ERROR
    
```

#### `FAIL` E2E-P7.2-02

- per-test log: `tests/010-e2e-p7-2-02.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-02"):
```
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table grace_admission_queue already exists at offset 154: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:32:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# Subtest: E2E-P7.2-02
not ok 10 - E2E-P7.2-02
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:32:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# Subtest: E2E-P7.2-03
not ok 11 - E2E-P7.2-03
  ---
```

#### `FAIL` E2E-P7.2-03

- per-test log: `tests/011-e2e-p7-2-03.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-03"):
```
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:32:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# Subtest: E2E-P7.2-03
  ---
  duration_ms: 0.090715
not ok 11 - E2E-P7.2-03
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:199:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table grace_admission_queue already exists at offset 154: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:32:11)
```

#### `FAIL` E2E-P7.2-04

- per-test log: `tests/012-e2e-p7-2-04.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-04"):
```
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table grace_admission_queue already exists at offset 154: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:32:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# Subtest: E2E-P7.2-04
  ---
not ok 12 - E2E-P7.2-04
  duration_ms: 0.052398
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:393:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table grace_admission_queue already exists at offset 154: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
```

#### `FAIL` E2E-P7.2-05

- per-test log: `tests/013-e2e-p7-2-05.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-05"):
```
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-47_133.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-untrusted-callers.test.mjs:32:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# (node:13159) ExperimentalWarning: SQLite is an experimental feature and might change at any time
# (Use `node --trace-warnings ...` to show where the warning was created)
# Subtest: E2E-P7.2-05
  ---
not ok 13 - E2E-P7.2-05
  duration_ms: 2841.268993
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs:300:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table service_key already exists at offset 13: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-49_289.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
```

#### `FAIL` E2E-P7.2-06

- per-test log: `tests/014-e2e-p7-2-06.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-06"):
```
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table service_key already exists at offset 13: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-49_289.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs:63:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# Subtest: E2E-P7.2-06
  ---
not ok 14 - E2E-P7.2-06
  duration_ms: 0.658379
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs:435:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table service_key already exists at offset 13: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-49_289.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
```

#### `FAIL` E2E-P7.2-09

- per-test log: `tests/015-e2e-p7-2-09.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.2-09"):
```
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table service_key already exists at offset 13: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-49_289.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs:63:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# Subtest: E2E-P7.2-09
  ---
not ok 15 - E2E-P7.2-09
  duration_ms: 0.116593
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs:661:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/ai-platform/wrangler.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ✘ [ERROR] table service_key already exists at offset 13: SQLITE_ERROR
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-49_289.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
```

#### `FAIL` E2E-P7.3-01

- per-test log: `tests/016-e2e-p7-3-01.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of "E2E-P7.3-01"):
```
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-49_289.log"
    
  code: 'ERR_TEST_FAILURE'
  stack: |-
    runWranglerSync (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:41:11)
    preparePlatformD1 (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/wrangler-persist.mjs:82:3)
    startStack (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-stack.mjs:586:9)
    async TestContext.<anonymous> (file:///home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs:63:11)
    async TestHook.run (node:internal/test_runner/test:1054:7)
  ...
# (node:13378) ExperimentalWarning: SQLite is an experimental feature and might change at any time
# (Use `node --trace-warnings ...` to show where the warning was created)
# Subtest: E2E-P7.3-01
not ok 16 - E2E-P7.3-01
  ---
  duration_ms: 1794.93692
  type: 'test'
  location: '/home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/p7-3-01.test.mjs:133:1'
  failureType: 'hookFailed'
  error: |-
    wrangler d1 migrations apply ai-platform-development --local --env development --config /home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/variant/platform-n-plus-1.toml --persist-to /home/runner/work/AiClinic/AiClinic/e2e/fullstack/.wrangler/d1-seed failed (1): ▲ [WARNING] No migrations folder found. Set `migrations_dir` in your wrangler.toml file to choose a different path.
    
    
    ✘ [ERROR] No migrations present at /home/runner/work/AiClinic/AiClinic/e2e/fullstack/test/variant/migrations.
    
    
    🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_07-03-51_572.log"
    
  code: 'ERR_TEST_FAILURE'
```

---

## Subcampaign: `campaign-frontend-38695681551\governor\20261015T070147Z-536da71a\frontend\all`

- label: `frontend/all` — passed=4372 failed=12 exit=1

### Last 60 lines of output.log

```
{"test":{"id":6711,"name":"VitalSignFormDialog — dismissal trivial: cancel pops with null","suiteID":6603,"groupIDs":[6649,6710],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":342,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/vital_sign_form_dialog_test.dart"},"type":"testStart","time":861927}
{"testID":6711,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862092}
{"test":{"id":6711,"name":"VitalSignFormDialog — dismissal trivial: cancel pops with null","suiteID":6603,"groupIDs":[6649,6710],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":342,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/vital_sign_form_dialog_test.dart"},"type":"testStart","time":861927}
{"testID":6711,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862092}
{"test":{"id":6712,"name":"VitalSignFormDialog — dismissal edge case: barrier tap dismisses with null","suiteID":6603,"groupIDs":[6649,6710],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":370,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/vital_sign_form_dialog_test.dart"},"type":"testStart","time":862092}
{"testID":6712,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862231}
{"test":{"id":6712,"name":"VitalSignFormDialog — dismissal edge case: barrier tap dismisses with null","suiteID":6603,"groupIDs":[6649,6710],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":370,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/vital_sign_form_dialog_test.dart"},"type":"testStart","time":862092}
{"testID":6712,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862231}
{"testID":6709,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862436}
{"testID":6709,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862436}
{"test":{"id":6713,"name":"VisitIntakeSection — patient safety provider states edge case: encounter draft patient safety merges over provider context","suiteID":6289,"groupIDs":[6364,6706],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":383,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_intake_section_test.dart"},"type":"testStart","time":862436}
{"testID":6713,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862786}
{"test":{"id":6713,"name":"VisitIntakeSection — patient safety provider states edge case: encounter draft patient safety merges over provider context","suiteID":6289,"groupIDs":[6364,6706],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":383,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_intake_section_test.dart"},"type":"testStart","time":862436}
{"testID":6713,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862786}
{"group":{"id":6714,"suiteID":6289,"parentID":6364,"name":"VisitIntakeSection — saveStatus and errorMessage (not rendered here)","metadata":{"skip":false,"skipReason":null},"testCount":1,"line":407,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_intake_section_test.dart"},"type":"group","time":862786}
{"group":{"id":6714,"suiteID":6289,"parentID":6364,"name":"VisitIntakeSection — saveStatus and errorMessage (not rendered here)","metadata":{"skip":false,"skipReason":null},"testCount":1,"line":407,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_intake_section_test.dart"},"type":"group","time":862786}
{"test":{"id":6715,"name":"VisitIntakeSection — saveStatus and errorMessage (not rendered here) regression: saveStatus and errorMessage in state do not surface in this section","suiteID":6289,"groupIDs":[6364,6714],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":408,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_intake_section_test.dart"},"type":"testStart","time":862786}
{"test":{"id":6715,"name":"VisitIntakeSection — saveStatus and errorMessage (not rendered here) regression: saveStatus and errorMessage in state do not surface in this section","suiteID":6289,"groupIDs":[6364,6714],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":408,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_intake_section_test.dart"},"type":"testStart","time":862786}
{"testID":6703,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862918}
{"testID":6703,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":862918}
{"group":{"id":6716,"suiteID":6394,"parentID":6510,"name":"VisitTreatmentSection — investigations notifier wiring","metadata":{"skip":false,"skipReason":null},"testCount":3,"line":417,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"group","time":862918}
{"group":{"id":6716,"suiteID":6394,"parentID":6510,"name":"VisitTreatmentSection — investigations notifier wiring","metadata":{"skip":false,"skipReason":null},"testCount":3,"line":417,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"group","time":862918}
{"test":{"id":6717,"name":"VisitTreatmentSection — investigations notifier wiring advanced: create investigation routes to stageCreateInvestigation with args","suiteID":6394,"groupIDs":[6510,6716],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":418,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":862918}
{"testID":6715,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":863280}
{"test":{"id":6717,"name":"VisitTreatmentSection — investigations notifier wiring advanced: create investigation routes to stageCreateInvestigation with args","suiteID":6394,"groupIDs":[6510,6716],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":418,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":862918}
{"testID":6715,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":863280}
{"testID":6717,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":863955}
{"testID":6717,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":863955}
{"test":{"id":6718,"name":"VisitTreatmentSection — investigations notifier wiring advanced: archive investigation routes to stageArchiveInvestigation","suiteID":6394,"groupIDs":[6510,6716],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":432,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":863955}
{"testID":6718,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":864142}
{"test":{"id":6718,"name":"VisitTreatmentSection — investigations notifier wiring advanced: archive investigation routes to stageArchiveInvestigation","suiteID":6394,"groupIDs":[6510,6716],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":432,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":863955}
{"testID":6718,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":864142}
{"test":{"id":6719,"name":"VisitTreatmentSection — investigations notifier wiring advanced: edit investigation routes to stageUpdateInvestigation with args","suiteID":6394,"groupIDs":[6510,6716],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":447,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":864142}
{"testID":6719,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":864770}
{"test":{"id":6719,"name":"VisitTreatmentSection — investigations notifier wiring advanced: edit investigation routes to stageUpdateInvestigation with args","suiteID":6394,"groupIDs":[6510,6716],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":447,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":864142}
{"testID":6719,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":864770}
{"group":{"id":6720,"suiteID":6394,"parentID":6510,"name":"VisitTreatmentSection — attachments notifier wiring","metadata":{"skip":false,"skipReason":null},"testCount":1,"line":477,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"group","time":864771}
{"group":{"id":6720,"suiteID":6394,"parentID":6510,"name":"VisitTreatmentSection — attachments notifier wiring","metadata":{"skip":false,"skipReason":null},"testCount":1,"line":477,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"group","time":864771}
{"test":{"id":6721,"name":"VisitTreatmentSection — attachments notifier wiring advanced: delete attachment routes to stageDeleteAttachment","suiteID":6394,"groupIDs":[6510,6720],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":478,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":864771}
{"testID":6721,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":865137}
{"test":{"id":6721,"name":"VisitTreatmentSection — attachments notifier wiring advanced: delete attachment routes to stageDeleteAttachment","suiteID":6394,"groupIDs":[6510,6720],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":478,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":864771}
{"testID":6721,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":865137}
{"group":{"id":6722,"suiteID":6394,"parentID":6510,"name":"VisitTreatmentSection — saveStatus and errorMessage (not rendered here)","metadata":{"skip":false,"skipReason":null},"testCount":1,"line":496,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"group","time":865138}
{"group":{"id":6722,"suiteID":6394,"parentID":6510,"name":"VisitTreatmentSection — saveStatus and errorMessage (not rendered here)","metadata":{"skip":false,"skipReason":null},"testCount":1,"line":496,"column":3,"url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"group","time":865138}
{"test":{"id":6723,"name":"VisitTreatmentSection — saveStatus and errorMessage (not rendered here) regression: saveStatus and errorMessage in state do not surface in this section","suiteID":6394,"groupIDs":[6510,6722],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":497,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":865138}
{"testID":6723,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":865310}
{"test":{"id":6723,"name":"VisitTreatmentSection — saveStatus and errorMessage (not rendered here) regression: saveStatus and errorMessage in state do not surface in this section","suiteID":6394,"groupIDs":[6510,6722],"metadata":{"skip":false,"skipReason":null},"line":174,"column":5,"url":"package:flutter_test/src/widget_tester.dart","root_line":497,"root_column":5,"root_url":"file:///home/runner/work/AiClinic/AiClinic/frontend/test/widget/visits/visit_treatment_section_test.dart"},"type":"testStart","time":865138}
{"testID":6723,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":865310}
{"success":false,"type":"done","time":866780}
{"success":false,"type":"done","time":866780}

📁 Test artifacts: /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T070147Z-536da71a/frontend/all/unit

📁 Test artifacts: /home/runner/work/AiClinic/AiClinic/test-results/governor/20261015T070147Z-536da71a/frontend/all/unit
== boundary ==
ERROR: backend/local stack is not running.
  cd backend/local && docker compose up -d
ERROR: backend/local stack is not running.
  cd backend/local && docker compose up -d

```

### Failed / not-recorded tests (12)

#### `FAIL` E2E-P6.3-01 E2E-P6.3-01

- per-test log: `tests/002-e2e-p6-4-01-e2e-p6-4-01.log`
- failure source: `tests/002-e2e-p6-4-01-e2e-p6-4-01.log (flutter exception message)`

From tests/002-e2e-p6-4-01-e2e-p6-4-01.log (flutter machine log, exception message body):
```
H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack
billing tests.
```

#### `FAIL` E2E-P6.3-02 E2E-P6.3-02

- per-test log: `tests/003-e2e-p6-3-02-e2e-p6-3-02.log`
- failure source: `tests/003-e2e-p6-3-02-e2e-p6-3-02.log (flutter exception message)`

From tests/003-e2e-p6-3-02-e2e-p6-3-02.log (flutter machine log, exception message body):
```
LateInitializationError: Local 'ctx' has not been initialized.
```

#### `FAIL` E2E-P6.3-03 E2E-P6.3-03

- per-test log: `tests/004-e2e-p6-3-03-e2e-p6-3-03.log`
- failure source: `tests/004-e2e-p6-3-03-e2e-p6-3-03.log (flutter exception message)`

From tests/004-e2e-p6-3-03-e2e-p6-3-03.log (flutter machine log, exception message body):
```
LateInitializationError: Local 'ctx' has not been initialized.
```

#### `FAIL` E2E-P6.3-04 E2E-P6.3-04

- per-test log: `tests/005-e2e-p6-3-04-e2e-p6-3-04.log`
- failure source: `tests/005-e2e-p6-3-04-e2e-p6-3-04.log (flutter exception message)`

From tests/005-e2e-p6-3-04-e2e-p6-3-04.log (flutter machine log, exception message body):
```
LateInitializationError: Local 'ctx' has not been initialized.
```

#### `FAIL` E2E-P6.3-05 E2E-P6.3-05

- per-test log: `tests/006-e2e-p6-3-05-e2e-p6-3-05.log`
- failure source: `tests/006-e2e-p6-3-05-e2e-p6-3-05.log (flutter exception message)`

From tests/006-e2e-p6-3-05-e2e-p6-3-05.log (flutter machine log, exception message body):
```
LateInitializationError: Local 'ctx' has not been initialized.
```

#### `FAIL` E2E-P6.3-06 E2E-P6.3-06

- per-test log: `tests/007-e2e-p6-3-06-e2e-p6-3-06.log`
- failure source: `tests/007-e2e-p6-3-06-e2e-p6-3-06.log (flutter exception message)`

From tests/007-e2e-p6-3-06-e2e-p6-3-06.log (flutter machine log, exception message body):
```
LateInitializationError: Local 'ctx' has not been initialized.
```

#### `FAIL` E2E-P6.3-07 E2E-P6.3-07

- per-test log: `tests/008-e2e-p6-3-07-e2e-p6-3-07.log`
- failure source: `tests/008-e2e-p6-3-07-e2e-p6-3-07.log (flutter exception message)`

From tests/008-e2e-p6-3-07-e2e-p6-3-07.log (flutter machine log, exception message body):
```
LateInitializationError: Local 'ctx' has not been initialized.
```

#### `FAIL` E2E-P6.4-01 E2E-P6.4-01

- per-test log: `tests/009-e2e-p6-4-01-e2e-p6-4-01.log`
- failure source: `output.log (flutter exception print)`

From output.log (flutter machine stream, exception print for this test):
```
H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack
subscription tests.
```

#### `FAIL` E2E-P6.4-02 E2E-P6.4-02

- per-test log: `tests/010-e2e-p6-4-02-e2e-p6-4-02.log`
- failure source: `tests/010-e2e-p6-4-02-e2e-p6-4-02.log (flutter exception message)`

From tests/010-e2e-p6-4-02-e2e-p6-4-02.log (flutter machine log, exception message body):
```
H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack
subscription tests.
```

#### `FAIL` E2E-P6.4-03 E2E-P6.4-03

- per-test log: `tests/011-e2e-p6-4-03-e2e-p6-4-03.log`
- failure source: `tests/011-e2e-p6-4-03-e2e-p6-4-03.log (flutter exception message)`

From tests/011-e2e-p6-4-03-e2e-p6-4-03.log (flutter machine log, exception message body):
```
H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack
subscription tests.
```

#### `FAIL` E2E-P6.4-04 E2E-P6.4-04

- per-test log: `tests/012-e2e-p6-4-04-e2e-p6-4-04.log`
- failure source: `tests/012-e2e-p6-4-04-e2e-p6-4-04.log (flutter exception message)`

From tests/012-e2e-p6-4-04-e2e-p6-4-04.log (flutter machine log, exception message body):
```
H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack
subscription tests.
```

#### `FAIL` E2E-P6.4-05 E2E-P6.4-05

- per-test log: `tests/013-e2e-p6-4-05-e2e-p6-4-05.log`
- failure source: `tests/013-e2e-p6-4-05-e2e-p6-4-05.log (flutter exception message)`

From tests/013-e2e-p6-4-05-e2e-p6-4-05.log (flutter machine log, exception message body):
```
H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack
subscription tests.
```

---

## Subcampaign: `campaign-frontend-38695681551\governor\20261015T070147Z-536da71a\frontend\fullstack`

- label: `frontend/fullstack` — passed=0 failed=0 exit=1

### Last 60 lines of output.log

```
ERROR: H-FS stack dependencies are missing. Run `npm ci` in e2e/fullstack/ before the frontend fullstack campaign.

```

---

## Subcampaign: `campaign-ops-launch-38695681551\governor\20261015T065835Z-cfdfc88a\ops-launch\launch-check`

- label: `ops-launch/launch-check` — passed=2 failed=0 exit=0

---

## Subcampaign: `campaign-ops-launch-38695681551\ops-launch\launch-check\20261015T065835Z-024a600a`

- label: `ops-launch/launch-check` — passed=2 failed=0 exit=0

---

## Subcampaign: `campaign-vendor-contracts-38695681551\governor\20261015T065850Z-0a6fa8f1\vendor-contracts\all`

- label: `vendor-contracts/all` — passed=10 failed=1 exit=1

### Last 60 lines of output.log

```
      src/vendor/entrypoint.ts:19:7:
        19 │ } from "vendor-contracts";
           ╵        ~~~~~~~~~~~~~~~~~~
  
    To fix this, you can add an entry to "alias" in your Wrangler configuration.
    For more guidance see: https://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues
    
  
  
  ✘ [ERROR] Could not resolve "vendor-contracts"
  
      src/worker.ts:6:7:
        6 │ } from "vendor-contracts";
          ╵        ~~~~~~~~~~~~~~~~~~
  
    To fix this, you can add an entry to "alias" in your Wrangler configuration.
    For more guidance see: https://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues
    
  
  


🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"

 ❯ test/bundle-scan.test.ts:60:5
     58|     );
     59| 
     60|     execFileSync(
     58|     );
       |     ^
     61|       process.execPath,
     59| 
     62|       [
     60|     execFileSync(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
       |     ^
     61|       process.execPath,
     62|       [

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
Serialized Error: { status: 1, signal: null, output: [ null, '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' ], pid: 2635, stdout: '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', stderr: '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[1/1]⎯


Serialized Error: { status: 1, signal: null, output: [ null, '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' ], pid: 2635, stdout: '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', stderr: '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' }
 Test Files  1 failed | 8 passed (9)
      Tests  1 failed | 10 passed (11)
   Start at  06:58:50
   Duration  3.70s (transform 245ms, setup 0ms, collect 557ms, tests 1.36s, environment 2ms, prepare 662ms)

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[1/1]⎯


 Test Files  1 failed | 8 passed (9)
      Tests  1 failed | 10 passed (11)
   Start at  06:58:50
   Duration  3.70s (transform 245ms, setup 0ms, collect 557ms, tests 1.36s, environment 2ms, prepare 662ms)


```

### Failed / not-recorded tests (1)

#### `FAIL` test/bundle-scan.test.ts > production bundle scan > E2E-P2.2-08 A production ai-platform bundle contains no testkit code

- per-test log: `tests/012-test-bundle-scan-test-ts-production-bundle-scan.log`
- failure source: `output.log`

From output.log (15 lines around last error-adjacent mention of test/bundle-scan.test.ts):
```
  ✘ [ERROR] Could not resolve "vendor-contracts"
  
      src/worker.ts:6:7:
        6 │ } from "vendor-contracts";
          ╵        ~~~~~~~~~~~~~~~~~~
  
    To fix this, you can add an entry to "alias" in your Wrangler configuration.
    For more guidance see: https://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues
    
  
  


🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"

 ❯ test/bundle-scan.test.ts:60:5
     58|     );
     59| 
     60|     execFileSync(
     58|     );
       |     ^
     61|       process.execPath,
     59| 
     62|       [
     60|     execFileSync(

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
       |     ^
     61|       process.execPath,
     62|       [

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯
Serialized Error: { status: 1, signal: null, output: [ null, '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' ], pid: 2635, stdout: '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', stderr: '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' }
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[1/1]⎯


Serialized Error: { status: 1, signal: null, output: [ null, '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' ], pid: 2635, stdout: '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/telemetry.md\n\n', stderr: '\u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mBuild failed with 12 errors:\u001b[0m\n\n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/admission/index.ts:14:33:\n  \u001b[37m      14 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/alert/index.ts:1:33:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage-read/index.ts:5:50:\n  \u001b[37m      5 │ import { CHANNEL_VERSIONS, subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                                   \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/coverage/transfer.ts:7:7:\n  \u001b[37m      7 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/credit/index.ts:3:33:\n  \u001b[37m      3 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/pipeline/index.ts:48:33:\n  \u001b[37m      48 │ import { CHANNEL_VERSIONS } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵                                  \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/coverage.ts:9:7:\n  \u001b[37m      9 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/quota-do/index.ts:1:32:\n  \u001b[37m      1 │ import { coverageEventId } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/support/index.ts:1:32:\n  \u001b[37m      1 │ import { subscriptionRef } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                 \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/contract-version.ts:1:44:\n  \u001b[37m      1 │ import { CHANNEL_VERSIONS, negotiate } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵                                             \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/vendor/entrypoint.ts:19:7:\n  \u001b[37m      19 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n           ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n  \u001b[31m✘ \u001b[41;31m[\u001b[41;97mERROR\u001b[41;31m]\u001b[0m \u001b[1mCould not resolve "vendor-contracts"\u001b[0m\n  \n      src/worker.ts:6:7:\n  \u001b[37m      6 │ } from \u001b[32m"vendor-contracts"\u001b[37m;\n          ╵        \u001b[32m~~~~~~~~~~~~~~~~~~\u001b[0m\n  \n    To fix this, you can add an entry to "alias" in your Wrangler configuration.\n    For more guidance see: \u001b[4m\u001b[4mhttps://developers.cloudflare.com/workers/wrangler/configuration/#bundling-issues\u001b[0m\u001b[0m\n    \n  \n  \n\n\n🪵  Logs were written to "/home/runner/.config/.wrangler/logs/wrangler-2026-10-15_06-58-52_409.log"\n' }
 Test Files  1 failed | 8 passed (9)
      Tests  1 failed | 10 passed (11)
   Start at  06:58:50
   Duration  3.70s (transform 245ms, setup 0ms, collect 557ms, tests 1.36s, environment 2ms, prepare 662ms)

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[1/1]⎯
```

---

## Distinct error signatures (first error line, de-duplicated)

Total failing/not-recorded test entries: 144; distinct signatures: 21

- **(86 tests)** `Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\load`, `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(10 tests)** `code: 'ERR_TEST_FAILURE'`
  - subcampaigns: `campaign-e2e-fullstack-38695681551\governor\20261015T070039Z-78af63ae\e2e-fullstack\all-manual`
- **(9 tests)** `AssertionError: expected 409 to be 200 // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\e2e`, `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(6 tests)** `H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack`
  - subcampaigns: `campaign-frontend-38695681551\governor\20261015T070147Z-536da71a\frontend\all`
- **(6 tests)** `LateInitializationError: Local 'ctx' has not been initialized.`
  - subcampaigns: `campaign-frontend-38695681551\governor\20261015T070147Z-536da71a\frontend\all`
- **(4 tests)** `Serialized Error: { remote: true }`
  - subcampaigns: `campaign-abo-38695681551\governor\20261015T065913Z-244b6d47\abo\cross-worker`
- **(4 tests)** `AssertionError: expected false to be true // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(2 tests)** `AssertionError: expected [] to have a length of 1 but got +0`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\e2e`, `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(2 tests)** `Error: R2 object not found: null`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\e2e`, `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(2 tests)** `AssertionError: expected 'CREATE TABLE ai_attempt (\n  attempt_…' to be 'CREATE TABLE ai_attempt (\n  attempt_…' // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(2 tests)** `error: 'test timed out after 180000ms'`
  - subcampaigns: `campaign-e2e-fullstack-38695681551\governor\20261015T070039Z-78af63ae\e2e-fullstack\all-ci`, `campaign-e2e-fullstack-38695681551\governor\20261015T070039Z-78af63ae\e2e-fullstack\all-manual`
- **(2 tests)** `error: 'test failed'`
  - subcampaigns: `campaign-e2e-fullstack-38695681551\governor\20261015T070039Z-78af63ae\e2e-fullstack\all-ci`, `campaign-e2e-fullstack-38695681551\governor\20261015T070039Z-78af63ae\e2e-fullstack\all-manual`
- **(1 test)** `(no failure text captured)`
  - subcampaigns: `campaign-abo-38695681551\governor\20261015T065913Z-244b6d47\abo\cross-worker`
- **(1 test)** `AssertionError: expected null to be 'request/55a2ff13-97e1-49d7-8117-6af0f…' // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\e2e`
- **(1 test)** `AssertionError: export hashCanonicalJson must be data, not executable wiring: expected false to be true // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(1 test)** `AssertionError: expected 401 to be 200 // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(1 test)** `AssertionError: expected null to be truthy`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(1 test)** `AssertionError: expected undefined to be 'failed' // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(1 test)** `AssertionError: expected null to be 'request/fa906603-e645-4419-a2b1-7fe1d…' // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(1 test)** `AssertionError: expected 500 to be 200 // Object.is equality`
  - subcampaigns: `campaign-ai-platform-38695681551\governor\20261015T065855Z-999179fa\ai-platform\npm-test`
- **(1 test)** `Serialized Error: { status: 1, signal: null, output: [ null, '\n ⛅️ wrangler 4.86.0\n───────────────────\n\nCloudflare collects anonymous telemetry about your usage of Wrangler. Learn more at https://github.com/cloudflare/workers-sdk/tre…`
  - subcampaigns: `campaign-vendor-contracts-38695681551\governor\20261015T065850Z-0a6fa8f1\vendor-contracts\all`
