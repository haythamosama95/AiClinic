import { SideNav } from '@/components/SideNav'
import { Stage7DiscoveryPage } from '@/components/Stage7DiscoveryPage'
import { Stage8IngressPage } from '@/components/Stage8IngressPage'
import { Stage9GuardPage } from '@/components/Stage9GuardPage'
import { Stage10StreamPage } from '@/components/Stage10StreamPage'
import { Stage11SettlementPage } from '@/components/Stage11SettlementPage'
import { Stage12LookupSupportPage } from '@/components/Stage12LookupSupportPage'
import { ToastStack } from '@/components/ToastStack'
import { useSession } from '@/context/SessionContext'
import type { NavSection } from '@/types'
import type { ReactNode } from 'react'

const STAGE_PAGES: Record<NavSection, ReactNode> = {
  'stage-7': <Stage7DiscoveryPage />,
  'stage-8': <Stage8IngressPage />,
  'stage-9': <Stage9GuardPage />,
  'stage-10': <Stage10StreamPage />,
  'stage-11': <Stage11SettlementPage />,
  'stage-12': <Stage12LookupSupportPage />,
}

export function AppShell() {
  const { activeSection, toasts, dismissToast } = useSession()

  return (
    <div className="app-shell">
      <div className="app-shell__body">
        <SideNav />
        <main className="app-shell__main">
          {STAGE_PAGES[activeSection]}
        </main>
      </div>
      <ToastStack toasts={toasts} onDismiss={dismissToast} />
    </div>
  )
}
