import { useState } from 'react'
import { Tabs } from '@/components/navigation/Tabs'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

const TAB_ITEMS = [
  { id: 'overview', label: 'Overview' },
  { id: 'visits', label: 'Visits' },
  { id: 'billing', label: 'Billing' },
  { id: 'documents', label: 'Documents', disabled: true },
]

export function TabsShowcase() {
  const [underline, setUnderline] = useState('overview')
  const [segmented, setSegmented] = useState('overview')
  const [vertical, setVertical] = useState('overview')

  return (
    <ShowcaseSection
      id="tabs"
      title="Tabs"
      description="Underline (Signal), segmented, and vertical variants with arrow-key navigation."
      componentName="Tabs"
    >
      <ShowcaseDemoGrid columns={1}>
        <ShowcaseDemo label="Underline (default)" propsHint='variant="underline"'>
          <Tabs items={TAB_ITEMS} value={underline} onChange={setUnderline} />
        </ShowcaseDemo>
        <ShowcaseDemo label="Segmented" propsHint='variant="segmented"'>
          <Tabs
            items={TAB_ITEMS.filter((t) => !t.disabled)}
            value={segmented}
            onChange={setSegmented}
            variant="segmented"
          />
        </ShowcaseDemo>
        <ShowcaseDemo label="Vertical" propsHint='variant="vertical"'>
          <Tabs
            items={TAB_ITEMS}
            value={vertical}
            onChange={setVertical}
            variant="vertical"
            className="w-48"
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
