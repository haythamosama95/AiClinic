import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'

export const STAGE0_META: JourneyStageMeta = {
  id: 'stage-0',
  navLabel: 'Stage 0',
  navNote: 'Platform boot',
  eyebrow: 'Stage 0 · Platform configuration and boot',
  title: 'Build the airport before airlines arrive',
  lede:
    'Provision bindings, apply D1 migrations, and confirm the Worker isolate serves GET /health before any clinic enrolls. Scheduled cron handlers flush rejection counters, run retention purge (03:00), and rollup/reconciliation (04:00). Use wrangler dev --test-scheduled for local cron probes.',
  accentClass: 'stage-accent--boot',
  cardClass: 'operation-card--boot',
  buttonClass: 'boot-button',
}

export const STAGE0_OPERATIONS: JourneyOperationDefinition[] = [
  {
    id: 'health',
    section: 'Boot & health',
    title: 'GET /health',
    method: 'GET',
    path: '/health',
    auth: 'none',
    bodyKind: 'none',
    fields: [],
    summary:
      'Liveness probe — returns only build (BUILD_SHA) and environment (ENVIRONMENT). No auth, no D1 read. Confirms assertRequiredBindings passed and the isolate is serving.',
    successNote: '200 — {"build":"local","environment":"development"} on local dev.',
    failures: [
      {
        status: 0,
        error: '(connection refused)',
        trigger: 'Worker not running or missing DB/R2/DO binding threw at module load',
      },
    ],
  },
  {
    id: 'scheduled-cron',
    section: 'Scheduled jobs',
    title: 'Trigger scheduled handler',
    method: 'GET',
    path: '/cdn-cgi/handler/scheduled',
    auth: 'none',
    bodyKind: 'none',
    fields: [
      {
        name: 'cron',
        scope: 'query',
        defaultValue: '0+4+*+*+*',
        hint: 'Cron expression — use + for spaces (e.g. *+*+*+*+* every tick, 0+3+*+*+* retention, 0+4+*+*+* rollup)',
        wide: true,
      },
      {
        name: 'format',
        scope: 'query',
        defaultValue: 'json',
        hint: 'Response format — json returns { outcome: "ok" }',
      },
    ],
    summary:
      'Manually invoke the scheduled() handler when running wrangler dev --test-scheduled. Every tick runs flushRejectionCounters then reconcileGraceUsage; 0 3 * * * adds retention purge; 0 4 * * * adds rollup and reconciliation.',
    successNote:
      '200 — { "outcome": "ok" }. Watch wrangler stdout for scheduled_cron_start; retention/rollup logs only on matching cron.',
    failures: [
      {
        status: 404,
        error: '(not found)',
        trigger: 'Worker started without --test-scheduled',
      },
    ],
  },
]
