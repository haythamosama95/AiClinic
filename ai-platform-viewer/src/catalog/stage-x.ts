import type { JourneyOperationDefinition } from '@/catalog/journey-types'

function cronFields(expression: string): JourneyOperationDefinition['fields'] {
  const encoded = expression.replace(/ /g, '+')
  return [
    {
      name: 'cron',
      scope: 'query',
      defaultValue: encoded,
      hint: 'Cron expression — use + for spaces',
      wide: true,
    },
    {
      name: 'format',
      scope: 'query',
      defaultValue: 'json',
      hint: 'Response format — json returns { outcome: "ok" }',
    },
  ]
}

export const STAGE_X_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'cron-retention',
    section: 'Scheduled crons',
    title: 'Retention purge — 0 3 * * *',
    method: 'GET',
    path: '/cdn-cgi/handler/scheduled',
    auth: 'none',
    bodyKind: 'none',
    fields: cronFields('0 3 * * *'),
    summary:
      'SX retention cron — runs retention purge on matching scheduled tick. Requires wrangler dev --test-scheduled.',
    successNote: '200 — { "outcome": "ok" } when --test-scheduled is enabled.',
    failures: [
      {
        status: 404,
        error: '(not found)',
        trigger: 'Worker started without --test-scheduled',
      },
    ],
  },
  {
    id: 'cron-rollup',
    section: 'Scheduled crons',
    title: 'Rollup and reconciliation — 0 4 * * *',
    method: 'GET',
    path: '/cdn-cgi/handler/scheduled',
    auth: 'none',
    bodyKind: 'none',
    fields: cronFields('0 4 * * *'),
    summary:
      'SX rollup cron — runs rollup and reconciliation on matching scheduled tick.',
    successNote: '200 — { "outcome": "ok" } when --test-scheduled is enabled.',
    failures: [
      {
        status: 404,
        error: '(not found)',
        trigger: 'Worker started without --test-scheduled',
      },
    ],
  },
  {
    id: 'cron-period-close',
    section: 'Scheduled crons',
    title: 'G4 period close — 0 5 1 * *',
    method: 'GET',
    path: '/cdn-cgi/handler/scheduled',
    auth: 'none',
    bodyKind: 'none',
    fields: cronFields('0 5 1 * *'),
    summary:
      'G4 billing period close cron — issues invoices for the prior month. Not a /control POST.',
    successNote: '200 — { "outcome": "ok" } when --test-scheduled is enabled.',
    failures: [
      {
        status: 404,
        error: '(not found)',
        trigger: 'Worker started without --test-scheduled',
      },
    ],
  },
  {
    id: 'cron-unknown-fallthrough',
    section: 'Scheduled crons',
    title: 'Unknown cron fallthrough — 0 5 * * * (SX-003)',
    method: 'GET',
    path: '/cdn-cgi/handler/scheduled',
    auth: 'none',
    bodyKind: 'none',
    fields: cronFields('0 5 * * *'),
    summary:
      'SX-003 unknown-cron fallthrough — scheduled handler accepts the tick without retention, rollup, or period-close branch.',
    successNote: '200 — { "outcome": "ok" } when --test-scheduled is enabled.',
    failures: [
      {
        status: 404,
        error: '(not found)',
        trigger: 'Worker started without --test-scheduled',
      },
    ],
  },
  {
    id: 'failure-poll-request',
    section: 'HTTP failure journeys',
    title: 'GET /v1/requests/{request_reference} — SX-054 / SX-055',
    method: 'GET',
    path: '/v1/requests/{request_reference}',
    auth: 'operator',
    bodyKind: 'none',
    fields: [
      {
        name: 'request_reference',
        scope: 'path',
        defaultValue: '00000000-0000-4000-8000-000000000099',
        hint: 'Crockford request reference for journal-purged 404 or Completed-without-result',
        required: true,
        wide: true,
      },
    ],
    summary:
      'HTTP failure-journey poll — journal-purged 404 (SX-054) or Completed without result (SX-055). Operator bearer for local stack drivability.',
    successNote: '404 empty body or 200 { state: "Completed" } without result payload.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing operator bearer' },
      { status: 404, error: '(empty body)', trigger: 'Unknown or purged reference' },
    ],
  },
  {
    id: 'failure-support-lookup',
    section: 'HTTP failure journeys',
    title: 'POST /control/support/lookup — SX-054 / SX-055',
    method: 'POST',
    path: '/control/support/lookup',
    auth: 'operator',
    bodyKind: 'none',
    fields: [
      {
        name: 'reference',
        scope: 'query',
        defaultValue: '00000000-0000-4000-8000-000000000099',
        hint: 'Request reference query param',
        required: true,
        wide: true,
      },
    ],
    summary:
      'Operator support lookup for failure-journey diagnostics — cross-installation read by reference.',
    successNote: '200 — diagnostic dump or 404 not_found for purged reference.',
    failures: [
      { status: 401, error: 'unauthorized', trigger: 'Missing operator bearer' },
      { status: 404, error: 'not_found', trigger: 'No journal row for reference' },
    ],
  },
]
