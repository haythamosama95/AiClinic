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
    </div>
  )
}

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
    </div>
  )
}

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
  )
}
