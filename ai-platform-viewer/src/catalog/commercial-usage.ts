import type { JourneyOperationDefinition } from '@/catalog/journey-types'

export const COMMERCIAL_USAGE_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'usage-summary',
    section: 'Credit gauge',
    title: 'GET /v1/usage',
    method: 'GET',
    path: '/v1/usage',
    auth: 'aat',
    bodyKind: 'none',
    fields: [],
    summary:
      'Installation-authenticated usage summary. Returns current_period.credits_used and current_period.credit_budget for the credits-only gauge. Does not call GET /control/installations/:id/quota.',
    successNote:
      '200 — { current_period: { credits_used, credit_budget }, prior_periods: [...] }.',
    failures: [
      { status: 401, error: 'unauthenticated', trigger: 'Missing or invalid clinic AAT' },
      { status: 403, error: 'installation_suspended', trigger: 'Installation suspended' },
    ],
  },
]
