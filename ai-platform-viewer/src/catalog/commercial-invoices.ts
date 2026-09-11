import type { JourneyOperationDefinition } from '@/catalog/journey-types'

export const COMMERCIAL_INVOICE_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'invoice-list',
    section: 'Issued invoices',
    title: 'List issued invoices (local D1)',
    method: 'GET',
    path: '/api/dev/invoices',
    auth: 'none',
    bodyKind: 'none',
    fields: [],
    summary:
      'SELECT issued G4 invoice rows from local D1 via wrangler d1 execute --local. SQL and JSON appear in the raw inspector — not a Worker HTTP route.',
    successNote:
      '200 — JSON array of invoice rows (installation_id, period, credits_consumed, credit_price_version, total, status, issued_at).',
    failures: [
      {
        status: 500,
        error: '(D1 error)',
        trigger: 'Local D1 unavailable or invoice table missing',
      },
    ],
  },
  {
    id: 'invoice-detail',
    section: 'Invoice evidence',
    title: 'Invoice rollup evidence (local D1)',
    method: 'GET',
    path: '/api/dev/invoices/detail',
    auth: 'none',
    bodyKind: 'none',
    fields: [
      {
        name: 'installation_id',
        scope: 'query',
        hint: 'Invoice installation_id',
        required: true,
        wide: true,
      },
      {
        name: 'period',
        scope: 'query',
        hint: 'Invoice period (YYYY-MM)',
        required: true,
        wide: true,
      },
    ],
    summary:
      'SELECT usage_rollup lines and usage_event → ai_request.request_reference traces for an installation and period. Frozen G4 evidence SQL — local D1 only.',
    successNote:
      '200 — { rollup_lines: [...], traces: [{ request_id, request_reference }, ...] }.',
    failures: [
      {
        status: 500,
        error: '(D1 error)',
        trigger: 'Local D1 unavailable or evidence tables missing',
      },
    ],
  },
]
