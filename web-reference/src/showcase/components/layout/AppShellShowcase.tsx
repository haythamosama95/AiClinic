import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { AppShell } from '@/components/layout/AppShell'
import { PageHeader } from '@/components/layout/PageHeader'
import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { AppSidebar } from '@/components/navigation/AppSidebar'
import { AppTopBar } from '@/components/navigation/AppTopBar'
import { Tabs } from '@/components/navigation/Tabs'
import {
  CLINIC_NAV_FOOTER,
  CLINIC_NAV_GROUPS,
  MOCK_BRANCHES,
  MOCK_NOTIFICATION_COUNT,
  MOCK_ORG,
  MOCK_USER,
} from '@/components/navigation/nav-model'
import { Skeleton } from '@/components/skeleton'
import { ShowcaseToolbar } from '@/components/showcase/ShowcaseToolbar'
import { ShowcaseDemo, ShowcaseSection } from '../../ShowcasePrimitives'

export function AppShellShowcase() {
  const [activeId, setActiveId] = useState('patients')
  const [collapsed, setCollapsed] = useState(false)
  const [branchId, setBranchId] = useState(MOCK_BRANCHES[0].id)
  const [tab, setTab] = useState('overview')

  const branch = MOCK_BRANCHES.find((b) => b.id === branchId) ?? MOCK_BRANCHES[0]

  return (
    <ShowcaseSection
      id="app-shell"
      title="App shell"
      description="Live shell with sidebar, top bar, command bar, and placeholder page content."
      componentName="AppShell"
    >
      <ShowcaseDemo label="Live shell demo" propsHint="⌘K · collapse · toggles">
        <div className="h-[32rem] w-full overflow-hidden rounded-xl border border-border-default shadow-elevation-2">
          <AppShell
            sidebar={
              <AppSidebar
                items={CLINIC_NAV_GROUPS}
                footerItems={CLINIC_NAV_FOOTER}
                activeId={activeId}
                onNavigate={setActiveId}
                collapsed={collapsed}
                onToggleCollapsed={() => setCollapsed((c) => !c)}
                org={MOCK_ORG}
                branch={branch.name}
              />
            }
            topBar={
              <AppTopBar
                pageContext={
                  <Breadcrumb
                    items={[
                      { label: 'Patients', onClick: () => setActiveId('patients') },
                      { label: 'Directory' },
                    ]}
                  />
                }
                branches={MOCK_BRANCHES}
                currentBranchId={branchId}
                onBranchChange={setBranchId}
                user={MOCK_USER}
                notificationCount={MOCK_NOTIFICATION_COUNT}
                toolbarSlot={<ShowcaseToolbar />}
              />
            }
          >
            <PageHeader
              title="Patients"
              description="Manage patient records, demographics, and care history."
              actions={<Button variant="primary">New patient</Button>}
              tabs={
                <Tabs
                  items={[
                    { id: 'overview', label: 'Overview' },
                    { id: 'active', label: 'Active' },
                    { id: 'archived', label: 'Archived' },
                  ]}
                  value={tab}
                  onChange={setTab}
                />
              }
            />
            <div className="mt-8 space-y-4">
              <div className="grid gap-4 sm:grid-cols-3">
                <Skeleton className="h-24 rounded-lg" />
                <Skeleton className="h-24 rounded-lg" />
                <Skeleton className="h-24 rounded-lg" />
              </div>
              <Skeleton className="h-48 w-full rounded-lg" />
              <Skeleton className="h-32 w-full rounded-lg" />
            </div>
          </AppShell>
        </div>
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
