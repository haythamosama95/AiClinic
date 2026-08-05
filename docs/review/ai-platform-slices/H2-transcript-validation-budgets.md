# H2 — Transcript validation, conversation budgets, and composer rendering

Static review of slice H2 against `docs/architecture/17-ai-platform.md` §4.3.5, §6.7.1, §6.7.3,
§4.3.6, §6.7.2 (source of truth) and `specs/045-transcript-validation-budgets/` (spec, plan,
contracts). No code was built or executed; no implementation files were modified.

Implementation files reviewed:

- `ai-platform/src/context/validator.ts` (transcript shape/order, budgets, allowlist)
- `ai-platform/src/context/preflight.ts` (consumed, unchanged)
- `ai-platform/src/context/context-request.ts` (consumed H1 schema, unchanged)
- `ai-platform/src/prompt/composer.ts` (prior-turn rendering, dual output-shape offer)
- `ai-platform/src/validate/phases.ts`, `ai-platform/src/validate/index.ts` (dual acceptance)
- `ai-platform/test/transcript-validation.test.ts`,
  `ai-platform/test/conversational-composer.test.ts`,
  `ai-platform/test/conversational-response-validator.test.ts`

## 1. Executive Summary

H2 is a faithful implementation of its core contract in the areas that matter most: the closed
transcript wire shape is enforced whole (accept-or-reject, no coercion), shape is checked before
budgets, both budgets are counted from the submitted transcript alone and breach with
`conversation_budget_exhausted`, the permitted-key allowlist drops (never rejects) unknown keys
including inside `context_resolved`, the cost pre-flight mechanism is reused unchanged, the closed
role-tag set is respected, `single_shot` behaviour is untouched, and no new taxonomy codes were
introduced. Error codes, evaluation order, and D6 phase order/repair all match the architecture.

The main concerns are: (a) R-10 containment for transcript user/model turns rests on the role tag
alone — the text is rendered raw with none of the delimiting/escaping that §4.3.6 and H2's own
frozen composition contract describe as the mechanism, and the architecture wording itself is
internally ambiguous here; (b) conversational context values receive no published-shape or size
validation despite §6.7.1 requiring `context_resolved` payloads to be "keyed and shaped exactly as
an ordinary context payload"; (c) the H1-frozen `transcriptSizeLimit` manifest field is never read
by any code; and (d) several required tests are weak (self-spies, missing branches) — most notably
the R-10 delimiter-neutralization property and the tail-only context-round branch are untested. No
pipeline wiring exists in `src/` yet (no caller of `validateContext` / `runCostPreflight` /
`composeRequest` / `validateAndRepair`), so integration-level claims ("no egress") are currently
untestable and the tests do not attempt them.

No Critical-severity findings.

## 2. Critical Issues

None found.

## 3. Bugs

1. **(Medium)** `context_requested` turn payload is validated only as "is an array", never for
   element shape — `ai-platform/src/context/validator.ts:156-163` casts `turn.requests` to
   `ContextRequest` after a bare `Array.isArray` check. A client can supply `requests: ["garbage",
   42]` and it passes validation, then is serialized verbatim into an assistant part by the
   composer (`ai-platform/src/prompt/composer.ts:147-151`). §6.7.1 defines this payload as "the
   platform-owned `{key, arguments}` list the assistant asked for on that turn, verbatim as the
   platform emitted it"; the transcript is explicitly untrusted (§6.7.3), so echoing unvalidated
   client content as a prior platform emission is a defence-in-depth gap even though the "Payload
   type: `array`" table cell makes it technically contract-conformant. Elements should be checked
   with H1's `validateContextRequest` (rejecting with `context_invalid`).
2. **(Medium)** Conversational context values get no published-shape or per-key size validation.
   The conversational path (`ai-platform/src/context/validator.ts:275-314`) only filters keys
   against the permitted set; the `validatePayload` shape check and `maxSize` byte check used on
   the single-shot path (`validator.ts:371-395`) are never applied — neither to the ordinary
   supplied context nor to `context_resolved` turn payloads. §6.7.1 requires `context_resolved`
   context to be "keyed and shaped exactly as an ordinary context payload ([§5.2])", and §4.3.5's
   validator duties include "shapes conform, sizes within bounds". A permitted key carrying a
   mistyped or oversized value reaches the composer, bounded only by the stage-7 pre-flight.
3. **(Low)** A missing `transcript` field is silently treated as an empty transcript —
   `validator.ts:283` (`parseTranscript(options.transcript ?? [])`). The wire contract
   (`contracts/transcript-wire.md` §2) carries `transcript` on the leg; omission should arguably be
   `context_invalid` rather than an implicit first leg. Not architecture-decided; flagged as an
   edge-case decision that was made implicitly.
4. **(Low)** Budget predicates fail open on non-numeric manifest values — `validator.ts:292,297`
   (`Number(manifest.Interaction.maxHistoryTurns)` / `Number(...maxContextRoundsPerTurn)`; any
   comparison against `NaN` is `false`, silently disabling the bound). The manifest loader
   (`ai-platform/src/manifest/index.ts:336-343`) asserts presence only, not numeric type. This is
   inconsistent with the pre-flight's deliberately fail-closed stance on non-numeric Economics
   (`ai-platform/src/context/preflight.ts:54-61`). Manifests are pinned/trusted, so low severity.
5. **(Low)** Dual-acceptance heuristic edge cases — `ai-platform/src/validate/phases.ts:127-133`
   rejects any output whose trimmed text starts with `{` or `[` as "neither prose nor context
   request", so a legitimate prose answer opening with `[` (e.g. "[Note] …") is falsely failed;
   and `phases.ts:110` + `ai-platform/src/context/context-request.ts:26-54` accept an empty array
   `[]` as a valid context request (zero requested keys would end the leg as `context_requested`
   with nothing to resolve). Both are survivable (repair/`validation_failed` path, H1-owned schema)
   but are unexamined branches of the "exactly two permitted shapes" rule (§6.7.2).
6. **(Low)** "Neither" failures are reported with phase `"schema"` (`phases.ts:120-131`) although
   they are parse/shape-level rejections; D6's phase vocabulary reserves `transport_parse` for
   that. Cosmetic mislabel that will surface in repair journals.

## 4. Architectural Deviations

1. **(High)** Transcript `user` and `model` turn text is rendered raw — no delimiting, no typing,
   no escaping (`ai-platform/src/prompt/composer.ts:141-146`; `context_requested` at
   `composer.ts:147-151` likewise uses unneutralized `JSON.stringify`). H2's own frozen contract
   (`contracts/conversational-composition.md` §2–3) states user turns are rendered "delimited/typed
   so instruction-like content cannot act as an instruction (R-10)" and that "escaping / block
   opacity (D1's delimited renderer)" is the mechanism; §4.3.6 states "both the transcript's user
   turns and any context resolved during the conversation are rendered as delimited, typed data on
   the same footing as ordinary context … that escaping, not a plea in the system instruction, is
   what stops an embedded instruction from acting as one". Only `context_resolved` and ordinary
   context receive the `<key name=… shape=…>` + `</`-neutralization treatment
   (`composer.ts:37-39,113-131`). For user turns, R-10 therefore rests solely on the `user` role
   tag, not on "a property of the shape". Note the architecture is internally ambiguous (§4.3.6
   also fixes `user` as the role tag for user turns, and the role table is honoured), so part of
   this finding is a documentation issue: the "same footing as ordinary context" sentence and the
   role-tag table pull in different directions and should be reconciled.
2. **(Medium)** `Interaction.transcriptSizeLimit` (a field H1 froze and the H2 spec's Consumes
   lists among those "H2 enforces … at runtime") is never read anywhere — the only occurrence in
   the codebase is its declaration in `ai-platform/src/manifest/index.ts:80`. Per-turn size is
   enforced solely through `Economics.maxInputTokens` / `perRequestCostCeiling` in the existing
   pre-flight. The H2 spec's Assumptions section says "transcript size limit via pre-flight", which
   conflicts with H1 freezing a distinct numeric limit. Either the field is dead configuration
   (documentation/implementation mismatch) or a named bound is unenforced. Relates to §6.7.3 and
   the H1/H2 contract boundary.
3. **(Low)** The conversational validator path skips the tenant check that C2's single-shot path
   enforces (`suppliedContext.org !== principal.organizationId ||
   suppliedContext.branch !== principal.branchId` — `validator.ts:364-369` vs. the conversational
   path at `validator.ts:275-314`). §4.3.5 does not name this check for conversational capabilities
   and containment is arguably elsewhere (per-leg authn/admission, client-side RLS on resolution),
   so this is likely intended — but the divergence from C2's frozen behaviour is undocumented in
   both the spec and the contracts.
4. **(Low)** The composer still resolves — and therefore requires — the
   `contextRenderingTemplateRef` artifact in conversational mode but never uses it
   (`composer.ts:230-236` vs. the conversational branch at `composer.ts:249-251`, which renders
   from `permittedKeySet` instead). A conversational manifest whose prompt binding omits or
   mis-pins the template fails with `internal_error` for no functional reason; dead coupling to a
   D1 single-shot concept.
5. **(Low, documentation)** §4.3.6's "offer" of the context-request schema as a second output
   shape is realized only as prose in the derived format instruction
   (`composer.ts:179-186`); `formatDirective` remains `{ mode: "prose", outputSchemaRef: null }`,
   so the schema drives the instruction and the response validator but not any provider-side
   structured-output configuration. This is a reasonable reading of "alongside prose" (structured
   modes cannot express a choice of two shapes), but §4.3.6's "the output schema is the single
   source of truth for … the provider's structured-output/JSON-mode configuration" is silently
   inapplicable to the second shape. Worth one clarifying sentence in the architecture or contract.

## 5. Missing or Weak Tests

Required case list is from delivery plan §3.11.7 row H2 and §3.10.

1. **(High)** R-10 delimiter neutralization is untested. No test places delimiter-like content
   (e.g. `"</key>"`, a forged `<key name="…">` block, or `\u003c` sequences) inside a
   `context_resolved` value or context payload and asserts it cannot close its own block or open
   another. This is the exact mechanism §4.3.6 names ("any delimiter-like text occurring inside a
   value is neutralized") and `neutralizeJson` (`composer.ts:37-39`) implements. The existing R-10
   test (`conversational-composer.test.ts:352-380`) only checks that instruction-like text stays
   out of `system` parts — a weaker property.
2. **(High)** `oversized_transcript_request_too_large` is a self-spy
   (`transcript-validation.test.ts:503-522`): it spies on `runCostPreflight`, then calls it
   directly and asserts the spy observed its own call. It proves the estimator rejects a large
   serialized input (already C2's test) but does not prove the transcript is included in the
   serialized input by any caller, nor that "no egress occurs" — and cannot, because no pipeline
   wiring exists in `src/`. The same weakness applies to
   `per_turn_cost_ceiling_uses_existing_preflight_no_new_mechanism` and
   `no_per_request_server_state_from_h2` (`transcript-validation.test.ts:525-578`), which assert
   over export-name regexes and would pass regardless of behaviour.
3. **(Medium)** Tail-only context-round branch untested: no case where `context_requested` turns
   appear *not* at the transcript tail (e.g. two mid-transcript rounds with
   `maxContextRoundsPerTurn: 1`) and the request passes. `countTailContextRounds`
   (`validator.ts:216-225`) exists precisely for this distinction; only the breach direction is
   covered.
4. **(Medium)** The allowlist drop on the *ordinary* supplied context payload is untested — every
   allowlist test uses keys inside a `context_resolved` turn
   (`transcript-validation.test.ts:472-500`). FR-011 and §4.3.5 cover both paths
   (`filterToPermittedKeys(suppliedContext, …)` at `validator.ts:302` is exercised only indirectly
   by happy-path tests where all keys are permitted).
5. **(Medium)** `key_outside_permitted_set_dropped` omits the named precondition "even when
   requested by the model": the test transcript contains no `context_requested` turn naming the
   unpermitted key (`transcript-validation.test.ts:474-485`). It also asserts the validator's
   returned transcript rather than the composer input, whereas the spec (SC-006) requires a spy
   proving absence from composer input. Functionally close, formally short of the named case.
6. **(Medium)** No composer test renders a `context_requested` turn. Both the golden fixture and
   the role-tag test use only `user`/`model`/`context_resolved`
   (`conversational-composer.test.ts:118-137,313-350`), leaving one row of the frozen role-tag
   table (`contracts/conversational-composition.md` §2: `context_requested` → `assistant` with the
   structured `requests` payload) without coverage.
7. **(Low)** Named boundaries not probed: transcript length exactly equal to `maxHistoryTurns`
   (must pass — `>` at `validator.ts:292`); tail rounds exactly equal to `maxContextRoundsPerTurn`
   (must pass — `validator.ts:297`); `turn_ordinal` strictly *greater* than the leg's own (only
   equality is tested, `transcript-validation.test.ts:270-279`); empty transcript (first leg);
   missing `transcript` field; shape-before-budgets with the rounds budget (only the history
   variant is tested, `transcript-validation.test.ts:360-384`).
8. **(Low)** Response-validator branch gaps: prose beginning with `[`/`{` (false-rejection
   branch, `phases.ts:127-133`), empty-array `[]` context request, and truncated conversational
   output are all untested. `trimmed_transcript_accepted_bounded_by_admission`
   (`transcript-validation.test.ts:542-565`) asserts acceptance only; the "bounded by admission"
   half of its name is untestable at this layer and overpromises.

## 6. Recommended Improvements

1. **(High)** Add the missing R-10 golden test: a `context_resolved` value containing `</key>` and
   a forged `<key>` open tag must appear in the composed `data` part escaped (`\u003c/`) so the
   block structure is intact; extend the same assertion to ordinary filtered context.
2. **(Medium)** Reconcile the user-turn rendering with the contract: either render transcript
   `user`/`model` text through a delimited/escaped form (per `conversational-composition.md` §2–3),
   or amend the contract and §4.3.6 to state explicitly that role-tag binding is the containment
   for user turns and that delimited-typed rendering applies to `data` parts only. The current
   state implements a third, undocumented option.
3. **(Medium)** Validate `context_requested.requests` elements with H1's `validateContextRequest`
   inside `parseTranscriptTurn`, rejecting non-conforming elements as `context_invalid`
   (§6.7.1's "the platform-owned `{key, arguments}` list"), instead of trusting `Array.isArray`.
4. **(Medium)** Apply the published-shape (`validatePayload`) and size checks to permitted
   conversational context values — at minimum to `context_resolved` payloads, which §6.7.1
   requires to be "shaped exactly as an ordinary context payload" — or record an explicit,
   justified waiver in `contracts/transcript-validation-budgets.md`.
5. **(Medium)** Resolve the `transcriptSizeLimit` discrepancy: enforce it in the conversational
   validator (byte check over the serialized transcript) or remove it from the H1 manifest fields
   and correct the H2 spec's Consumes wording. As merged, it is dead configuration that suggests a
   bound exists where none does.
6. **(Low)** Fail closed on non-numeric budget fields (mirror `preflight.ts:54-61`), reject a
   missing `transcript` explicitly rather than `?? []`, and re-label the "neither" failure phase
   from `schema` to `transport_parse` in `phases.ts`.
7. **(Low)** Drop the unused `contextRenderingTemplateRef` resolution for conversational
   composition (`composer.ts:230-236`), and neutralize the `JSON.stringify(turn.requests)`
   assistant payload (`composer.ts:150`) with the same `\u003c` escaping for consistency.
8. **(Low)** When pipeline wiring lands (H3 or the request handler), replace the self-spy tests
   with stage-integration tests that assert the serialized pre-flight input includes the
   transcript, that `request_too_large` aborts before egress, and that
   `conversation_budget_exhausted` maps to the correct taxonomy wire response
   (`ai-platform/src/errors.ts:77-79`).
