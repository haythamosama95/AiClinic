import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'

export const STAGE12_META: JourneyStageMeta = {
  id: 'stage-12',
  navLabel: 'Stage 12',
  navNote: 'Lookup and support',
  eyebrow: 'Stage 12 · Lookup and support',
  title: 'Poll results and operator diagnostics',
  lede:
    'After SSE completed (or a missed stream), clinics poll GET /v1/requests/{request_reference} with the same AAT that admitted the job — scoped to the token installation_id. Operators use POST /control/support/lookup?reference= for a cross-installation diagnostic dump (request trace, attempts, R2 envelope). Staff record acceptance in clinic Postgres via record_ai_acceptance — not on the gateway.',
  accentClass: 'stage-accent--lookup',
  cardClass: 'operation-card--lookup',
  buttonClass: 'lookup-button',
}

export const STAGE12_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'get-request-by-reference',
    section: 'Client lookup',
    title: 'Poll request by reference',
    method: 'GET',
    path: '/v1/requests/{request_reference}',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'authenticateGetRequest verifies the AAT (same enrolled-key verifier as POST /v1/requests). Returns journal state and, when Completed with payload_pointer, the CanonicalResult from R2. Wrong installation returns empty 404 — no cross-tenant leak.',
    successNote:
      '200 — { state, result? }. Completed + pointer → full CanonicalResult (finalContent, usage, providerModel, finishReason, providerRequestId, timing). Completed without envelope → { state: "Completed" } only. In-flight → { state, pending: true }.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Missing or invalid AAT' },
      { status: 403, error: 'installation_suspended', trigger: 'Installation suspended' },
      { status: 404, error: '(empty body)', trigger: 'Unknown reference, wrong installation, or non-pollable state' },
    ],
    fields: [
      {
        name: 'request_reference',
        scope: 'path',
        hint: 'Crockford XXXX-XXXX ticket from SSE accepted event',
        required: true,
        wide: true,
      },
    ],
  },
  {
    id: 'support-lookup',
    section: 'Support lookup',
    title: 'Operator diagnostic dump',
    method: 'POST',
    path: '/control/support/lookup',
    auth: 'operator',
    bodyKind: 'none',
    summary:
      'requireOperator + supportLookup. Cross-installation read by request_reference — returns D1 request trace, provider attempts[], and R2 envelope when still within retention. Does not write control_audit.',
    successNote:
      '200 — { request, attempts[], envelope }. request has requestId, requestReference, installationId, actorId, branchId, capabilityId, capabilityVersion, promptArtifactHash, state, timestamps, terminalErrorCode, traceId, payloadPointer.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing or wrong OPERATOR_BEARER_TOKEN' },
      { status: 400, error: 'missing_reference', trigger: 'Query param absent or blank' },
      { status: 400, error: 'invalid_reference', trigger: 'Not valid XXXX-XXXX Crockford' },
      { status: 404, error: 'not_found', trigger: 'No journal row for reference' },
      { status: 500, error: 'missing_r2_binding', trigger: 'Worker misconfiguration' },
    ],
    fields: [
      {
        name: 'reference',
        scope: 'query',
        hint: 'Same XXXX-XXXX ticket — query string, not JSON body',
        required: true,
        wide: true,
      },
    ],
  },
  {
    id: 'record-ai-acceptance',
    section: 'Acceptance recording',
    title: 'Record AI acceptance (clinic RPC)',
    method: 'RPC',
    path: '/rest/v1/rpc/record_ai_acceptance',
    rpcName: 'record_ai_acceptance',
    auth: 'supabase-admin',
    bodyKind: 'json',
    summary:
      'Clinic-side acceptance after terminal SSE completed. SECURITY DEFINER wrapper delegates to auth_internal.record_ai_acceptance. Gateway and D1 are not involved. Duplicate (table, record, reference) rejected before domain write.',
    successNote:
      'rpc_result success=true — data includes acceptance_id, table_name, record_id, audit_log_id plus delegated domain fields. audit_log action=ai.acceptance_record.',
    failures: [
      { status: 200, error: 'INVALID_INPUT', trigger: 'Malformed reference, unregistered target, or duplicate acceptance' },
      { status: 200, error: 'FORBIDDEN', trigger: 'Missing JWT organization' },
      { status: 200, error: 'INTERNAL_ERROR', trigger: 'Registry misconfiguration' },
      { status: 200, error: '(delegated)', trigger: 'Domain RPC failure — error_code passed through unchanged' },
    ],
    fields: [
      {
        name: 'p_request_reference',
        scope: 'body',
        hint: 'Terminal SSE / journal ticket — Crockford XXXX-XXXX',
        required: true,
        wide: true,
      },
      {
        name: 'p_target_key',
        scope: 'body',
        defaultValue: 'visit_clinical_notes',
        hint: 'Allow-listed key from ai_internal.acceptance_targets',
        required: true,
      },
      {
        name: 'p_target_args',
        scope: 'body',
        json: true,
        defaultValue: '{"p_visit_id": "", "p_complaint": "Accepted AI summary text"}',
        hint: 'Named arguments for registered domain RPC (save_visit_documentation)',
        required: true,
        wide: true,
      },
    ],
  },
]
