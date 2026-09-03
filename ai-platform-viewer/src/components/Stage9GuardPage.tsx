import { STAGE9_META, STAGE9_OPERATIONS } from '@/catalog/stage-9-guard'
import { JourneyStagePage } from '@/components/JourneyStagePage'

export function Stage9GuardPage() {
  return <JourneyStagePage meta={STAGE9_META} operations={STAGE9_OPERATIONS} />
}
