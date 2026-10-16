# Phase 15 catalog-vs-code conflicts

## S09-065

- **Catalog claim:** Second POST with the same AAT/jti and a new idempotency key returns HTTP 401 `unauthenticated`; the first request's journal row is **untouched**; still one `ai_request` row (`docs/testing/catalog/stage-09-the-guard.md` S09-065).
- **Code behavior:** JTI replay rejects at admission (`quota-do` `outcome: "replay"` → `unauthenticated`) and does not INSERT a second `ai_request`. The first row is not frozen: after `accepted`, Stage 11 settlement of request 1 continues (`persistPostResponseDetail` writes `payload_pointer = request/<id>/envelope`; `persistRoutingDecision` / `journalTransition` may update `routing_decision`, `state`, `updated_at`, `completed_at`, `terminal_error_code`). A snapshot taken at `accepted` therefore can differ from a later read of the same row without a second journal write.
- **File:line:** `ai-platform/src/journal/index.ts` (`persistPostResponseDetail` payload_pointer UPDATE; `persistRoutingDecision`; `journalTransition`); `ai-platform/src/quota-do/index.ts` jti replay; `ai-platform/src/admission/index.ts` replay → `unauthenticated`; `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts` S09-065.
