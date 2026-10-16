import { STAGE12_META, STAGE12_OPERATIONS } from '@/catalog/stage-12-lookup-support'
import { JourneyStagePage } from '@/components/JourneyStagePage'

export function Stage12LookupSupportPage() {
  return <JourneyStagePage meta={STAGE12_META} operations={STAGE12_OPERATIONS} />
}
