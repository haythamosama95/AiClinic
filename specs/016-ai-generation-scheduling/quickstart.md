# Quickstart — AI Generation Pipeline + Scheduling Agent (016)

**Branch**: `ai/016-generation-scheduling` | **Date**: 2026-07-18
**Spec**: `specs/016-ai-generation-scheduling/spec.md`
**Plan**: `specs/016-ai-generation-scheduling/plan.md`

This quickstart verifies the **end-to-end generation path** shipped by feature 016, building on
the Phase 1 control plane (feature 015). It exercises the scheduling agent end-to-end through
both the non-streaming and SSE streaming paths, asserts the resilience envelope, and confirms the
isolation invariant (no Supabase calls).

> Assumes Phase 1 quickstart has already been run successfully (Gateway + Ollama runner up on
> `127.0.0.1:8090` and `127.0.0.1:11434`, model `qwen3:4b` digest-pinned and loaded, health/ready
> green, `/v1/capabilities` responding).

## Prerequisites

- Phase 1 artifacts on the clinic server node:
  - `ai/gateway/` running (or run via `uvicorn` / Docker compose).
  - `ai/runners/ollama/` Ollama running on `127.0.0.1:11434`; `qwen3:4b` (Q4_K_M) digest-pinned
    and loaded.
- A valid Supabase staff JWT for a user whose role has `ai.access` (doctor or administrator by
  default per Phaes 1 seed). Set `$JWT` in your shell.
- `curl` ≥ 7.84 (for SSE, `-N` no-buffer) and `jq` for pretty-printing JSON.

## Step 1 — Verify capabilities advertises the scheduling agent

```bash
curl -s -H "Authorization: Bearer $JWT" http://127.0.0.1:8090/v1/capabilities | jq .
```

Expected:

```json
{
  "schema_version": "1.0",
  "streaming": true,
  "tasks": ["command"],
  "commands": [
    "create_appointment", "reschedule_appointment",
    "cancel_appointment", "update_appointment_status"
  ],
  "runners": [ { "id": "runnerA", "model": "qwen3:4b", "digest": "sha256:…",
                 "status": "READY", "features": ["json_grammar"], "context_tokens": 8192 } ]
}
```

If `tasks` does not include `"command"` or `commands` is empty, abort — feature 016 has not been
deployed correctly.

## Step 2 — Non-streaming happy path: `create_appointment`

```bash
curl -s -X POST http://127.0.0.1:8090/v1/ai/generate \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "task": "command",
    "prompt": "book Ahmed Hassan with Dr Ali tomorrow 5pm",
    "context": {
      "branch_name": "Main",
      "now": "2026-07-18T09:00:00+03:00",
      "active_patient": { "name": "Ahmed Hassan" },
      "doctors": [ { "name": "Dr. Ali" } ]
    },
    "options": { "stream": false }
  }' | jq .
```

Expected response (shape — exact confidence/wording varies):

```json
{
  "schema_version": "1.0",
  "task": "command",
  "command_type": "create_appointment",
  "confidence": 0.9,
  "display_summary": "Book Ahmed Hassan with Dr. Ali tomorrow at 5:00 PM.",
  "params": {
    "patient_name": "Ahmed Hassan",
    "doctor_name": "Dr. Ali",
    "date": "2026-07-19",
    "time": "17:00",
    "type": "planned"
  },
  "requires_resolution": {
    "patient_id": "lookup_required",
    "doctor_id": "lookup_required"
  },
  "warnings": [],
  "needs_clarification": false
}
```

Assert (manually or via the test suite):

- [x] `command_type` is `create_appointment`.
- [x] `display_summary` mentions both "Ahmed Hassan" and "Dr. Ali" and references tomorrow's date.
- [x] `requires_resolution` carries `patient_id` and `doctor_id` as `"lookup_required"`
  (bare-string form — the AI did NOT fabricate ids).
- [x] `needs_clarification` is `false` (above default threshold `0.6`).
- [x] No `id` field appears inside `params` — entity ids are resolution directives only.

## Step 3 — SSE streaming happy path (same input, identical `final`)

```bash
curl -sN -X POST http://127.0.0.1:8090/v1/ai/generate \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "task": "command",
    "prompt": "book Ahmed Hassan with Dr Ali tomorrow 5pm",
    "context": {
      "branch_name": "Main",
      "now": "2026-07-18T09:00:00+03:00",
      "active_patient": { "name": "Ahmed Hassan" },
      "doctors": [ { "name": "Dr. Ali" } ]
    },
    "options": { "stream": true }
  }'
```

Expected stream (event order; zero or more `summary` events before the terminal):

```
event: summary
data: {"delta":"Looking up tomorrow's availability..."}

event: final
data: {"schema_version":"1.0","task":"command","command_type":"create_appointment",...}
```

Assert:

- [x] Exactly one terminal event (`final` or `error`); never both.
- [x] No `event: token` events appear (command tasks never stream partial actionable JSON).
- [x] The `final` event's payload equals the non-streaming body in Step 2 (modulo confidence
  jitter — `command_type`, `params` fields the model resolved, `display_summary`, and
  `requires_resolution` MUST match for the same input).
- [x] The `final` payload validates as a Command Protocol envelope (jq parses; `schema_version`,
  `task`, `command_type`, `confidence`, `display_summary`, `params`, `requires_resolution`,
  `warnings`, `needs_clarification` all present).

## Step 4 — Semantic validation rejects past dates (`422 ai_unusable`)

```bash
curl -s -X POST http://127.0.0.1:8090/v1/ai/generate \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "task": "command",
    "prompt": "book Ahmed Hassan with Dr Ali yesterday 9am",
    "context": {
      "branch_name": "Main",
      "now": "2026-07-18T09:00:00+03:00",
      "active_patient": { "name": "Ahmed Hassan" },
      "doctors": [ { "name": "Dr. Ali" } ]
    },
    "options": { "stream": false }
  }' | jq .
```

Expected (the model is constrained to emit a valid envelope; the Gateway's semantic validator
catches the past date and rejects the proposal):

```json
{ "error": { "code": "ai_unusable",
             "message": "Proposed appointment date is in the past.",
             "request_id": "..." } }
```

HTTP status `422`.

Assert:

- [x] Response is `422` with `code=ai_unusable` and a `request_id`.
- [x] The Gateway did **not** retry (per /clarify Q3 — `422` is terminal).
- [x] The structured log for this request_id has `outcome=error` and `error_class=ai_unusable`
  (find it in `ai/gateway/logs/`).

## Step 5 — Low confidence → `needs_clarification=true`

Craft an ambiguous prompt with multiple doctor matches and confirm the Gateway's
`needs_clarification` flag reflects the configured threshold:

```bash
curl -s -X POST http://127.0.0.1:8090/v1/ai/generate \
  -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{
    "task": "command",
    "prompt": "book Ahmed with the doctor tomorrow",
    "context": {
      "branch_name": "Main",
      "now": "2026-07-18T09:00:00+03:00",
      "active_patient": { "name": "Ahmed" },
      "doctors": [ { "name": "Dr. Ali" }, { "name": "Dr. Sara" } ]
    },
    "options": { "stream": false }
  }' | jq .
```

Expected: the model attempts a proposal but is uncertain; `confidence < 0.6` and the envelope
shows:

```json
{ ..., "confidence": 0.4, ..., "needs_clarification": true, ... }
```

Assert:

- [x] `needs_clarification` is `true` (the Gateway set it from `ai.confidence_threshold`).
- [x] `confidence` is still present (raw model output is always carried).

## Step 6 — Cancellation frees the queue slot

Start a streaming request that simulates a slow runner (e.g., a prompt known to take > 10 s,
or temporarily point the Gateway at a slow fake runner for this step):

```bash
curl -sN -X POST http://127.0.0.1:8090/v1/ai/generate \
  -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{ "task":"command", "prompt":"...", "context":{...}, "options":{"stream":true} }' \
  --max-time 2 &
CURL_PID=$!
sleep 1
kill -INT $CURL_PID   # client aborts mid-stream
wait $CURL_PID 2>/dev/null
```

Inspect the log:

```bash
tail -n 100 ai/gateway/logs/*.jsonl | jq 'select(.request_id == "...") | {outcome, request_id}'
```

Assert:

- [x] The request log shows `outcome="cancelled"` (NOT `"error"`).
- [x] The queue depth gauge (`ai_queue_depth` in `/metrics`) returns to its prior value within
  one poll cycle.
- [x] No terminal SSE event is emitted (the client is no longer listening); the cancellation is
  recorded in the local log only.

## Step 7 — Isolation invariant reaffirmation

Across all the above requests, the Gateway MUST make **zero** outbound calls to Supabase.

If you have packet capture or test instrumentation available, assert:

```bash
grep -E "supabase|postgres" ai/gateway/logs/*.jsonl   # MUST return nothing
```

The Phase 1 isolation scan (`ai/gateway/scripts/isolation_scan.py`) is **unchanged** in scope
this feature and remains a CI gate:

```bash
python ai/gateway/scripts/isolation_scan.py && echo "isolation: PASS"
```

Assert:

- [x] `isolation_scan.py` passes (no DB credentials / service-role keys / DB-client imports
  in `ai/`).

## Step 8 — Run the Phase 2 contract suite (the authoritative gate)

The manual steps above are illustrative. The authoritative verification of feature 016's exit
criteria is the Phase 2 contract test suite (spec §15 🧪 block, Phase 2):

```bash
cd ai/gateway && pytest tests/contract/ -v
```

Expected: all green. This covers schema/grammar/semantic conformance per command type,
streaming-vs-non-streaming equivalence, resilience (saturation/backpressure/timeouts/retry/
cancel), prompt-injection fuzzing, PHI-redaction assertions, and the Phase 1 regression suite
(`/health`, `/ready`, `/v1/capabilities`, auth matrix).

## Feature exit criteria (from `spec.md`)

This quickstart demonstrates each success criterion is verifiable. The feature is **exit-ready**
when:

- [x] SC-001: realistic scheduling prompts → schema-valid envelope with bare-string
  `requires_resolution` for patient/doctor id fields.
- [x] SC-002: non-streaming body and streaming `final` event are equivalent for the same input.
- [x] SC-003: grammar-constrained decoding makes invalid JSON impossible;
  `422 ai_unusable` on past date / bad enum / missing required param.
- [x] SC-004: prompt-injection attempts cannot produce off-catalog `command_type` and trigger
  zero Supabase calls.
- [x] SC-005: saturation → `503 ai_busy` + `Retry-After` with bounded memory; per-caller cap
  enforced.
- [x] SC-006: first-token/total timeouts → `504 ai_timeout`; retry hits a different runner when
  available; no retry after partial stream.
- [x] SC-007: cancellation frees the queue slot and is logged `cancelled`.
- [x] SC-008: model swap served within extended timeout; never more than one model in RAM.
- [x] SC-009: with `log_verbatim=false` (default), no verbatim patient-name in logs;
  `/metrics` reflects generation signals.
- [x] SC-010: zero outbound calls to Supabase / off-LAN; isolation scan passes.
- [x] SC-011: `/v1/capabilities` advertises `streaming`, `command`, and the four command types;
  mirrors live registry.
- [x] SC-012: every failure carries the typed error contract; `enable_multi_command_plans=false`
  keeps emission single-command even when clients request `plan_mode="multi"`.