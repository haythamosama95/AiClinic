import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'

export const STAGE7_META: JourneyStageMeta = {
  id: 'stage-7',
  navLabel: 'Stage 7',
  navNote: 'Discovery',
  eyebrow: 'Stage 7 · Discovery',
  title: 'What AI features can I use?',
  lede:
    'GET /v1/capabilities lists capability manifests the installation may invoke — filtered to entitled, granted, non-retired capabilities. Kill switches are not applied on discovery (they apply on invoke). Auth is the clinic AAT only; no extra required headers.',
  accentClass: 'stage-accent--discovery',
  cardClass: 'operation-card--discovery',
  buttonClass: 'discovery-button',
}

export const STAGE7_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'get-capabilities',
    section: 'Discovery response',
    title: 'Get capabilities',
    method: 'GET',
    path: '/v1/capabilities',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'Returns { manifests: [...] } for entitled capabilities. Pending entitlement yields { manifests: [] }. Response includes ETag and Cache-Control: private, must-revalidate.',
    successNote:
      '200 — { manifests: [...] } with ETag header. Each manifest carries capabilityId, version, context requirements, and economics.',
    failures: [
      {
        status: 401,
        error: 'unauthenticated',
        trigger: 'Missing/invalid AAT, unknown ver on token_contract, or retired ver claim',
      },
      {
        status: 403,
        error: 'installation_suspended',
        trigger: 'installation.status = suspended',
      },
    ],
    fields: [],
  },
  {
    id: 'get-capabilities-conditional',
    section: 'Conditional GET',
    title: 'Get capabilities (If-None-Match)',
    method: 'GET',
    path: '/v1/capabilities',
    auth: 'aat',
    bodyKind: 'none',
    summary:
      'Sends If-None-Match with a prior ETag. When the opaque tag still matches, the handler returns 304 Not Modified with an empty body — the client keeps its cached manifests array.',
    successNote:
      '304 — empty body, ETag echoed. 200 when tag is stale, absent, or does not match.',
    failures: [
      {
        status: 401,
        error: 'unauthenticated',
        trigger: 'Missing/invalid AAT',
      },
    ],
    fields: [
      {
        name: 'If-None-Match',
        scope: 'header',
        hint: 'Quoted etag from a prior 200 response — leave empty for a normal 200',
        defaultValue: '',
        wide: true,
        required: false,
      },
    ],
  },
]
