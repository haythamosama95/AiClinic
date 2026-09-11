import { SecretsPage } from '@/components/SecretsPage'
import { SideNav } from '@/components/SideNav'
import { Stage0PlatformBootPage } from '@/components/Stage0PlatformBootPage'
import { Stage1TokenContractPage } from '@/components/Stage1TokenContractPage'
import { Stage2ClinicKeypairPage } from '@/components/Stage2ClinicKeypairPage'
import { Stage3PlatformInstallationPage } from '@/components/Stage3PlatformInstallationPage'
import { Stage4EntitlementPage } from '@/components/Stage4EntitlementPage'
import { Stage5RoutingPage } from '@/components/Stage5RoutingPage'
import { Stage6MintAatPage } from '@/components/Stage6MintAatPage'
import { Stage7DiscoveryPage } from '@/components/Stage7DiscoveryPage'
import { Stage8IngressPage } from '@/components/Stage8IngressPage'
import { Stage9GuardPage } from '@/components/Stage9GuardPage'
import { Stage10StreamPage } from '@/components/Stage10StreamPage'
import { Stage11SettlementPage } from '@/components/Stage11SettlementPage'
import { GuardPipelinePage } from '@/components/GuardPipelinePage'
import { InvoicesPage } from '@/components/InvoicesPage'
import { PlansPage } from '@/components/PlansPage'
import { Stage12LookupSupportPage } from '@/components/Stage12LookupSupportPage'
import { StageXPage } from '@/components/StageXPage'
import { UsageGaugePage } from '@/components/UsageGaugePage'
import { ToastStack } from '@/components/ToastStack'
import { useSession } from '@/context/SessionContext'
import type { NavSection } from '@/types'
import type { ReactNode } from 'react'

const STAGE_PAGES: Record<Exclude<NavSection, 'secrets'>, ReactNode> = {
  'stage-0': <Stage0PlatformBootPage />,
  'stage-1': <Stage1TokenContractPage />,
  'stage-2': <Stage2ClinicKeypairPage />,
  'stage-3': <Stage3PlatformInstallationPage />,
  'stage-4': <Stage4EntitlementPage />,
  'stage-5': <Stage5RoutingPage />,
  'stage-6': <Stage6MintAatPage />,
  'stage-7': <Stage7DiscoveryPage />,
  'stage-8': <Stage8IngressPage />,
  'stage-9': <Stage9GuardPage />,
  'stage-10': <Stage10StreamPage />,
  'stage-11': <Stage11SettlementPage />,
  'stage-12': <Stage12LookupSupportPage />,
  'guard-pipeline': <GuardPipelinePage />,
  plans: <PlansPage />,
  usage: <UsageGaugePage />,
  invoices: <InvoicesPage />,
  'stage-x': <StageXPage />,
}

export function AppShell() {
  const { activeSection, toasts, dismissToast } = useSession()

  return (
    <div className="app-shell">
      <div className="app-shell__body">
        <SideNav />
        <main className="app-shell__main">
          {activeSection === 'secrets'
            ? <SecretsPage />
            : STAGE_PAGES[activeSection]}
        </main>
      </div>
      <ToastStack toasts={toasts} onDismiss={dismissToast} />
    </div>
  )
}
