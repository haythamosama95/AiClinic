import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'

export const STAGE6_META: JourneyStageMeta = {
  id: 'stage-6',
  navLabel: 'Stage 6',
  navNote: 'Minting an AAT',
  eyebrow: 'Stage 6 · Minting an AAT',
  title: 'Boarding pass from clinic Postgres',
  lede:
    'Staff with ai.* RBAC permissions call issue_ai_token on clinic Supabase. The RPC signs a short-lived EdDSA JWS with the clinic private key — the platform never sees the private key. Client-supplied p_scopes are ignored at mint; scopes come from RBAC. Use the compact JWS as Bearer on discovery and ingress.',
  accentClass: 'stage-accent--mint',
  cardClass: 'operation-card--mint',
  buttonClass: 'mint-button',
}

export const STAGE6_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'issue-ai-token',
    section: 'Clinic AAT issuer',
    title: 'Issue AI token',
    method: 'RPC',
    path: '/rest/v1/rpc/issue_ai_token',
    rpcName: 'issue_ai_token',
    auth: 'supabase-admin',
    bodyKind: 'json',
    summary:
      'Mints a compact JWS (AAT) for the authenticated staff session. Returns plain text — not rpc_result. p_scopes is optional and ignored by the issuer; RBAC ai.* permissions become the scopes claim.',
    successNote:
      '200 — compact JWS string (header.payload.signature). Writes ai_internal.ai_token_issuance row per jti.',
    failures: [
      {
        status: 200,
        error: 'INSTALLATION_NOT_ENROLLED',
        trigger: 'No active installation_keys row — run Stage 2 enroll first',
      },
      {
        status: 200,
        error: 'AI_ACCESS_DENIED',
        trigger: 'Staff lacks ai.* RBAC permission',
      },
      {
        status: 200,
        error: 'BRANCH_NOT_FOUND',
        trigger: 'No primary active branch assignment',
      },
      { status: 200, error: 'RATE_LIMITED', trigger: 'Issuance rate limit exceeded' },
      { status: 401, error: 'unauthenticated', trigger: 'Missing or invalid Supabase session (anon has no GRANT)' },
    ],
    fields: [
      {
        name: 'p_scopes',
        scope: 'body',
        hint: 'Optional text[] — ignored by issuer; leave empty for all RBAC ai.* scopes',
        defaultValue: '["ai.visit_summary"]',
        json: true,
        required: false,
      },
    ],
  },
]
