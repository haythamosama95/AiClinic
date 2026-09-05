# Stage 08 failure report

Command: `npx vitest run --config vitest.e2e.config.ts test/e2e/stage-08-*`
Working directory: `/home/haytham/Desktop/AiClinic/ai-platform`
Catalog: `docs/testing/catalog/stage-08-request-ingress.md`
Exit code: 0

Miniflare compatibility-date warnings (`requested "2026-05-03"`, falling back to `"2025-09-06"`) are not test failures.

## 1. Counts

- Passing: 57
- Skipped: 3
- Failing: 0
- Total tests: 60

**Zero failures.** 57 passed, 3 skipped, 0 failed (60 total).

Test files: 3 (3 passed, 0 failed)

| File | Result |
| --- | --- |
| `test/e2e/stage-08-size-json-headers.test.ts` | 17 passed, 3 skipped (S08-001…S08-020) |
| `test/e2e/stage-08-trace-auth.test.ts` | 20 passed (S08-021…S08-040) |
| `test/e2e/stage-08-guard-sse-adapter.test.ts` | 20 passed (S08-041…S08-060), including S08-057 which failed on the prior run |

## 2. Vitest summary

```
 Test Files  3 passed (3)
      Tests  57 passed | 3 skipped (60)
   Start at  13:21:09
   Duration  19.27s (transform 467ms, setup 182ms, collect 2.30s, tests 26.17s, environment 1ms, prepare 737ms)
```

Per-file:

```
 ✓ test/e2e/stage-08-size-json-headers.test.ts (20 tests | 3 skipped) 3363ms
 ✓ test/e2e/stage-08-trace-auth.test.ts (20 tests) 6144ms
 ✓ test/e2e/stage-08-guard-sse-adapter.test.ts (20 tests) 16661ms
```

## 3. Failures

None. Catalog `docs/testing/catalog/stage-08-request-ingress.md` scenarios S08-001 through S08-060 either passed or were the three Register 5 skips listed below. No assertion failed and no uncaught test exception was reported.

The prior-run failure (S08-057 — `AbortError: The operation was aborted` at `AbortSignal.abort()` while constructing `new Request`, before `SELF.fetch`) did not reproduce. This run executed S08-057 as a passing `it(...)` in `stage-08-guard-sse-adapter.test.ts`; workerd emitted `ingress_body_parse_failed` only for S08-059 (expected bare-422 path), and the file closed with 20/20 passed.

S08-061…S08-069 (deferred to pgTAP / PostgREST; catalog non-automatable note 2) did **not** appear as tests or skips.

## 4. Skipped IDs

Register 5 skips (not failures), Content-Length / Register 5 #37 — catalog non-automatable note 1: workerd may strip `Content-Length` on constructed `Request`; no in-pool seam. All three are `it.skip` in `test/e2e/stage-08-size-json-headers.test.ts`.

- **S08-003** — Content-Length one byte over 1 MiB. Catalog: HTTP 413 `{"code":"request_too_large","request_reference":"","trace_id":"","retry_safe":false}` when `Content-Length: 1048577` is declared on a small body. Skip reason: in-pool `Request` cannot retain that header.
- **S08-005** — Under-declared Content-Length smuggle. Catalog: HTTP 413 `request_too_large` (empty reference/trace) when `Content-Length: 1024` but the stream is 1,048,577 bytes. Skip reason: same Content-Length seam.
- **S08-009** — Non-numeric Content-Length. Catalog: `Content-Length: abc` is ignored (`Number.isFinite` fails); request reaches preAccept → HTTP 401 `unauthenticated` taxonomy JSON with a Crockford reference. Skip reason: same Content-Length seam.

In-pool size coverage that did run: S08-004 (chunked oversize → 413), S08-006 (exactly 1 MiB → not 413, then 401), S08-007 (UTF-8 byte counting → 413), S08-008 (oversize wins over invalid JSON/missing headers → 413).
