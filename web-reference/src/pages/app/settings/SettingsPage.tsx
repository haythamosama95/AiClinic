import { Bell, Palette, Printer, Shield, Sparkles } from 'lucide-react'
import { PageHeader } from '@/components/layout/PageHeader'
import { SETTINGS_SCREENS, type SettingsScreenId } from '@/data/settings'
import { cn } from '@/lib/cn'
import { ScreenPanel } from './components/AnimatedPanels'
import {
  AppearanceScreen,
  NotificationsScreen,
  PrintingScreen,
  PrivacyScreen,
  SecurityScreen,
} from './screens/SettingsScreens'
import './settings-layout.css'

export type SettingsPageProps = {
  screen?: string
  onNavigate: (route: string) => void
}

export const SETTINGS_NAV_ICONS = {
  appearance: Palette,
  notifications: Bell,
  security: Shield,
  printing: Printer,
  privacy: Sparkles,
} as const

function resolveScreen(screen?: string): SettingsScreenId {
  const match = SETTINGS_SCREENS.find((s) => s.id === screen)
  return match?.id ?? SETTINGS_SCREENS[0].id
}

function SettingsRail({
  screen,
  onNavigate,
}: {
  screen: SettingsScreenId
  onNavigate: (route: string) => void
}) {
  return (
    <aside className="settings-rail">
      <nav className="settings-rail-nav" aria-label="Settings sections">
        <p className="settings-rail-nav-label" id="settings-sections-label">
          Sections
        </p>
        <ul className="settings-rail-list" aria-labelledby="settings-sections-label">
          {SETTINGS_SCREENS.map((item) => {
            const Icon = SETTINGS_NAV_ICONS[item.id]
            const active = item.id === screen
            return (
              <li key={item.id}>
                <button
                  type="button"
                  onClick={() => onNavigate(`settings/${item.id}`)}
                  className={cn('settings-rail-btn focus-ring', active && 'settings-rail-btn--active')}
                  aria-current={active ? 'page' : undefined}
                >
                  <Icon size={16} strokeWidth={1.75} className="settings-rail-btn-icon" aria-hidden />
                  <span className="settings-rail-btn-label">{item.label}</span>
                </button>
              </li>
            )
          })}
        </ul>
      </nav>
    </aside>
  )
}

function SettingsContent({ screen }: { screen: SettingsScreenId }) {
  switch (screen) {
    case 'appearance':
      return <AppearanceScreen />
    case 'notifications':
      return <NotificationsScreen />
    case 'printing':
      return <PrintingScreen />
    case 'privacy':
      return <PrivacyScreen />
    case 'security':
    default:
      return <SecurityScreen />
  }
}

export function SettingsPage({ screen: screenParam, onNavigate }: SettingsPageProps) {
  const screen = resolveScreen(screenParam)
  const activeMeta = SETTINGS_SCREENS.find((s) => s.id === screen) ?? SETTINGS_SCREENS[0]

  return (
    <div className="space-y-6">
      <PageHeader
        title="Settings"
        description="Personal preferences for this workstation — theme, alerts, security, and printing."
      />

      <div className="settings-layout">
        <SettingsRail screen={screen} onNavigate={onNavigate} />

        <main className="settings-layout-main min-w-0">
          <ScreenPanel screenKey={screen}>
            <SettingsContent screen={screen} />
          </ScreenPanel>
        </main>
      </div>

      <p className="sr-only" aria-live="polite">
        Viewing {activeMeta.label} settings
      </p>
    </div>
  )
}
