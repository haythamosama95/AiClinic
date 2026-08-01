<<<<<<< HEAD
import { PageHeader } from '@/components/layout/PageHeader'
import { SETTINGS_SCREENS, type SettingsScreenId } from '@/data/settings'
import { cn } from '@/lib/cn'
import { SetupProvider } from './SetupContext'
import { ScreenPanel } from './components/AnimatedPanels'
import {
  BranchesScreen,
  GeneralScreen,
  NotificationsScreen,
  ServicesScreen,
  settingsNavItemClass,
  SetupScreen,
  SETTINGS_NAV_ICONS,
  StaffScreen,
} from './screens/SettingsScreens'
=======
import { Bell, Palette, Shield } from 'lucide-react'
import { PageHeader } from '@/components/layout/PageHeader'
import { SETTINGS_SCREENS, type SettingsScreenId } from '@/data/settings'
import { cn } from '@/lib/cn'
import { ScreenPanel } from './components/AnimatedPanels'
import {
  AppearanceScreen,
  NotificationsScreen,
  SecurityScreen,
} from './screens/SettingsScreens'
import './settings-layout.css'
>>>>>>> master

export type SettingsPageProps = {
  screen?: string
  onNavigate: (route: string) => void
}

<<<<<<< HEAD
function resolveScreen(screen?: string): SettingsScreenId {
  const match = SETTINGS_SCREENS.find((s) => s.id === screen)
  return match?.id ?? 'general'
=======
export const SETTINGS_NAV_ICONS = {
  appearance: Palette,
  notifications: Bell,
  security: Shield,
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
>>>>>>> master
}

function SettingsContent({ screen }: { screen: SettingsScreenId }) {
  switch (screen) {
<<<<<<< HEAD
    case 'setup':
      return <SetupScreen />
    case 'branches':
      return <BranchesScreen />
    case 'staff':
      return <StaffScreen />
    case 'services':
      return <ServicesScreen />
    case 'notifications':
      return <NotificationsScreen />
    case 'general':
    default:
      return <GeneralScreen />
=======
    case 'appearance':
      return <AppearanceScreen />
    case 'notifications':
      return <NotificationsScreen />
    case 'security':
    default:
      return <SecurityScreen />
>>>>>>> master
  }
}

export function SettingsPage({ screen: screenParam, onNavigate }: SettingsPageProps) {
  const screen = resolveScreen(screenParam)
  const activeMeta = SETTINGS_SCREENS.find((s) => s.id === screen) ?? SETTINGS_SCREENS[0]

  return (
<<<<<<< HEAD
    <SetupProvider>
      <PageHeader
        title="Settings"
        description="Configure your clinic, team, and operational defaults."
      />

      <div className="mt-8 flex flex-col gap-8 lg:flex-row lg:gap-12">
        <nav
          className="lg:w-56 lg:shrink-0"
          aria-label="Settings sections"
        >
          <ul className="flex gap-1 overflow-x-auto pb-1 lg:flex-col lg:overflow-visible lg:pb-0">
            {SETTINGS_SCREENS.map((item) => {
              const Icon = SETTINGS_NAV_ICONS[item.id]
              const active = item.id === screen
              return (
                <li key={item.id} className="shrink-0 lg:shrink">
                  <button
                    type="button"
                    onClick={() => onNavigate(`settings/${item.id}`)}
                    className={cn(settingsNavItemClass(active), 'whitespace-nowrap lg:whitespace-normal')}
                    aria-current={active ? 'page' : undefined}
                  >
                    <Icon
                      size={18}
                      strokeWidth={1.5}
                      className={cn(
                        'shrink-0',
                        active ? 'text-[var(--color-teal-600)]' : 'text-icon-muted',
                      )}
                      aria-hidden
                    />
                    <span>{item.label}</span>
                  </button>
                </li>
              )
            })}
          </ul>
        </nav>

        <main className="min-w-0 flex-1">
=======
    <div className="space-y-6">
      <PageHeader
        title="Settings"
        description="Personal preferences for this workstation — theme, alerts, and security."
      />

      <div className="settings-layout">
        <SettingsRail screen={screen} onNavigate={onNavigate} />

        <main className="settings-layout-main min-w-0">
>>>>>>> master
          <ScreenPanel screenKey={screen}>
            <SettingsContent screen={screen} />
          </ScreenPanel>
        </main>
      </div>

      <p className="sr-only" aria-live="polite">
        Viewing {activeMeta.label} settings
      </p>
<<<<<<< HEAD
    </SetupProvider>
=======
    </div>
>>>>>>> master
  )
}
