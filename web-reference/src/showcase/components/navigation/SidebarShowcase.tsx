import { useState } from 'react'
import { AppSidebar } from '@/components/navigation/AppSidebar'
import {
  CLINIC_NAV_FOOTER,
  CLINIC_NAV_GROUPS,
  MOCK_BRANCHES,
  MOCK_ORG,
} from '@/components/navigation/nav-model'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function SidebarShowcase() {
  const [activeId, setActiveId] = useState('patients')

  return (
    <ShowcaseSection
      id="app-sidebar"
      title="App sidebar"
      description="Expanded and collapsed rail with Signal active indicator and keyboard navigation."
      componentName="AppSidebar"
    >
      <ShowcaseDemoGrid columns={2}>
        <ShowcaseDemo label="Expanded" propsHint="collapsed={false}">
          <div className="h-96 overflow-hidden rounded-lg border border-border-default">
            <AppSidebar
              items={CLINIC_NAV_GROUPS}
              footerItems={CLINIC_NAV_FOOTER}
              activeId={activeId}
              onNavigate={setActiveId}
              collapsed={false}
              onToggleCollapsed={() => undefined}
              org={MOCK_ORG}
              branch={MOCK_BRANCHES[0].name}
            />
          </div>
        </ShowcaseDemo>
        <ShowcaseDemo label="Collapsed rail" propsHint="collapsed={true}">
          <div className="h-96 overflow-hidden rounded-lg border border-border-default">
            <AppSidebar
              items={CLINIC_NAV_GROUPS}
              footerItems={CLINIC_NAV_FOOTER}
              activeId={activeId}
              onNavigate={setActiveId}
              collapsed
              onToggleCollapsed={() => undefined}
              org={MOCK_ORG}
              branch={MOCK_BRANCHES[0].name}
            />
          </div>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
