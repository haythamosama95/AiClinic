<<<<<<< HEAD
import { Bell, Building2, MapPinned, Stethoscope, Users, WandSparkles } from 'lucide-react'
import { motion } from 'motion/react'
import { Badge } from '@/components/badge'
import { Card } from '@/components/card/Card'
import { DescriptionList } from '@/components/description-list/DescriptionList'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { CURRENCY_OPTIONS, TIMEZONE_OPTIONS } from '@/data/settings'
import { cn } from '@/lib/cn'
import { isSetupComplete, useSetup } from '../SetupContext'
import { SetupWizard } from '../setup/SetupWizard'

export function SetupScreen() {
  const setupDone = isSetupComplete()

  return (
    <div className="space-y-6">
      <div>
        <h2 className="font-display text-h2 text-text-primary">Setup</h2>
        <p className="mt-1 max-w-2xl text-body text-text-secondary">
          Walk through the essentials to get your clinic running — organization, branches, staff,
          and services.
        </p>
      </div>

      {setupDone ? (
        <Card variant="raised" padding="lg" className="border-[var(--color-teal-200)] bg-[var(--color-teal-50)]/30">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="flex size-10 items-center justify-center rounded-full bg-[var(--color-teal-100)] text-[var(--color-teal-700)]">
                <WandSparkles size={18} aria-hidden />
              </div>
              <div>
                <p className="text-body-strong text-text-primary">Setup complete</p>
                <p className="text-body-sm text-text-secondary">
                  Your clinic configuration is in place. Re-run the wizard to change defaults.
                </p>
              </div>
            </div>
            <Badge color="success" variant="soft">
              Done
            </Badge>
          </div>
        </Card>
      ) : null}

      <SetupWizard />
    </div>
  )
}

export function GeneralScreen() {
  const { draft } = useSetup()

  const timezoneLabel =
    TIMEZONE_OPTIONS.find((t) => t.value === draft.organization.timezone)?.label ??
    draft.organization.timezone
  const currencyLabel =
    CURRENCY_OPTIONS.find((c) => c.value === draft.organization.currency)?.label ??
    draft.organization.currency

  return (
    <div className="space-y-6">
      <div>
        <h2 className="font-display text-h2 text-text-primary">General</h2>
        <p className="mt-1 text-body text-text-secondary">
          Organization-wide defaults that apply to every branch.
        </p>
      </div>

      <Card variant="flat" padding="lg">
        <DescriptionList
          items={[
            { label: 'Organization name', value: draft.organization.name || '—' },
            { label: 'Timezone', value: timezoneLabel },
            { label: 'Currency', value: currencyLabel },
          ]}
        />
        <p className="mt-4 text-caption text-text-tertiary">
          Edit these in the Setup wizard or update them here when editing is enabled.
        </p>
      </Card>
    </div>
  )
}

function SummaryListScreen({
  title,
  description,
  icon: Icon,
  items,
  emptyTitle,
  emptyDescription,
}: {
  title: string
  description: string
  icon: typeof Building2
  items: { id: string; primary: string; secondary?: string }[]
  emptyTitle: string
  emptyDescription: string
}) {
  return (
    <div className="space-y-6">
      <div className="flex items-start gap-3">
        <div className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-surface-muted text-icon-default">
          <Icon size={20} strokeWidth={1.5} aria-hidden />
        </div>
        <div>
          <h2 className="font-display text-h2 text-text-primary">{title}</h2>
          <p className="mt-1 text-body text-text-secondary">{description}</p>
        </div>
      </div>

      {items.length === 0 ? (
        <EmptyState variant="first-run" title={emptyTitle} description={emptyDescription} />
      ) : (
        <ul className="divide-y divide-border-subtle rounded-lg border border-border-default bg-surface-default">
          {items.map((item, index) => (
            <motion.li
              key={item.id}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.04 }}
              className="flex items-center justify-between gap-4 px-5 py-4"
            >
              <div className="min-w-0">
                <p className="truncate text-body-strong text-text-primary">{item.primary}</p>
                {item.secondary ? (
                  <p className="truncate text-caption text-text-tertiary">{item.secondary}</p>
                ) : null}
              </div>
            </motion.li>
          ))}
        </ul>
      )}
=======
import { Bell, Clock, Palette, Shield } from 'lucide-react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { Select } from '@/components/ui/select/Select'
import { Switch } from '@/components/ui/switch/Switch'
import {
  DATE_FORMAT_OPTIONS,
  IDLE_TIMEOUT_PRESETS,
  TIME_FORMAT_OPTIONS,
} from '@/data/settings'
import { cn } from '@/lib/cn'
import { useDirection, type Locale } from '@/providers/DirectionProvider'
import { useTheme, type ThemePreference } from '@/providers/ThemeProvider'
import {
  useFormatPreferences,
  useIdleTimeout,
  useNotificationPrefs,
} from '../hooks/useSettingsStorage'

const LOCALE_OPTIONS: { value: Locale; label: string }[] = [
  { value: 'en', label: 'English' },
  { value: 'ar', label: 'العربية' },
]

const THEME_OPTIONS: { value: ThemePreference; label: string }[] = [
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'system', label: 'System' },
]

function ScreenHeader({
  icon: Icon,
  title,
  description,
  action,
}: {
  icon: typeof Shield
  title: string
  description: string
  action?: React.ReactNode
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div className="flex items-start gap-3">
        <div className="flex size-10 shrink-0 items-center justify-center rounded-lg border border-border-subtle bg-surface-muted text-text-link">
          <Icon size={20} strokeWidth={1.5} aria-hidden />
        </div>
        <div>
          <h2 className="font-display text-xl font-semibold tracking-tight text-text-primary">{title}</h2>
          <p className="mt-1 max-w-2xl text-body-sm text-text-secondary">{description}</p>
        </div>
      </div>
      {action}
>>>>>>> master
    </div>
  )
}

<<<<<<< HEAD
export function BranchesScreen() {
  const { draft } = useSetup()
  const items = draft.branches
    .filter((b) => b.name.trim())
    .map((b) => ({
      id: b.id,
      primary: b.name,
      secondary: [b.code, b.mobile].filter(Boolean).join(' · '),
    }))

  return (
    <SummaryListScreen
      title="Branches"
      description="Physical locations where care is delivered."
      icon={MapPinned}
      items={items}
      emptyTitle="No branches yet"
      emptyDescription="Complete the Setup wizard to add your first branch."
    />
  )
}

export function StaffScreen() {
  const { draft } = useSetup()
  const items = draft.staff
    .filter((s) => s.name.trim())
    .map((s) => ({
      id: s.id,
      primary: s.name,
      secondary: `${s.role} · ${s.branchIds.length} branch${s.branchIds.length !== 1 ? 'es' : ''}`,
    }))

  return (
    <SummaryListScreen
      title="Staff"
      description="People who sign in and work across your branches."
      icon={Users}
      items={items}
      emptyTitle="No staff yet"
      emptyDescription="Complete the Setup wizard to add your first team member."
    />
  )
}

export function ServicesScreen() {
  const { draft } = useSetup()
  const items = draft.services
    .filter((s) => s.name.trim())
    .map((s) => ({
      id: s.id,
      primary: s.name,
      secondary:
        s.price !== null
          ? new Intl.NumberFormat('en', {
            style: 'currency',
            currency: draft.organization.currency,
          }).format(s.price)
          : undefined,
    }))

  return (
    <SummaryListScreen
      title="Services"
      description="Billable procedures in your catalog."
      icon={Stethoscope}
      items={items}
      emptyTitle="No services yet"
      emptyDescription="Complete the Setup wizard to add your first service."
    />
  )
}

export function NotificationsScreen() {
  return (
    <div className="space-y-6">
      <div className="flex items-start gap-3">
        <div className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-surface-muted text-icon-default">
          <Bell size={20} strokeWidth={1.5} aria-hidden />
        </div>
        <div>
          <h2 className="font-display text-h2 text-text-primary">Notifications</h2>
          <p className="mt-1 text-body text-text-secondary">
            Control how your team receives alerts and reminders.
          </p>
        </div>
      </div>

      <Card variant="flat" padding="lg" className="text-center">
        <p className="text-body text-text-secondary">
          Notification preferences will be configurable in a future release.
        </p>
      </Card>
=======
function ContentPanel({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        'rounded-xl border border-border-subtle bg-surface-default p-6 shadow-elevation-1',
        className,
      )}
    >
      {children}
    </div>
  )
}

function SettingRow({
  title,
  description,
  children,
}: {
  title: string
  description?: string
  children: React.ReactNode
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-4 py-4 first:pt-0 last:pb-0">
      <div className="min-w-0 flex-1">
        <p className="text-body-strong text-text-primary">{title}</p>
        {description ? <p className="mt-1 text-body-sm text-text-secondary">{description}</p> : null}
      </div>
      <div className="shrink-0">{children}</div>
    </div>
  )
}

export function AppearanceScreen() {
  const { theme, setTheme } = useTheme()
  const { locale, setLocale } = useDirection()
  const { dateFormat, setDateFormat, timeFormat, setTimeFormat } = useFormatPreferences()

  return (
    <div className="space-y-6">
      <ScreenHeader
        icon={Palette}
        title="Appearance"
        description="Set how the app looks and formats dates and times on this workstation."
      />

      <ContentPanel className="divide-y divide-border-subtle">
        <SettingRow
          title="Color theme"
          description="Choose light, dark, or match your operating system."
        >
          <SegmentedControl
            aria-label="Color theme"
            size="sm"
            value={theme}
            onChange={setTheme}
            options={THEME_OPTIONS.map(({ value, label }) => ({ value, label }))}
          />
        </SettingRow>

        <SettingRow
          title="Language"
          description="Sets the interface language and text direction for your account."
        >
          <SegmentedControl
            aria-label="Language"
            size="sm"
            value={locale}
            onChange={setLocale}
            options={LOCALE_OPTIONS}
          />
        </SettingRow>

        <SettingRow title="Date format" description="How dates appear in lists, forms, and reports.">
          <Select
            className="w-44"
            value={dateFormat}
            onValueChange={(v) => setDateFormat(v as typeof dateFormat)}
            options={DATE_FORMAT_OPTIONS.map((o) => ({ value: o.value, label: o.label }))}
            aria-label="Date format"
          />
        </SettingRow>

        <SettingRow title="Time format" description="How clock times are shown across the app.">
          <Select
            className="w-52"
            value={timeFormat}
            onValueChange={(v) => setTimeFormat(v as typeof timeFormat)}
            options={TIME_FORMAT_OPTIONS.map((o) => ({ value: o.value, label: o.label }))}
            aria-label="Time format"
          />
        </SettingRow>
      </ContentPanel>
>>>>>>> master
    </div>
  )
}

<<<<<<< HEAD
export const SETTINGS_NAV_ICONS = {
  general: Building2,
  setup: WandSparkles,
  branches: MapPinned,
  staff: Users,
  services: Stethoscope,
  notifications: Bell,
} as const

export function settingsNavItemClass(active: boolean) {
  return cn(
    'focus-ring flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-start text-body transition-colors',
    active
      ? 'bg-surface-selected font-medium text-text-primary'
      : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary',
=======
const NOTIFICATION_ITEMS = [
  {
    key: 'appointmentReminders' as const,
    title: 'Appointment reminders',
    description: 'Upcoming visits, confirmations, and no-show follow-ups.',
  },
  {
    key: 'billingAlerts' as const,
    title: 'Billing alerts',
    description: 'Overdue invoices, payment receipts, and claim status updates.',
  },
  {
    key: 'labResults' as const,
    title: 'Lab results',
    description: 'New results ready for review or patient notification.',
  },
  {
    key: 'shiftHandoffs' as const,
    title: 'Shift handoffs',
    description: 'End-of-shift summaries and open task reminders.',
  },
  {
    key: 'productUpdates' as const,
    title: 'Product updates',
    description: 'New features, maintenance windows, and release notes.',
  },
]

export function NotificationsScreen() {
  const { prefs, setPref } = useNotificationPrefs()

  return (
    <div className="space-y-6">
      <ScreenHeader
        icon={Bell}
        title="Notifications"
        description="Choose which alerts you receive on this workstation. Applies to your account only."
      />

      <ContentPanel>
        <div className="divide-y divide-border-subtle">
          {NOTIFICATION_ITEMS.map((item) => (
            <SettingRow key={item.key} title={item.title} description={item.description}>
              <Switch
                checked={prefs[item.key]}
                onCheckedChange={(checked) => setPref(item.key, checked)}
                aria-label={item.title}
              />
            </SettingRow>
          ))}
        </div>
        <p className="mt-6 text-caption text-text-tertiary">
          Email and SMS delivery channels will be available when connected to your clinic&apos;s
          notification service.
        </p>
      </ContentPanel>
    </div>
  )
}

export function SecurityScreen() {
  const { minutes, setMinutes } = useIdleTimeout()

  return (
    <div className="space-y-6">
      <ScreenHeader
        icon={Shield}
        title="Security"
        description="Protect this workstation when you step away from the desk."
      />

      <ContentPanel>
        <div className="flex items-start gap-3 mb-6">
          <Clock size={20} className="mt-0.5 text-text-link" aria-hidden />
          <div>
            <p className="text-body-strong text-text-primary">Idle sign-out duration</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Applies to this browser workstation.
            </p>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          {IDLE_TIMEOUT_PRESETS.map((preset) => (
            <button
              key={preset}
              type="button"
              onClick={() => setMinutes(preset)}
              className={cn(
                'focus-ring rounded-md border px-4 py-2 text-body-sm font-medium transition-colors',
                minutes === preset
                  ? 'border-action-primary bg-action-primary/10 text-text-link'
                  : 'border-border-default text-text-secondary hover:border-border-strong hover:text-text-primary',
              )}
              aria-pressed={minutes === preset}
            >
              {preset} min
            </button>
          ))}
        </div>

        <p className="mt-6 text-caption text-text-tertiary">
          Current setting: <strong className="text-text-secondary">{minutes} minutes</strong> of
          inactivity before sign-out.
        </p>
      </ContentPanel>
    </div>
>>>>>>> master
  )
}
