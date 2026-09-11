import {
  COMMERCIAL_PLAN_OPERATIONS,
} from '@/catalog/commercial-plans'
import type { JourneyStageMeta } from '@/catalog/journey-types'
import { JourneyStagePage } from '@/components/JourneyStagePage'

const PLANS_META: JourneyStageMeta = {
  id: 'plans',
  navLabel: 'Plans',
  navNote: 'G1 plan catalogue',
  eyebrow: 'Commercial · Plan catalogue',
  title: 'G1 plan catalogue CRUD',
  lede:
    'Create, update, and delete plans via the three frozen G1 POST mutations. Missing operator credentials surface the frozen B2 401 {"error":"unauthorized"} body in the raw inspector — no viewer diagnostic.',
  accentClass: 'stage-accent--entitlement',
  cardClass: 'operation-card--entitlement',
  buttonClass: 'entitlement-button',
}

export function PlansPage() {
  return <JourneyStagePage meta={PLANS_META} operations={COMMERCIAL_PLAN_OPERATIONS} />
}
