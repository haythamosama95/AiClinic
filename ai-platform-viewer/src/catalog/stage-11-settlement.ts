import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'

export const STAGE11_META: JourneyStageMeta = {
  id: 'stage-11',
  navLabel: 'Stage 11',
  navNote: 'Terminal settlement',
  eyebrow: 'Stage 11 · Terminal settlement',
  title: 'Closing the flight log',
  lede:
    'After a terminal SSE event, the platform credits the Quota DO, updates D1 ai_request, inserts ai_attempt and usage_event rows, and writes the R2 envelope. Clients poll GET /v1/requests/{request_reference}; operators inspect D1 and R2 with wrangler.',
  accentClass: 'stage-accent--settlement',
  cardClass: 'operation-card--settlement',
  buttonClass: 'settlement-button',
}

export const STAGE11_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'settle-get-terminal',
    section: 'D1 terminal row',
    title: 'GET /v1/requests/{request_reference} — terminal state',
    method: 'GET',
    path: '/v1/requests/{request_reference}',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'Client-visible terminal snapshot. After completed, returns authoritative result.finalContent. D1 columns (state, completed_at, routing_decision, payload_pointer) are not exposed — use wrangler for journal inspection.',
    successNote:
      '200 when Completed — result matches SSE completed frame. Compare with wrangler: SELECT state, completed_at, terminal_error_code, payload_pointer FROM ai_request WHERE request_reference = …',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Invalid AAT' },
      { status: 404, error: 'request_not_found', trigger: 'Unknown reference or wrong installation' },
    ],
    fields: [
      {
        name: 'request_reference',
        scope: 'path',
        defaultValue: '',
        hint: 'Copy from Stage 10 SSE accepted frame — leave empty until you have REF',
        wide: true,
        required: true,
      },
    ],
  },
  {
    id: 'settle-quota-credit-doc',
    section: 'Quota credit',
    title: 'Quota DO credit (document)',
    method: 'GET',
    path: '/v1/requests/{request_reference}',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'kind: credit is internal to the Quota DO — not a public HTTP API. Observe credit indirectly: inFlight released, idempotency key leaves "admitted", retry with the same x-idempotency-key replays the terminal outcome. Healthy path: one credit after admit (partial=false on success).',
    successNote:
      'Document only. Replay the same idempotency key within 2h — expect idempotent SSE replay, not a second charge. No wrangler dump of DO storage exists.',
    failures: [],
    fields: [
      {
        name: 'request_reference',
        scope: 'path',
        defaultValue: '',
        hint: 'Optional — poll terminal if you have REF from Stage 10',
        wide: true,
        required: false,
      },
    ],
  },
  {
    id: 'settle-r2-envelope-doc',
    section: 'R2 envelope inspection',
    title: 'R2 envelope via GET poll + wrangler',
    method: 'GET',
    path: '/v1/requests/{request_reference}',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'R2 key request/{request_id}/envelope holds context, prompt (CanonicalRequest), attempts[], and result. GET poll returns client-safe result only. Operators: read payload_pointer from D1, then wrangler r2 object get ai-platform-development/request/<request_id>/envelope.',
    successNote:
      'GET 200 includes terminal result for Completed. Full envelope: cd ai-platform && npx wrangler r2 object get ai-platform-development/$(d1 payload_pointer) --local --env development',
    failures: [
      { status: 404, error: 'request_not_found', trigger: 'Stream not yet terminal' },
    ],
    fields: [
      {
        name: 'request_reference',
        scope: 'path',
        defaultValue: '',
        hint: 'REF from Stage 10 — D1 request_id (RID) is only in wrangler, not SSE',
        wide: true,
        required: false,
      },
    ],
  },
]
