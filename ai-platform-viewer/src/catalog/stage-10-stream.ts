import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import {
  VISIT_SUMMARY_CAPABILITY,
  VISIT_SUMMARY_INTENT,
  VISIT_SUMMARY_VERSION,
  buildVisitSummaryContextJson,
} from '@/catalog/stage-8-ingress'
import { visitSummaryPostFields } from '@/catalog/visit-summary-probe-fields'

const VISIT_CONTEXT_PLACEHOLDER = buildVisitSummaryContextJson(
  '<match AAT org claim>',
  '<match AAT branch claim>',
)

export const STAGE10_META: JourneyStageMeta = {
  id: 'stage-10',
  navLabel: 'Stage 10',
  navNote: 'Accept, route, invoke, stream',
  eyebrow: 'Stage 10 · Accept, route, invoke, stream',
  title: 'From accepted to SSE terminal',
  lede:
    'After the guard passes, POST /v1/requests opens an SSE stream. accepted is the first frame; routing and provider invocation follow on the fresh path.',
  accentClass: 'stage-accent--stream',
  cardClass: 'operation-card--stream',
  buttonClass: 'stream-button',
}

export const STAGE10_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'stream-sse-happy',
    section: 'SSE accept',
    title: 'POST /v1/requests — visit summary happy path (SSE)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'sse',
    summary:
      'Full fresh path: accepted → text_delta → completed on the fake provider when routing policy version 91 is active. Save request_reference from the accepted frame for Stage 11.',
    successNote:
      '200 text/event-stream. Payload rows are per SSE event (body.accepted, body.completed, …). request_reference is only in body.accepted — also pinned above the payload when present. Terminal completed uses placeholder text on idempotent replay (same x-idempotency-key).',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Guard stage 2 failure' },
      { status: 200, error: 'failed (SSE)', trigger: 'Missing routing policy after accepted' },
    ],
    fields: visitSummaryPostFields({
      body: {
        capability_id: VISIT_SUMMARY_CAPABILITY,
        user_intent: VISIT_SUMMARY_INTENT,
        context: VISIT_CONTEXT_PLACEHOLDER,
      },
      headers: {
        'x-idempotency-key': 'idem-happy-1',
        'x-capability-version': VISIT_SUMMARY_VERSION,
        'x-trace-id': 'trace-happy-1',
      },
    }),
  },
  {
    id: 'stream-get-poll',
    section: 'GET poll',
    title: 'GET /v1/requests/{request_reference}',
    method: 'GET',
    path: '/v1/requests/{request_reference}',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'Poll terminal state after the SSE stream completes. Paste request_reference from the pinned field or body.accepted on the POST response (XXXX-XXXX). GET does not echo the ticket back.',
    successNote:
      '200 with terminal payload when the journal row is Completed. 404 while still in-flight or unknown reference.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Invalid or missing AAT' },
      { status: 404, error: 'request_not_found', trigger: 'Unknown request_reference' },
    ],
    fields: [
      {
        name: 'request_reference',
        scope: 'path',
        defaultValue: '',
        hint: 'Copy from SSE accepted frame (e.g. W6GP-H3BT)',
        wide: true,
        required: true,
      },
    ],
  },
]
