import { ArrowLeft, CheckCircle2, Percent, Receipt, Tag } from 'lucide-react'
import { useMemo } from 'react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge/Badge'
import { Card } from '@/components/card/Card'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { FormField } from '@/components/ui/form-field/FormField'
import { MoneyField } from '@/components/ui/money-field/MoneyField'
import { NumberInput } from '@/components/ui/number-input/NumberInput'
import { RadioGroup } from '@/components/ui/radio-group/RadioGroup'
import type { Patient } from '@/data/patients'
import { patientFullName } from '@/data/patients'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition } from '@/lib/motion'
import type { DiscountType, SelectedServiceLine } from './types'
import { computeInvoiceTotals, lineTotal } from './types'

export type InvoiceReviewStepProps = {
  patient: Patient
  invoiceNumber: string
  lines: SelectedServiceLine[]
  discountType: DiscountType
  discountValue: number
  onDiscountTypeChange: (type: DiscountType) => void
  onDiscountValueChange: (value: number) => void
  onBack: () => void
  onFinalize: () => void
}

const DISCOUNT_OPTIONS = [
  { value: 'none', label: 'No discount' },
  { value: 'percentage', label: 'Percentage off' },
  { value: 'fixed', label: 'Fixed amount off' },
] as const

function MetaDot() {
  return (
    <span className="px-2 text-text-tertiary" aria-hidden>
      ·
    </span>
  )
}

function InvoiceDocumentHeader({
  patient,
  invoiceNumber,
  issuedDate,
}: {
  patient: Patient
  invoiceNumber: string
  issuedDate: string
}) {
  const name = patientFullName(patient)

  return (
    <div className="border-b border-border-subtle px-6 py-5 sm:px-8">
      <div className="flex items-center justify-between gap-3">
        <p className="text-body-sm text-text-secondary">
          <span className="font-medium text-text-primary">Review invoice</span>
          <MetaDot />
          <span className="text-text-tertiary">Step 2 of 2</span>
        </p>
        <Badge color="warning" variant="soft" className="shrink-0">
          Draft
        </Badge>
      </div>

      <div className="mt-5 flex gap-4">
        <Avatar size="lg" name={name} className="shrink-0" />

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            <h2 className="font-display text-h2 text-text-primary">{name}</h2>
            <p className="shrink-0 font-mono text-body-sm uppercase tracking-[0.08em] text-text-primary">
              {invoiceNumber}
            </p>
          </div>

          <div className="mt-2 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-body-sm text-text-secondary">
              <span className="font-mono tabular-nums">{patient.mrn}</span>
              {patient.phone ? (
                <>
                  <MetaDot />
                  <span className="tabular-nums">{patient.phone}</span>
                </>
              ) : null}
            </p>
            <p className="text-body-sm tabular-nums text-text-secondary sm:text-end">{issuedDate}</p>
          </div>
        </div>
      </div>
    </div>
  )
}

export function InvoiceReviewStep({
  patient,
  invoiceNumber,
  lines,
  discountType,
  discountValue,
  onDiscountTypeChange,
  onDiscountValueChange,
  onBack,
  onFinalize,
}: InvoiceReviewStepProps) {
  const totals = useMemo(
    () => computeInvoiceTotals(lines, discountType, discountValue),
    [lines, discountType, discountValue],
  )

  const transition = resolveTransition(motionPresets['slide-up'])
  const today = new Date().toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })

  return (
    <>
      <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={transition}
        >
          <Card
            variant="raised"
            padding="sm"
            className="relative overflow-hidden rounded-2xl p-0"
          >
            {/* Perforated receipt edge — signature visual */}
            <div
              className="pointer-events-none absolute inset-x-0 top-0 h-1.5 opacity-40"
              aria-hidden
              style={{
                backgroundImage:
                  'repeating-linear-gradient(90deg, var(--border-default) 0, var(--border-default) 6px, transparent 6px, transparent 12px)',
              }}
            />

            <InvoiceDocumentHeader
              patient={patient}
              invoiceNumber={invoiceNumber}
              issuedDate={today}
            />

            <div className="px-6 py-5 sm:px-8">
              <table className="w-full text-body-sm">
                <thead>
                  <tr className="border-b border-border-subtle text-start text-overline text-text-tertiary">
                    <th className="pb-2.5 font-medium">Service</th>
                    <th className="hidden pb-2.5 text-end font-medium sm:table-cell">Unit</th>
                    <th className="pb-2.5 text-center font-medium w-16">Qty</th>
                    <th className="pb-2.5 text-end font-medium">Amount</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle/70">
                  {lines.map((line) => (
                    <tr key={line.id}>
                      <td className="py-3.5 pe-3 text-text-primary">{line.name}</td>
                      <td className="hidden py-3.5 text-end tabular-nums text-text-secondary sm:table-cell">
                        <MoneyDisplay amount={line.unitPrice} />
                      </td>
                      <td className="py-3.5 text-center tabular-nums text-text-secondary">
                        {line.quantity}
                      </td>
                      <td className="py-3.5 text-end tabular-nums">
                        <MoneyDisplay amount={lineTotal(line)} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="border-t border-dashed border-border-default bg-surface-sunken/20 px-6 py-5 sm:px-8">
              <dl className="space-y-2">
                <div className="flex items-baseline justify-between">
                  <dt className="text-body-sm text-text-secondary">Subtotal</dt>
                  <dd>
                    <MoneyDisplay amount={totals.subtotal} />
                  </dd>
                </div>
                {totals.discountAmount > 0 ? (
                  <div className="flex items-baseline justify-between text-status-success-fg">
                    <dt className="flex items-center gap-1.5 text-body-sm">
                      <Tag size={13} aria-hidden />
                      Discount
                      {discountType === 'percentage' ? ` (${discountValue}%)` : null}
                    </dt>
                    <dd>
                      <MoneyDisplay amount={totals.discountAmount} negative />
                    </dd>
                  </div>
                ) : null}
                <div className="flex items-baseline justify-between border-t border-border-subtle pt-3">
                  <dt className="font-display text-body-strong text-text-primary">Total due</dt>
                  <dd className="font-display text-h2 tabular-nums text-text-primary">
                    <MoneyDisplay amount={totals.total} emphasis />
                  </dd>
                </div>
              </dl>
            </div>
          </Card>
        </motion.div>

        <motion.aside
          initial={{ opacity: 0, x: 12 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ ...transition, delay: 0.05 }}
          className="space-y-4 lg:sticky lg:top-6 lg:self-start"
        >
          <Card variant="raised" padding="lg" className="rounded-2xl">
            <div className="flex items-center gap-3">
              <span className="flex size-10 items-center justify-center rounded-xl bg-[var(--color-amber-50)] text-[var(--color-amber-600)]">
                <Percent size={18} strokeWidth={1.75} aria-hidden />
              </span>
              <div>
                <p className="text-overline text-text-tertiary">Discount</p>
                <p className="text-body-sm text-text-secondary">Optional adjustment</p>
              </div>
            </div>

            <div className="mt-5 space-y-4 border-t border-border-subtle pt-5">
              <FormField id="discount-type" label="Discount type">
                <RadioGroup
                  value={discountType}
                  onValueChange={(v) => onDiscountTypeChange(v as DiscountType)}
                  options={[...DISCOUNT_OPTIONS]}
                />
              </FormField>

              {discountType === 'percentage' ? (
                <FormField
                  id="discount-percent"
                  label="Percentage"
                  hint="Applied to subtotal before tax"
                >
                  <div className="relative">
                    <NumberInput
                      id="discount-percent"
                      min={0}
                      max={100}
                      step={1}
                      value={discountValue}
                      onValueChange={(v) => onDiscountValueChange(v ?? 0)}
                      className="pe-10"
                    />
                    <span
                      className="pointer-events-none absolute end-3 top-1/2 -translate-y-1/2 text-body-sm text-text-tertiary"
                      aria-hidden
                    >
                      %
                    </span>
                  </div>
                </FormField>
              ) : null}

              {discountType === 'fixed' ? (
                <FormField id="discount-fixed" label="Amount off">
                  <MoneyField
                    id="discount-fixed"
                    value={discountValue}
                    onValueChange={(v) => onDiscountValueChange(v ?? 0)}
                  />
                </FormField>
              ) : null}
            </div>
          </Card>

          <Card variant="flat" padding="md" className="rounded-xl border border-border-subtle">
            <div className="flex items-start gap-3">
              <Receipt size={16} className="mt-0.5 shrink-0 text-icon-muted" aria-hidden />
              <p className="text-caption text-text-secondary">
                Finalizing issues the invoice linked to this visit. Payment can be recorded
                from the patient billing tab.
              </p>
            </div>
          </Card>
        </motion.aside>
      </div>

      <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
        <Button variant="secondary" leadingIcon={<ArrowLeft size={16} />} onClick={onBack}>
          Edit services
        </Button>
        <Button
          variant="primary"
          trailingIcon={<CheckCircle2 size={16} />}
          onClick={onFinalize}
          className={cn(totals.total > 0 && 'shadow-[0_0_0_1px_var(--action-primary)]')}
        >
          Finalize visit &amp; invoice
        </Button>
      </div>
    </>
  )
}
