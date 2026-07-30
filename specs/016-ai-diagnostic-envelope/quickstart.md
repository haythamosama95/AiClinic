# Quickstart: Diagnostic envelope — error taxonomy, request reference, trace propagation (A2)

Slice **A2** adds the gateway's diagnostic envelope: a closed §5.4 error taxonomy with normative HTTP
mapping, a stable error-body contract, a Crockford-base32 request-reference generator, and a trace-id
resolver wired into the fetch path — so every later slice that emits or handles an error is
constrained by contracts that already exist.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. What was implemented

- **`ai-platform/src/errors.ts`** — the §5.4 taxonomy table (eighteen codes: HTTP status,
  retryability, quota-consumption flag); `retry_safe` boolean mapping (`false` for Retryable
  values `No` and `—`, `true` otherwise); error-body builder emitting
  `{"code","request_reference","trace_id","retry_safe"}`; unrecognised codes classified as
  `internal_error`; `context_requested` refused; `cancelled` classified to `499` but never
  emitted on a live socket; `rate_limited` / `quota_exhausted` supplementary fields; no bare
  `400`.
- **`ai-platform/src/reference.ts`** — CSPRNG request-reference generator
  (`^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`, omits `I`/`L`/`O`/`U`) and lookup
  normalisation (`I`/`L` → `1`, `O` → `0`, case-fold up).
- **`ai-platform/src/trace.ts`** — trace-id resolver (accept caller-supplied `x-trace-id` or
  generate a ULID); structured logger carrying `request_reference`, `trace_id`, installation,
  capability, and prompt version — never prompt text, context payload, or credentials.
- **`ai-platform/src/worker.ts`** — wires the envelope into the fetch path: resolves trace id at
  the top of `POST /v1/requests`, generates a request reference, rejects malformed bodies before
  taxonomy codes are built, and emits structured logs with the diagnostic fields.
- **Twenty-nine named contract/unit cases (T1–T29)** across five test files — **48 passing
  tests** total.

## 2. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/errors.ts` | §5.4 taxonomy table, `buildErrorBody`, `classifyErrorCode`, `isRetrySafe` |
| `ai-platform/src/reference.ts` | `generateRequestReference`, `normalizeRequestReference` |
| `ai-platform/src/trace.ts` | `resolveTraceId`, `createStructuredLogger` |
| `ai-platform/src/worker.ts` | Diagnostic envelope wiring in `handleCreateRequest` and `fetch` |
| `ai-platform/test/taxonomy.test.ts` | T1–T19, T24, T26, T29 — per-code taxonomy and edge cases |
| `ai-platform/test/error-body.test.ts` | T20 — error-body field contract |
| `ai-platform/test/reference.test.ts` | T21, T28 — generator format and normalisation |
| `ai-platform/test/trace.test.ts` | T22, T23 — trace propagation and ULID fallback |
| `ai-platform/test/log-redaction.test.ts` | T25, T27 — malformed-body rejection and log redaction |

## 3. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/taxonomy.test.ts test/error-body.test.ts test/reference.test.ts \
  test/trace.test.ts test/log-redaction.test.ts
```

Expect **48 passing tests** across the five A2 test files listed above.

## 4. Inspect the changes

Read the three contract modules:

```bash
cat ai-platform/src/errors.ts      # taxonomy table and buildErrorBody
cat ai-platform/src/reference.ts   # generator and normalisation
cat ai-platform/src/trace.ts       # resolveTraceId and structured logger
```

Inspect worker integration — trace resolution at the top of `handleCreateRequest`, malformed-body
rejection before taxonomy, and structured-log emission:

```bash
grep -n 'resolveTraceId\|generateRequestReference\|createStructuredLogger\|malformed' \
  ai-platform/src/worker.ts
```

Run a focused taxonomy or error-body check:

```bash
npx vitest run test/taxonomy.test.ts test/error-body.test.ts
```
