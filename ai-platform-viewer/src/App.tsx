import { SessionProvider } from '@/context/SessionContext'
import { AppShell } from '@/components/AppShell'

export function App() {
  return (
    <SessionProvider>
      <AppShell />
    </SessionProvider>
  )
}
