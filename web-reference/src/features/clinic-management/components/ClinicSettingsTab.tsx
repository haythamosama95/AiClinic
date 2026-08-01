import { motion } from 'motion/react'
import { CreditCard } from 'lucide-react'
import { Switch } from '@/components/ui/switch/Switch'
import { useBillingSettings } from '../hooks/useBillingSettings'

export function ClinicSettingsTab() {
  const { settings, updateSettings } = useBillingSettings()

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22 }}
      className="space-y-6"
    >
      <div className="max-w-xl space-y-1">
        <h3 className="font-[family-name:var(--font-display)] text-h3 text-text-primary">
          Clinic settings
        </h3>
        <p className="text-body-sm text-text-secondary">
          Organization-wide billing and invoicing behavior for all branches.
        </p>
      </div>

      <div className="rounded-2xl border border-border-subtle bg-surface-default p-6 shadow-elevation-1">
        <div className="flex items-start gap-3 mb-6">
          <div className="flex size-10 shrink-0 items-center justify-center rounded-lg border border-border-subtle bg-surface-sunken text-icon-muted">
            <CreditCard size={20} strokeWidth={1.5} aria-hidden />
          </div>
          <div>
            <p className="text-body-strong text-text-primary">Billing</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Control how patient payments are recorded against invoices.
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-start justify-between gap-4 rounded-xl border border-border-subtle bg-surface-sunken/40 p-4">
          <div className="max-w-xl">
            <p className="text-body-strong text-text-primary">Allow partial payments</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              When enabled, staff can record payments that do not cover the full invoice balance.
              When disabled, each payment must settle the remaining amount in full.
            </p>
          </div>
          <Switch
            id="allow-partial-payments"
            checked={settings.allowPartialPayments}
            onCheckedChange={(allowPartialPayments) => updateSettings({ allowPartialPayments })}
            aria-label="Allow partial payments"
          />
        </div>
      </div>
    </motion.div>
  )
}
