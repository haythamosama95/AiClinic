import { COMMERCIAL_USAGE_OPERATIONS } from '@/catalog/commercial-usage'
import type { JourneyStageMeta } from '@/catalog/journey-types'
import { CreditGauge } from '@/components/CreditGauge'
import { JourneyStagePage } from '@/components/JourneyStagePage'

const USAGE_META: JourneyStageMeta = {
  id: 'usage',
  navLabel: 'Usage',
  navNote: 'G3 credits-only gauge',
  eyebrow: 'Commercial · Credit gauge',
  title: 'G3 credits-only usage gauge',
  lede:
    'GET /v1/usage with installation AAT. The gauge renders only credits_used against credit_budget — no token, cost, or price fields. Does not call GET /control/installations/:id/quota.',
  accentClass: 'stage-accent--routing',
  cardClass: 'operation-card--routing',
  buttonClass: 'routing-button',
}

export function UsageGaugePage() {
  return (
    <JourneyStagePage
      meta={USAGE_META}
      operations={COMMERCIAL_USAGE_OPERATIONS}
      mintAatBeforeEachRequest
      seedPanels={<CreditGauge model={null} />}
    />
  )
}
