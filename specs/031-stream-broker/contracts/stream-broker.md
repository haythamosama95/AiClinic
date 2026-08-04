# Stream broker, prose streaming, and connection-scoped cancellation (D4)

Frozen stream-broker contract: ordered relay of normalized chunks over A6 SSE framing, heartbeat
emission during provider silence, `prose` incremental and completion-time guards with an
authoritative terminal payload, and broker-owned connection-scoped cancellation (abort signal →
`cancelled` → partial-usage credit → journal-terminal outcome) with no per-request server-side
state. Later slices **D6** (structured modes / full validator), **E4** (first AI surface / CP3),
and **H1** (`context_requested`) **consume** this artifact — they must not rewrite the relay,
heartbeat, one-terminal-event, or connection-scoped cancel duties, nor introduce a Session Durable
Object or out-of-band cancel endpoint here.

**Source of truth in code (this slice):** `ai-platform/src/stream/index.ts` (prose broker),
`ai-platform/src/stream/prose-guards.ts`. Structured modes live in `ai-platform/src/stream/structured.ts`
(`createStructuredStreamBroker`) and are **D6-owned** — not a D4 deliverable.

**Traces to:** spec Freezes (stream broker; prose path; connection-scoped cancel; no OOB cancel /
Session DO / resume); FR-001–FR-013; architecture §4.3.10, §6.4, §5.5, §6.5, §9.7.

---

## 1. Overview

After D3's invocation loop begins producing normalized output against the provider port, the stream
broker relays content to the client over A6's SSE framing. For `prose`, it emits `text_delta`
events in order, applies cheap incremental guards, emits heartbeats while the provider is silent,
runs the full guard set on the assembled text at completion, and ends with exactly one terminal
event. When the client disconnects, the broker aborts the in-flight provider fetch through its
abort signal, terminates as `cancelled`, credits partial usage when present, and leaves a complete
journalable terminal outcome — without creating per-request server-side state (§4.3.10; §6.4; §6.5;
§9.7).

A6 owns wire framing and the one-terminal-event state machine. D3 owns retry, fallback, and
`regenerating`. D4 owns broker behaviour that *uses* those contracts. The named adapter
`createChunkSourceFromInvocationEvents` bridges D3 InvocationSink-shaped events (`text` /
`regenerating`) into the broker's `ChunkSource`.

---

## 2. Stream broker duties

**Module:** `ai-platform/src/stream/index.ts`

| Duty | Detail |
| --- | --- |
| Ordered relay | Normalized chunks from invocation are relayed to the client sink in order as A6 content events (`text_delta` for `prose`) (FR-001; T1) |
| Heartbeats | While the stream is open and idle during provider silence, emit A6 `heartbeat` events so intermediaries do not time out (FR-001; §5.5 rule 3; T2). Interval is driven by an injectable ticker (Clarification Q2); the schedule handle exposes `notifyActivity()`, and the broker resets silence on each relayed content chunk (including `regenerating`). This contract does not freeze a numeric interval |
| One terminal event | Every broker path ends with exactly one of `completed`, `failed`, or `cancelled`. A terminal is never inferred from silence (FR-005; §5.5 rule 4; T15). Framing enforcement remains A6; the broker must not emit a second terminal |
| Provisional vs committed | Relayed `text_delta` chunks are for responsiveness only. Only the validated terminal payload is authoritative (FR-013; §6.4 invariant 1; T18) |
| No per-chunk journal | The broker does not write a D1 row per stream chunk (FR-012; §7.5; T19) |
| No per-request state | An in-flight request exists only as an open connection plus the journal row from acceptance; the broker creates no per-request Durable Object or live request registry (FR-007, FR-012; §4.3.10; §9.7; T12) |
| D3 event adapter | `createChunkSourceFromInvocationEvents` maps InvocationSink-shaped events (`{ kind: "text"; text }` / `{ kind: "regenerating" }`) into `ChunkSource` / `StreamChunk`, preserving regenerating as a first-class chunk (T27) |

### 2.1 Injectable dependencies (implementation surface, not new architecture)

| Dependency | Role |
| --- | --- |
| Client / SSE event sink | Receives A6-shaped events (`text_delta`, `heartbeat`, `completed`, `failed`, `cancelled`, and relayed `regenerating` when D3 emits it) |
| Heartbeat ticker | Controllable schedule for silence heartbeats (Clarification Q2). `schedule(callback)` returns a handle with `cancel()` and `notifyActivity()` |
| In-flight `AbortSignal` / `AbortController` | Broker-owned signal for the provider fetch; disconnect aborts it (Clarification Q3) |
| Partial-usage credit sink | Records partial usage on cancel when `ChunkSource.getPartialUsage()` returns a live value at cancel time; absent or `undefined` → credit sink is not called (Clarification Q4; B4 credit shape, not a rewrite of B4; T10, T22) |
| Journal-terminal sink | Records a complete terminal `cancelled` / `completed` / `failed` outcome; `failed` includes `terminalErrorCode` (Clarification Q4; C3 writer unchanged; T11, T24) |

**Terminal emission order:** the terminal SSE event is emitted before credit/journal sinks run.
Sink throws must not suppress the terminal event (T25).

Production wiring of `createStreamBroker` into the Worker pipeline (B4/C3 sinks, E4 surface) is
intentionally deferred. This slice freezes the broker module and its injectable surface; it does
**not** change B4/C3 module contracts or call the broker from `worker.ts`.

---

## 3. Prose streaming path

**Module:** `ai-platform/src/stream/prose-guards.ts` (guards); broker in `index.ts` applies them.

| Phase | Behaviour |
| --- | --- |
| During stream | Emit `text_delta` events. Apply cheap guards **incrementally** against **assembled** text (cumulative length ceiling, stop-sequence, system-prompt-leak). Length is never evaluated per-chunk alone. A violation aborts the stream and fails terminally with exactly one `failed` event (FR-002; T3–T5) |
| At completion | Run the **full** guard set on the assembled text before the terminal event (FR-003; T6). Full set returns a violation kind (non-throwing): assembled length ceiling plus deferred `empty_output` (empty assembled text checked only at completion — empty streams never trip incremental guards) |
| On success | Emit exactly one `completed` carrying the validated payload — self-contained; clients must not assemble the final result from chunks (FR-004; §6.4 invariant 1; T7) |

| Guard kind | On violation |
| --- | --- |
| Length ceiling (assembled) | Abort stream → `failed` |
| Stop-sequence | Abort stream → `failed` |
| System-prompt-leak | Abort stream → `failed` |
| Empty output (full set only) | → `failed` |

Numeric thresholds are **parameters** supplied by capability/manifest or platform config already
named elsewhere; this slice freezes the guard *kinds*, not new threshold constants (spec
Assumptions). The `failed` terminal carries an existing A2 taxonomy code (`validation_failed`);
D4 does not add or rename taxonomy codes.

`structured` / `structured_atomic` streaming semantics in §6.4 are **out of scope** for D4.
D6 owns `ai-platform/src/stream/structured.ts` (`createStructuredStreamBroker`). Schema /
business-rule validation and bounded repair remain D6.

---

## 4. Connection-scoped cancellation

| Rule | Detail |
| --- | --- |
| Trigger | Client closes the stream (deliberate Cancel) or the connection drops — indistinguishable (§5.5 rule 5; FR-006; T16) |
| Abort | Broker aborts the in-flight provider fetch through its abort signal (FR-006; T8) |
| Terminal | Request ends as `cancelled` (FR-006; T9). `disconnect` emits `cancelled` synchronously so a signal-ignoring source cannot hang the one-terminal / credit / journal guarantees; abortable iteration bounds signal-ignoring sources (T26) |
| Partial usage | `ChunkSource.getPartialUsage()` is called live at cancel settle time and must reflect tokens generated before the cancel point. Absent or `undefined` → no credit (FR-008; §6.5; T10, T22). Cancel is not free when usage exists |
| Journal | A complete terminal `cancelled` outcome is left for the journal; the request remains explainable (FR-009; §5.5 rule 6; T11). Writing the D1 row remains C3 |
| Scope | Connection-scoped only: no separate cancel endpoint, no request registry, no per-request server-side state (FR-007; T12, T17) |
| Timing | Cancel before the first token and cancel mid-stream are both supported and both follow the same abort → `cancelled` → credit-when-present path (FR-011; T13, T14) |

### 4.1 Source error containment

| Condition | Outcome |
| --- | --- |
| Source throw after disconnect / abort (including `AbortError`) | → `cancelled` + journal; credit when `getPartialUsage()` is present (T20) |
| Other source throw mid-stream | → exactly one `failed` with taxonomy `internal_error` + journal (`terminalErrorCode`); no credit (T21) |
| Disconnect after a terminal already emitted | no-op — no second terminal (T23) |

---

## 5. Explicit non-support

| Not supported | Why frozen here |
| --- | --- |
| Out-of-band cancel (different window / after reconnect) | Would require a Session Durable Object (§4.3.10; §9.7; FR-010; T17) |
| Separate cancel HTTP endpoint | Connection close is the cancel mechanism (§5.5 Cancel row; FR-007; T17) |
| Stream resume after reconnect | Same — no per-request state to resume into (§6.5; §9.7; FR-010) |
| Session Durable Object | Rejected for now under §9.7; not added because it looks prudent (R-20; T17) |
| Structured streaming modes | Owned by D6 (`structured.ts`); not part of the D4 prose broker surface |

---

## 6. Consumers

| Slice | Binding |
| --- | --- |
| **D6** | Owns `src/stream/structured.ts` / `createStructuredStreamBroker`; extends what the broker may carry for structured modes; must not rewrite prose relay, heartbeat, or one-terminal duties |
| **E4 / CP3** | Client displays live draft from provisional chunks and commits only on validated `completed`; production wiring of `createStreamBroker` into the Worker pipeline is deferred to E4 (with B4/C3 sinks) |
| **H1** | May extend terminal kinds with `context_requested`; must not rewrite connection-scoped cancel |

Later slices MUST **consume** this artifact. They may wire sinks to B4/C3 and extend content event
kinds for structured/conversational modes; they must not rewrite the relay, heartbeat emission
duty, one-terminal-event rule on broker paths, provisional-versus-committed emission, or
connection-scoped cancel / no-Session-DO prohibitions.

---

## 7. Verification

| Test | Asserts |
| --- | --- |
| T1 | Chunks relayed in order as `text_delta` |
| T2 | ≥1 heartbeat during provider silence (injectable ticker; activity resets silence) |
| T3 | Length-ceiling guard aborts → `failed` (assembled / cumulative) |
| T4 | Stop-sequence guard aborts → `failed` |
| T5 | System-prompt-leak guard aborts → `failed` |
| T6 | Full guard set runs on assembled text (incl. deferred `empty_output`) |
| T7 | `completed` carries validated payload |
| T8 | Disconnect aborts provider fetch via abort signal |
| T9 | Disconnect → terminal `cancelled` |
| T10 | Partial usage credited on cancel (live `getPartialUsage`) |
| T11 | Journal-terminal record complete on cancel |
| T12 | No per-request state object created |
| T13 | Cancel before first token |
| T14 | Cancel mid-stream |
| T15 | Exactly one terminal under guard abort and under cancel |
| T16 | Network drop ≡ deliberate Cancel |
| T17 | No OOB cancel endpoint / Session DO |
| T18 | Provisional chunks not authoritative |
| T19 | No D1 row per stream chunk |
| T20 | Abort-rejecting source still cancels |
| T21 | Mid-stream source throw → `failed` / `internal_error` + journal |
| T22 | Zero-usage cancel skips credit |
| T23 | Disconnect after completion is a no-op |
| T24 | Journal on `completed` and `failed` (with `terminalErrorCode`) |
| T25 | Sink throw does not suppress terminal |
| T26 | Signal-ignoring source: disconnect emits `cancelled` promptly |
| T27 | Invocation adapter relays `regenerating` |
