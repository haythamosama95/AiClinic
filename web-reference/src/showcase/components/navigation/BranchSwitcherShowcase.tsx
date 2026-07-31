import { useState } from 'react'
import { BranchSwitcher } from '@/components/navigation/BranchSwitcher'
import { MOCK_BRANCHES } from '@/components/navigation/nav-model'
import { ShowcaseDemo, ShowcaseSection } from '../../ShowcasePrimitives'

export function BranchSwitcherShowcase() {
  const [branchId, setBranchId] = useState(MOCK_BRANCHES[0].id)

  return (
    <ShowcaseSection
      id="branch-switcher"
      title="Branch switcher"
      description="Switch between clinic branches with org context and search."
      componentName="BranchSwitcher"
    >
      <ShowcaseDemo label="Default" propsHint="branches + onBranchChange">
        <BranchSwitcher
          branches={MOCK_BRANCHES}
          currentBranchId={branchId}
          onBranchChange={setBranchId}
        />
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
