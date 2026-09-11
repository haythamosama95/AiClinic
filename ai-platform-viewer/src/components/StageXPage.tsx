import { STAGE_X_OPERATIONS } from '@/catalog/stage-x'
import type { JourneyStageMeta } from '@/catalog/journey-types'
import { JourneyStagePage } from '@/components/JourneyStagePage'

const STAGE_X_META: JourneyStageMeta = {
  id: 'stage-x',
  navLabel: 'Stage X',
  navNote: 'Cron and failure journeys',
  eyebrow: 'Stage X · Cron and failure journeys',
  title: 'Catalog cron ticks and HTTP failure journeys',
  lede:
    'Drive scheduled handler crons (retention, rollup, G4 period close, unknown-cron fallthrough) via GET /cdn-cgi/handler/scheduled?cron= with wrangler dev --test-scheduled. HTTP failure-journey cards poll GET /v1/requests/{request_reference} and POST /control/support/lookup for SX-054 / SX-055.',
  accentClass: 'stage-accent--boot',
  cardClass: 'operation-card--boot',
  buttonClass: 'boot-button',
}

export function StageXPage() {
  return <JourneyStagePage meta={STAGE_X_META} operations={STAGE_X_OPERATIONS} />
}
