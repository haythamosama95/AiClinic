import {
  Bell,
  Clock,
  Download,
  Globe,
  Keyboard,
  Palette,
  Printer,
  Shield,
} from 'lucide-react'
import { useState } from 'react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { Button } from '@/components/actions/Button'
import { FormField } from '@/components/ui/form-field/FormField'
import { Select } from '@/components/ui/select/Select'
import { Switch } from '@/components/ui/switch/Switch'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { Textarea } from '@/components/ui/textarea/Textarea'
import {
  DATE_FORMAT_OPTIONS,
  IDLE_TIMEOUT_MAX,
  IDLE_TIMEOUT_MIN,
  IDLE_TIMEOUT_PRESETS,
  TIME_FORMAT_OPTIONS,
} from '@/data/settings'
import { cn } from '@/lib/cn'
import { useDirection, type Locale } from '@/providers/DirectionProvider'
import { useTheme, type ThemePreference } from '@/providers/ThemeProvider'
import {
  useFormatPreferences,
  useIdleTimeout,
  useKeyboardShortcuts,
  useNotificationPrefs,
  usePrintDefaults,
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
    </div>
  )
}

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

function SettingDivider() {
  return <div className="border-t border-border-subtle" aria-hidden />
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
    </div>
  )
}

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
  const { enabled: shortcutsEnabled, setEnabled: setShortcutsEnabled } = useKeyboardShortcuts()
  const [customValue, setCustomValue] = useState('')
  const [showCustom, setShowCustom] = useState(
    () => !IDLE_TIMEOUT_PRESETS.includes(minutes as (typeof IDLE_TIMEOUT_PRESETS)[number]),
  )

  const applyCustom = () => {
    const parsed = Number.parseInt(customValue, 10)
    if (!Number.isNaN(parsed)) {
      setMinutes(parsed)
    }
  }

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
              Applies to this browser workstation. Range: {IDLE_TIMEOUT_MIN}–{IDLE_TIMEOUT_MAX}{' '}
              minutes.
            </p>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          {IDLE_TIMEOUT_PRESETS.map((preset) => (
            <button
              key={preset}
              type="button"
              onClick={() => {
                setMinutes(preset)
                setShowCustom(false)
              }}
              className={cn(
                'focus-ring rounded-md border px-4 py-2 text-body-sm font-medium transition-colors',
                minutes === preset && !showCustom
                  ? 'border-action-primary bg-action-primary/10 text-text-link'
                  : 'border-border-default text-text-secondary hover:border-border-strong hover:text-text-primary',
              )}
              aria-pressed={minutes === preset && !showCustom}
            >
              {preset} min
            </button>
          ))}
          <button
            type="button"
            onClick={() => setShowCustom(true)}
            className={cn(
              'focus-ring rounded-md border px-4 py-2 text-body-sm font-medium transition-colors',
              showCustom
                ? 'border-action-primary bg-action-primary/10 text-text-link'
                : 'border-border-default text-text-secondary hover:border-border-strong hover:text-text-primary',
            )}
            aria-pressed={showCustom}
          >
            Custom
          </button>
        </div>

        {showCustom ? (
          <div className="mt-4 flex flex-wrap items-end gap-3">
            <FormField id="idle-custom" label="Custom minutes" className="w-32">
              <TextInput
                id="idle-custom"
                type="number"
                min={IDLE_TIMEOUT_MIN}
                max={IDLE_TIMEOUT_MAX}
                value={customValue || String(minutes)}
                onChange={(e) => setCustomValue(e.target.value)}
              />
            </FormField>
            <Button variant="secondary" onClick={applyCustom}>
              Apply
            </Button>
          </div>
        ) : null}

        <p className="mt-6 text-caption text-text-tertiary">
          Current setting: <strong className="text-text-secondary">{minutes} minutes</strong> of
          inactivity before sign-out.
        </p>
      </ContentPanel>

      <ContentPanel>
        <SettingRow
          title="Keyboard shortcuts"
          description="Use quick keys for navigation and common actions across the app."
        >
          <div className="flex items-center gap-2">
            <Keyboard size={16} className="text-icon-muted" aria-hidden />
            <Switch
              checked={shortcutsEnabled}
              onCheckedChange={setShortcutsEnabled}
              aria-label="Enable keyboard shortcuts"
            />
          </div>
        </SettingRow>
      </ContentPanel>
    </div>
  )
}

export function PrintingScreen() {
  const { defaults, setReceiptFooter, setIncludeClinicLogo } = usePrintDefaults()

  return (
    <div className="space-y-6">
      <ScreenHeader
        icon={Printer}
        title="Printing"
        description="Set defaults for receipts and printed documents from this workstation."
      />

      <ContentPanel className="space-y-6">
        <FormField
          id="receipt-footer"
          label="Receipt footer text"
          hint="Appears at the bottom of printed receipts and payment confirmations."
        >
          <Textarea
            id="receipt-footer"
            rows={3}
            value={defaults.receiptFooter}
            onChange={(e) => setReceiptFooter(e.target.value)}
            placeholder="Thank you for choosing our clinic."
          />
        </FormField>

        <SettingDivider />

        <SettingRow
          title="Include clinic logo"
          description="Print your organization logo on receipts and invoices."
        >
          <Switch
            checked={defaults.includeClinicLogo}
            onCheckedChange={setIncludeClinicLogo}
            aria-label="Include clinic logo on prints"
          />
        </SettingRow>
      </ContentPanel>
    </div>
  )
}

export function PrivacyScreen() {
  return (
    <div className="space-y-6">
      <ScreenHeader
        icon={Globe}
        title="Privacy"
        description="Manage your personal data and export options."
      />

      <ContentPanel>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0">
            <p className="text-body-strong text-text-primary">Export your data</p>
            <p className="mt-1 max-w-xl text-body-sm text-text-secondary">
              Request a copy of your account activity, preferences, and audit history. Exports are
              prepared by your clinic administrator and delivered securely.
            </p>
          </div>
          <Button variant="secondary" disabled className="shrink-0">
            <Download size={16} className="me-2" aria-hidden />
            Request export
          </Button>
        </div>

        <p className="mt-6 rounded-lg border border-border-subtle bg-surface-muted/60 px-4 py-3 text-caption text-text-tertiary">
          Data export requests require administrator approval. Contact your clinic admin if you need
          immediate access to your records.
        </p>
      </ContentPanel>
    </div>
  )
}
