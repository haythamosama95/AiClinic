import { STAGE7_META, STAGE7_OPERATIONS } from '@/catalog/stage-7-discovery'
import { JourneyStagePage } from '@/components/JourneyStagePage'

export function Stage7DiscoveryPage() {
  return <JourneyStagePage meta={STAGE7_META} operations={STAGE7_OPERATIONS} />
}
