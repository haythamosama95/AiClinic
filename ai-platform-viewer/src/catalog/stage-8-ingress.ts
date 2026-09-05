import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'

export const VISIT_SUMMARY_CAPABILITY = 'clinic.visit_summary'
export const VISIT_SUMMARY_VERSION = '1.0.0'
export const VISIT_SUMMARY_INTENT = "Summarize today's visit for the chart."
export const VISIT_SUMMARY_COMPLAINT = 'Patient reports headache for 3 days.'
export const VISIT_SUMMARY_VISIT_ID = '550e8400-e29b-41d4-a716-446655440000'
export const VISIT_SUMMARY_RECORDED_AT = '2026-07-31T12:00:00.000Z'

export function buildVisitSummaryChiefComplaint(): Record<string, string> {
  return {
    visit_id: VISIT_SUMMARY_VISIT_ID,
    complaint: VISIT_SUMMARY_COMPLAINT,
    recorded_at: VISIT_SUMMARY_RECORDED_AT,
  }
}

export function buildVisitSummaryContextJson(orgId: string, branchId: string): string {
  return JSON.stringify(
    {
      org: orgId,
      branch: branchId,
      'visit.chief_complaint@v1': buildVisitSummaryChiefComplaint(),
    },
    null,
    2,
  )
}

export const STAGE8_META: JourneyStageMeta = {
  id: 'stage-8',
  navLabel: 'Stage 8',
  navNote: 'Request ingress',
  eyebrow: 'Stage 8 · Request ingress',
  title: 'Checking in at the gate',
  lede:
    'POST /v1/requests submits an AI job. The adapter validates body size and required headers before the guard runs. Visit summary is single-shot — conversational fields are optional probes. context.org and context.branch must match the AAT org and branch claims. Each POST mints a fresh AAT first (JTI is one-time per admit).',
  accentClass: 'stage-accent--ingress',
  cardClass: 'operation-card--ingress',
  buttonClass: 'ingress-button',
}

const INGRESS_FAILURES: JourneyOperationDefinition['failures'] = [
  { status: 401, error: 'unauthenticated', trigger: 'Missing/invalid AAT or installation_suspended' },
  { status: 403, error: 'forbidden_capability', trigger: 'Enrolled but entitlement pending (ai_disabled)' },
  { status: 413, error: 'request_too_large', trigger: 'Content-Length or body > 1 MiB' },
  { status: 422, error: 'invalid_request', trigger: 'Missing/empty x-idempotency-key or x-capability-version' },
]

export const STAGE8_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'get-visit-chief-complaint',
    section: 'Context provider RPC',
    title: 'Get visit chief complaint',
    method: 'RPC',
    path: '/rest/v1/rpc/get_visit_chief_complaint',
    rpcName: 'get_visit_chief_complaint',
    auth: 'supabase-admin',
    bodyKind: 'json',
    summary:
      'Clinic-side context provider for visit.chief_complaint@v1. The desktop client resolves this before POST /v1/requests — the gateway never calls clinic Postgres.',
    successNote:
      '200 — rpc_result with data.visit_id; data.complaint and data.recorded_at when a note exists.',
    failures: [
      { status: 200, error: 'NOT_FOUND', trigger: 'Visit not in scope or does not exist' },
      { status: 200, error: 'FORBIDDEN', trigger: 'Staff lacks visit clinical read access' },
      { status: 401, error: 'unauthenticated', trigger: 'Missing or invalid Supabase session' },
    ],
    fields: [
      {
        name: 'p_visit_id',
        scope: 'body',
        hint: 'UUID of a visit in the caller branch — upsert visit_clinical_notes.complaint for a happy path',
        defaultValue: '',
        wide: true,
      },
    ],
  },
  {
    id: 'post-requests-headers',
    section: 'Required headers',
    title: 'POST /v1/requests (header probe)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'sse',
    summary:
      'Minimal body with all adapter-required headers. x-idempotency-key and x-capability-version must be non-empty after trim. x-trace-id is optional. Authorization is implicit from the clinic AAT in Secrets.',
    successNote:
      'Passes ingress when headers are valid. May return 401 unauthenticated, 403 forbidden_capability (pending entitle), or SSE accepted when entitled.',
    failures: INGRESS_FAILURES,
    fields: [
      {
        name: 'x-idempotency-key',
        scope: 'header',
        hint: 'Opaque retry ticket — leave blank to generate UUID on send',
        defaultValue: '',
        wide: true,
        required: false,
      },
      {
        name: 'x-capability-version',
        scope: 'header',
        hint: 'Semver matching discovery manifest version',
        defaultValue: VISIT_SUMMARY_VERSION,
      },
      {
        name: 'x-trace-id',
        scope: 'header',
        hint: 'Optional correlation id — server generates ULID when omitted',
        defaultValue: '',
        required: false,
      },
      {
        name: 'capability_id',
        scope: 'body',
        hint: 'Stable capability id from discovery',
        defaultValue: VISIT_SUMMARY_CAPABILITY,
      },
      {
        name: 'user_intent',
        scope: 'body',
        hint: 'Natural-language instruction — defaults to empty string',
        defaultValue: '',
        required: false,
      },
      {
        name: 'context',
        scope: 'body',
        hint: 'JSON object — tenant keys org/branch must match AAT',
        defaultValue: '{}',
        json: true,
        wide: true,
        required: false,
      },
    ],
  },
  {
    id: 'post-requests-body-fields',
    section: 'Body fields',
    title: 'POST /v1/requests (all body fields)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'sse',
    summary:
      'Demonstrates every ingress body field including optional conversational keys (ignored for single-shot visit summary). Aliases capability and intent are not shown — use canonical names.',
    successNote:
      'Ingress accepts the body shape. Conversational fields are validated only for conversational capabilities.',
    failures: INGRESS_FAILURES,
    fields: [
      {
        name: 'x-idempotency-key',
        scope: 'header',
        defaultValue: '',
        required: false,
        wide: true,
      },
      {
        name: 'x-capability-version',
        scope: 'header',
        defaultValue: VISIT_SUMMARY_VERSION,
      },
      {
        name: 'x-trace-id',
        scope: 'header',
        defaultValue: 'probe-ingress-body-fields',
        required: false,
      },
      {
        name: 'capability_id',
        scope: 'body',
        defaultValue: VISIT_SUMMARY_CAPABILITY,
      },
      {
        name: 'user_intent',
        scope: 'body',
        defaultValue: VISIT_SUMMARY_INTENT,
      },
      {
        name: 'context',
        scope: 'body',
        defaultValue: '{}',
        json: true,
        wide: true,
        required: false,
      },
      {
        name: 'conversation_id',
        scope: 'body',
        hint: 'Conversational only — omitted for visit summary',
        defaultValue: '',
        required: false,
      },
      {
        name: 'turn_ordinal',
        scope: 'body',
        hint: 'Conversational only — finite number',
        defaultValue: '',
        required: false,
      },
      {
        name: 'transcript',
        scope: 'body',
        hint: 'Conversational only — JSON array of turn objects',
        defaultValue: '[]',
        json: true,
        wide: true,
        required: false,
      },
    ],
  },
  {
    id: 'post-requests-visit-summary',
    section: 'Visit summary example',
    title: 'POST /v1/requests (visit summary §7)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'sse',
    summary:
      'Canonical visit summary ingress from doc §7. context must include org, branch, and visit.chief_complaint@v1 (max 4096 bytes). Sync clinic defaults to prefill org/branch from Supabase.',
    successNote:
      'Not 413/422 — ingress passed. Expect SSE accepted when entitled, or 403 forbidden_capability when pending.',
    failures: INGRESS_FAILURES,
    fields: [
      {
        name: 'x-idempotency-key',
        scope: 'header',
        defaultValue: '',
        required: false,
        wide: true,
      },
      {
        name: 'x-capability-version',
        scope: 'header',
        defaultValue: VISIT_SUMMARY_VERSION,
      },
      {
        name: 'x-trace-id',
        scope: 'header',
        defaultValue: 'probe-visit-trace',
        required: false,
      },
      {
        name: 'capability_id',
        scope: 'body',
        defaultValue: VISIT_SUMMARY_CAPABILITY,
      },
      {
        name: 'user_intent',
        scope: 'body',
        defaultValue: VISIT_SUMMARY_INTENT,
      },
      {
        name: 'context',
        scope: 'body',
        hint: 'org and branch must match AAT — synced from clinic Postgres',
        defaultValue: buildVisitSummaryContextJson('<org>', '<branch>'),
        json: true,
        wide: true,
        clinicKey: 'org_id',
      },
    ],
  },
]
