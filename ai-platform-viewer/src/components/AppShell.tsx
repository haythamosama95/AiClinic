import { HeaderBar } from '@/components/HeaderBar'
import { SecretsPage } from '@/components/SecretsPage'
import { SideNav } from '@/components/SideNav'
import { Stage1TokenContractPage } from '@/components/Stage1TokenContractPage'
import { Stage2ClinicKeypairPage } from '@/components/Stage2ClinicKeypairPage'
import { useSession } from '@/context/SessionContext'

export function AppShell() {
  const { activeSection } = useSession()

  return (
    <div className="app-shell">
      <HeaderBar />
      <div className="app-shell__body">
        <SideNav />
        <main className="app-shell__main">
          {activeSection === 'secrets' ? (
            <SecretsPage />
          ) : activeSection === 'stage-2' ? (
            <Stage2ClinicKeypairPage />
          ) : (
            <Stage1TokenContractPage />
          )}
        </main>
      </div>
    </div>
  )
}
