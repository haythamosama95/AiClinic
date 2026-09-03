import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import {
  VISIT_SUMMARY_CAPABILITY,
  VISIT_SUMMARY_INTENT,
  VISIT_SUMMARY_VERSION,
} from '@/catalog/stage-8-ingress'
import {
  visitSummaryPostFields,
  VISIT_SUMMARY_CONTEXT_JSON,
} from '@/catalog/visit-summary-probe-fields'

const POST_FAILURES = [
  { status: 401, error: 'unauthenticated', trigger: 'Stage 2 identity failure' },
  { status: 403, error: 'installation_suspended', trigger: 'installation.status = suspended' },
  { status: 403, error: 'forbidden_capability', trigger: 'Stage 3 entitlement or stage 5 access' },
  { status: 404, error: 'capability_unknown', trigger: 'Unknown capability_id@version' },
  { status: 404, error: 'capability_retired', trigger: 'Manifest lifecycle retired' },
  { status: 409, error: 'conversation_budget_exhausted', trigger: 'Conversational mode only' },
  { status: 413, error: 'request_too_large', trigger: 'Stage 1 body or stage 7 token estimate' },
  { status: 422, error: 'context_required', trigger: 'Stage 6 missing required context keys' },
  { status: 422, error: 'context_invalid', trigger: 'Stage 6 tenant bind or shape violation' },
  { status: 429, error: 'quota_exhausted', trigger: 'Stage 8 Quota DO admission refusal' },
  { status: 429, error: 'rate_limited', trigger: 'Stage 4 rate limit binding' },
  { status: 503, error: 'capability_disabled', trigger: 'Stage 3 or 5 kill switch' },
  { status: 500, error: 'internal_error', trigger: 'Non-object JSON or compose failure' },
]

export const STAGE9_META: JourneyStageMeta = {
  id: 'stage-9',
  navLabel: 'Stage 9',
  navNote: 'The guard (stages 1–10)',
  eyebrow: 'Stage 9 · The guard',
  title: 'Ten checkpoints before SSE opens',
  lede:
    'Every POST /v1/requests runs ten sequential guard checks before the SSE stream opens. Failures return HTTP JSON — never accepted. Use these probes to target each stage: edit Authorization, capability_id, context, and headers to force the expected taxonomy code.',
  accentClass: 'stage-accent--guard',
  cardClass: 'operation-card--guard',
  buttonClass: 'guard-button',
}

export const STAGE9_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'guard-s1-oversized-doc',
    section: 'Stage 1 — Ingress size + JSON',
    title: 'Oversized body (> 1 MiB) — document only',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Stage 1 rejects bodies larger than 1 MiB UTF-8 with 413 request_too_large. The browser viewer cannot practically send a multi-megabyte JSON body — use curl with a generated payload per data-journey §14.3.2.',
    successNote:
      'Document only. Example: python3 -c "print(\\"x\\"*1048577)" | curl -X POST … -d @- with valid headers and a minimal JSON wrapper.',
    failures: [{ status: 413, error: 'request_too_large', trigger: 'bodyText exceeds 1 MiB UTF-8' }],
    fields: visitSummaryPostFields(),
  },
  {
    id: 'guard-s1-normal',
    section: 'Stage 1 — Ingress size + JSON',
    title: 'Normal JSON object (passes stage 1)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Valid plain-object JSON within size limits. Ingress extracts capability_id, user_intent, context, and optional conversational fields. Later guard stages may still reject.',
    successNote:
      'Passes stage 1. With a minted clinician AAT, entitled installation, and matching context.org/branch, the request may reach SSE accepted (Stage 10 boundary).',
    failures: POST_FAILURES,
    fields: visitSummaryPostFields(),
  },
  {
    id: 'guard-s2-missing-auth',
    section: 'Stage 2 — Identity (AAT)',
    title: 'Missing Authorization header',
    method: 'POST',
    path: '/v1/requests',
    auth: 'none',
    bodyKind: 'json',
    summary:
      'Adapter does not reject missing Authorization at ingress — stage 2 identity fails with unauthenticated when the wire token is absent.',
    successNote: '401 unauthenticated — no SSE body.',
    failures: [{ status: 401, error: 'unauthenticated', trigger: 'No Bearer token on wire' }],
    fields: visitSummaryPostFields(),
  },
  {
    id: 'guard-s2-malformed-jwt',
    section: 'Stage 2 — Identity (AAT)',
    title: 'Malformed wire token (not 3 JWS segments)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'none',
    bodyKind: 'json',
    summary:
      'Stage 2 requires a three-segment JWS. Edit Authorization to any non-JWS string.',
    successNote: '401 unauthenticated.',
    failures: [{ status: 401, error: 'unauthenticated', trigger: 'Token is not a valid JWS' }],
    fields: visitSummaryPostFields({
      authorization: 'Bearer not-a-valid-jwt',
    }),
  },
  {
    id: 'guard-s2-wrong-bearer-kind',
    section: 'Stage 2 — Identity (AAT)',
    title: 'Operator bearer instead of clinic AAT',
    method: 'POST',
    path: '/v1/requests',
    auth: 'none',
    bodyKind: 'json',
    summary:
      'Control-plane operator tokens are not valid clinic AATs. Paste OPERATOR_BEARER_TOKEN into Authorization (or load from Secrets and copy).',
    successNote: '401 unauthenticated — operator JWT is not an installation AAT.',
    failures: [{ status: 401, error: 'unauthenticated', trigger: 'Wire token fails Ed25519 / claim checks' }],
    fields: visitSummaryPostFields({
      authorization: 'Bearer <paste OPERATOR_BEARER_TOKEN>',
    }),
  },
  {
    id: 'guard-s2-empty-cap-version',
    section: 'Stage 2 — Identity (AAT)',
    title: 'Empty x-capability-version header',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Ingress requires x-capability-version. Clear the header field to probe missing capability version before identity resolves the manifest.',
    successNote: '400 or 401 depending on adapter validation order — never SSE accepted.',
    failures: [
      { status: 400, error: 'invalid_request', trigger: 'Missing x-capability-version' },
      { status: 401, error: 'unauthenticated', trigger: 'If headers pass, bad token still fails stage 2' },
    ],
    fields: visitSummaryPostFields({
      headers: { 'x-capability-version': '' },
    }),
  },
  {
    id: 'guard-s3-wrong-capability',
    section: 'Stage 3 — Entitlement',
    title: 'Capability not in allowed_capabilities',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Stage 3 checks entitlement.allowed_capabilities and per-capability grants. Edit capability_id to an id that is not granted.',
    successNote: '403 forbidden_capability after identity passes.',
    failures: [{ status: 403, error: 'forbidden_capability', trigger: 'capability_id missing from entitlement grant' }],
    fields: visitSummaryPostFields({
      body: { capability_id: 'clinic.does_not_exist' },
    }),
  },
  {
    id: 'guard-s3-wrong-grant-version',
    section: 'Stage 3 — Entitlement',
    title: 'Grant version mismatch',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Entitlement grant version must match x-capability-version. Set header to 9.9.9 while body keeps clinic.visit_summary.',
    successNote: '403 forbidden_capability (grant version mismatch) or 404 capability_unknown.',
    failures: [
      { status: 403, error: 'forbidden_capability', trigger: 'Grant version does not match header' },
      { status: 404, error: 'capability_unknown', trigger: 'No manifest at capability@9.9.9' },
    ],
    fields: visitSummaryPostFields({
      headers: { 'x-capability-version': '9.9.9' },
    }),
  },
  {
    id: 'guard-s3-kill-switch-doc',
    section: 'Stage 3 — Entitlement',
    title: 'D1 kill switch — operator setup (document)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Insert kill_switch rows for global, capability:clinic.visit_summary, installation:<id>, or provider:fake (stage 3 hardcodes providerId fake). Expect 503 capability_disabled. Remove rows after probing. See data-journey §14.3.5.',
    successNote:
      'Document only unless kill_switch rows exist. Send to confirm 503 capability_disabled when a switch is active.',
    failures: [{ status: 503, error: 'capability_disabled', trigger: 'Active D1 kill_switch row' }],
    fields: visitSummaryPostFields(),
  },
  {
    id: 'guard-s4-rate-limit-doc',
    section: 'Stage 4 — Rate limit',
    title: 'Burst rate limit (document + probe)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Three Cloudflare Rate Limit dimensions: installation, installation+actor, installation+capability. Burst-send this probe or use a tight loop in curl. Expect 429 rate_limited with retry_after (binding hint or 60s default).',
    successNote:
      '429 rate_limited with retry_after when a binding rejects. Post-accept provider 429s are not this code.',
    failures: [{ status: 429, error: 'rate_limited', trigger: 'Rate limit binding success=false' }],
    fields: visitSummaryPostFields({
      headers: { 'x-idempotency-key': 'rate-limit-probe-<use-unique-per-attempt>' },
    }),
  },
  {
    id: 'guard-s5-unknown-capability',
    section: 'Stage 5 — Capability resolve',
    title: 'Unknown capability_id@version',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Registry lookup uses capability_id@x-capability-version. Use a nonsense capability id after entitlement would allow a different id.',
    successNote: '404 capability_unknown when manifest registry has no match.',
    failures: [{ status: 404, error: 'capability_unknown', trigger: 'No manifest for id@version' }],
    fields: visitSummaryPostFields({
      body: { capability_id: 'clinic.unknown_capability' },
    }),
  },
  {
    id: 'guard-s5-forbidden-scope',
    section: 'Stage 5 — Capability resolve',
    title: 'Missing requiredCapabilityScope (doctor AAT)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Visit summary requires scope ai.visit_summary and role clinician|nurse. Mint a stock doctor token (issue_ai_token as doctor) and paste it into Authorization to override the Secrets AAT.',
    successNote: '403 forbidden_capability — scope or role check before SSE.',
    failures: [{ status: 403, error: 'forbidden_capability', trigger: 'requiredCapabilityScope or allowedStaffRoles' }],
    fields: visitSummaryPostFields({
      authorization: 'Bearer <paste DOCTOR_AAT from issue_ai_token()>',
    }),
  },
  {
    id: 'guard-s6-missing-context-key',
    section: 'Stage 6 — Context validate',
    title: 'Missing required context key',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Visit summary requires visit.chief_complaint@v1. Send context with only org/branch.',
    successNote: '422 context_required (missing_keys not exposed on live HTTP).',
    failures: [{ status: 422, error: 'context_required', trigger: 'Required manifest context key absent' }],
    fields: visitSummaryPostFields({
      body: {
        context: `{
  "org": "<match AAT org claim>",
  "branch": "<match AAT branch claim>"
}`,
      },
    }),
  },
  {
    id: 'guard-s6-tenant-mismatch',
    section: 'Stage 6 — Context validate',
    title: 'context.org / context.branch mismatch',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Tenant binding: context.org and context.branch must equal principal.organizationId and principal.branchId from the AAT.',
    successNote: '422 context_invalid.',
    failures: [{ status: 422, error: 'context_invalid', trigger: 'org or branch does not match AAT' }],
    fields: visitSummaryPostFields({
      body: {
        context: `{
  "org": "00000000-0000-4000-8000-000000000001",
  "branch": "00000000-0000-4000-8000-000000000002",
  "visit.chief_complaint@v1": "Patient reports headache for 3 days."
}`,
      },
    }),
  },
  {
    id: 'guard-s6-invalid-shape',
    section: 'Stage 6 — Context validate',
    title: 'Invalid context shape (string instead of object)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Manifest Context requirements enforce shape and maxSize. visit.chief_complaint@v1 must be an object with visit_id and complaint.',
    successNote: '422 context_invalid.',
    failures: [{ status: 422, error: 'context_invalid', trigger: 'Shape or maxSize violation' }],
    fields: visitSummaryPostFields({
      body: {
        context: `{
  "org": "<match AAT org claim>",
  "branch": "<match AAT branch claim>",
  "visit.chief_complaint@v1": "Patient reports headache for 3 days."
}`,
      },
    }),
  },
  {
    id: 'guard-s7-huge-intent',
    section: 'Stage 7 — Cost pre-flight',
    title: 'Oversized user_intent (token estimate)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Stage 7 estimates input tokens from context + user_intent + prompt scaffold. Exceeding maxInputTokens or perRequestTokenCeiling yields 413 request_too_large (token-only — no price table).',
    successNote: '413 request_too_large when estimate exceeds manifest economics ceilings.',
    failures: [{ status: 413, error: 'request_too_large', trigger: 'Token estimate over manifest ceiling' }],
    fields: visitSummaryPostFields({
      body: {
        user_intent: 'x'.repeat(500000),
        context: VISIT_SUMMARY_CONTEXT_JSON,
      },
    }),
  },
  {
    id: 'guard-s8-quota-exhausted',
    section: 'Stage 8 — Admission (Quota DO)',
    title: 'Quota exhausted (operator setup)',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'json',
    summary:
      'Set entitlement request_quota to 0 or exhaust tokens via wrangler/D1, then send. Stage 8 Quota DO returns quota_exhausted. Restore quotas after probing. JTI replay of a prior admitted jti yields 401 unauthenticated.',
    successNote:
      '429 quota_exhausted when DO refuses admission. Use a fresh x-idempotency-key per attempt.',
    failures: [
      { status: 429, error: 'quota_exhausted', trigger: 'Quota DO admission refusal' },
      { status: 401, error: 'unauthenticated', trigger: 'JTI replay after prior admit' },
    ],
    fields: visitSummaryPostFields({
      headers: { 'x-idempotency-key': 'quota-probe-<unique>' },
    }),
  },
  {
    id: 'guard-s9-10-happy-path',
    section: 'Stages 9–10 — Journal + prompt compose',
    title: 'Happy path through prompt compose',
    method: 'POST',
    path: '/v1/requests',
    auth: 'aat',
    bodyKind: 'sse',
    summary:
      'When stages 1–8 pass, stage 9 INSERTs ai_request (state=Accepted) and stage 10 composes CanonicalRequest. SSE accepted is the Stage 10 boundary — routing has not run yet. Requires fake routing policy (Stage 10 preload) for a full stream.',
    successNote:
      '200 text/event-stream with event: accepted first. D1 ai_request row with routing_decision NULL until Stage 10 routing.',
    failures: POST_FAILURES,
    fields: visitSummaryPostFields({
      body: {
        capability_id: VISIT_SUMMARY_CAPABILITY,
        user_intent: VISIT_SUMMARY_INTENT,
        context: VISIT_SUMMARY_CONTEXT_JSON,
      },
      headers: {
        'x-idempotency-key': '',
        'x-capability-version': VISIT_SUMMARY_VERSION,
        'x-trace-id': 'trace-guard-happy-1',
      },
    }),
  },
]
