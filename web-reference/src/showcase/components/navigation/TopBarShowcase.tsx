import { useState } from 'react'
import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { AppTopBar } from '@/components/navigation/AppTopBar'
import {
  MOCK_BRANCHES,
  MOCK_NOTIFICATION_COUNT,
  MOCK_USER,
} from '@/components/navigation/nav-model'
import { ShowcaseDemo, ShowcaseSection } from '../../ShowcasePrimitives'

export function TopBarShowcase() {
  const [branchId, setBranchId] = useState(MOCK_BRANCHES[0].id)

  return (
    <ShowcaseSection
      id="app-topbar"
      title="App top bar"
      description="Sticky chrome with command trigger, branch switcher, AI toggle, and user menu."
      componentName="AppTopBar"
    >
      <ShowcaseDemo label="Default composition" propsHint="slots + live providers">
        <div className="w-full overflow-hidden rounded-lg border border-border-default">
          <AppTopBar
            pageContext={
              <Breadcrumb
                items={[
                  { label: 'Patients', href: '#' },
                  { label: 'Layla Hassan' },
                ]}
              />
            }
            branches={MOCK_BRANCHES}
            currentBranchId={branchId}
            onBranchChange={setBranchId}
            user={MOCK_USER}
            notificationCount={MOCK_NOTIFICATION_COUNT}
          />
        </div>
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
