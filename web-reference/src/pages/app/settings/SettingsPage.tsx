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

export type SettingsPageProps = {
  screen?: string
  onNavigate: (route: string) => void
}

function resolveScreen(screen?: string): SettingsScreenId {
  const match = SETTINGS_SCREENS.find((s) => s.id === screen)
  return match?.id ?? 'general'
}

function SettingsContent({ screen }: { screen: SettingsScreenId }) {
  switch (screen) {
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
  }
}

export function SettingsPage({ screen: screenParam, onNavigate }: SettingsPageProps) {
  const screen = resolveScreen(screenParam)
  const activeMeta = SETTINGS_SCREENS.find((s) => s.id === screen) ?? SETTINGS_SCREENS[0]

  return (
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
          <ScreenPanel screenKey={screen}>
            <SettingsContent screen={screen} />
          </ScreenPanel>
        </main>
      </div>

      <p className="sr-only" aria-live="polite">
        Viewing {activeMeta.label} settings
      </p>
    </SetupProvider>
  )
}
