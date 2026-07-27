import {
  AlertTriangle,
  ArrowRight,
  Banknote,
  Building2,
  CalendarCheck,
  CalendarPlus,
  CreditCard,
  Landmark,
  ReceiptText,
  ShieldCheck,
  Stethoscope,
  Tag,
  UserRound,
  Wallet,
} from 'lucide-react'
import { motion } from 'motion/react'
import { useMemo, type ReactNode } from 'react'
import { IconButton } from '@/components/actions/IconButton'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { Card } from '@/components/card/Card'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { PageHeader } from '@/components/layout/PageHeader'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { getPatientById, patientFullName } from '@/data/patients'
import {
  discountLabel,
  formatDate,
  formatDateTime,
  getBranchById,
  getInsuranceProviderById,
  getInvoiceById,
  getVisitForInvoice,
  invoiceBalance,
  invoiceStatusColor,
  invoiceStatusLabel,
  netPaidAmount,
  originalDueAmount,
  paymentMethodLabel,
  type Invoice,
  type InvoicePayment,
  type PaymentMethod,
} from '@/data/invoices'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition, staggerChildren } from '@/lib/motion'

export type InvoiceDetailPageProps = {
  invoiceId: string
  onNavigate: (route: string) => void
}

function PerforatedEdge() {
  return (
    <div
      className="pointer-events-none absolute inset-x-0 top-0 h-1.5 opacity-40"
      aria-hidden
      style={{
        backgroundImage:
          'repeating-linear-gradient(90deg, var(--border-default) 0, var(--border-default) 6px, transparent 6px, transparent 12px)',
      }}
    />
  )
}

function MetaItem({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="min-w-0 space-y-1">
      <p className="text-overline text-text-tertiary">{label}</p>
      <div className="truncate text-body-sm text-text-primary">{value}</div>
    </div>
  )
}

function InvoiceSectionTitle({
  icon: Icon,
  title,
}: {
  icon: typeof ReceiptText
  title: string
}) {
  return (
    <div className="flex items-center gap-3">
      <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-surface-selected text-text-link">
        <Icon size={18} strokeWidth={1.75} aria-hidden />
      </span>
      <h2 className="text-body-strong text-text-primary">{title}</h2>
    </div>
  )
}

function LinkCard({
  eyebrow,
  icon: Icon,
  title,
  subtitle,
  badge,
  actionLabel,
  onAction,
}: {
  eyebrow: string
  icon: typeof UserRound
  title: string
  subtitle: string
  badge?: ReactNode
  actionLabel: string
  onAction: () => void
}) {
  return (
    <Card variant="flat" padding="lg" className="rounded-2xl">
      <div className="flex items-center gap-3">
        <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-surface-selected text-text-link">
          <Icon size={18} strokeWidth={1.75} aria-hidden />
        </span>
        <div className="min-w-0 flex-1 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <p className="text-overline text-text-tertiary">{eyebrow}</p>
            {badge}
          </div>
          <p className="truncate text-body-strong text-text-primary">{title}</p>
          <p className="truncate text-body-sm text-text-secondary">{subtitle}</p>
        </div>
        <IconButton
          icon={<ArrowRight size={18} strokeWidth={2} className="rtl:-scale-x-100" />}
          label={actionLabel}
          variant="secondary"
          size="lg"
          onClick={onAction}
          className="shrink-0 rounded-xl"
        />
      </div>
    </Card>
  )
}

function paymentMethodIcon(method: PaymentMethod) {
  switch (method) {
    case 'cash':
      return Banknote
    case 'card':
      return CreditCard
    case 'bank_transfer':
      return Landmark
    case 'insurance_settlement':
      return ShieldCheck
    default:
      return Banknote
  }
}

function PaymentLedgerRow({
  payment,
  currency,
}: {
  payment: InvoicePayment
  currency: string
}) {
  const Icon = paymentMethodIcon(payment.method)
  const isRefund = payment.amount < 0

  return (
    <tr>
      <td className="py-3.5 pe-3">
        <div className="flex items-start gap-2.5">
          <span className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-lg bg-surface-muted text-icon-muted">
            <Icon size={14} strokeWidth={1.75} aria-hidden />
          </span>
          <div className="min-w-0 space-y-0.5">
            <p className="text-text-primary">
              {paymentMethodLabel(payment.method)}
              {isRefund ? (
                <span className="ms-1.5 text-caption text-status-danger-fg">Refund</span>
              ) : null}
            </p>
            {payment.note ? <p className="text-caption text-text-secondary">{payment.note}</p> : null}
          </div>
        </div>
      </td>
      <td className="hidden py-3.5 text-end tabular-nums text-text-secondary sm:table-cell">
        {formatDateTime(payment.recordedAt)}
      </td>
      <td className="hidden py-3.5 text-end text-text-secondary md:table-cell">
        {payment.recordedByName}
      </td>
      <td
        className={cn(
          'py-3.5 text-end tabular-nums',
          isRefund ? 'text-status-danger-fg' : 'text-status-success-fg',
        )}
      >
        <MoneyDisplay
          amount={payment.amount}
          currency={currency}
          negative={isRefund}
        />
      </td>
    </tr>
  )
}

function VoidedNotice({ invoice }: { invoice: Invoice }) {
  return (
    <Card
      variant="flat"
      padding="lg"
      className="rounded-2xl border-status-danger-border bg-status-danger-surface"
    >
      <div className="flex items-start gap-3">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-surface-default text-status-danger-fg">
          <AlertTriangle size={16} strokeWidth={1.75} aria-hidden />
        </span>
        <div className="min-w-0 space-y-1">
          <p className="text-body-strong text-status-danger-fg">This invoice was voided</p>
          <p className="text-body-sm text-text-primary">{invoice.voidReason}</p>
          <p className="text-caption text-text-secondary">
            {invoice.voidedAt ? formatDateTime(invoice.voidedAt) : '—'}
            {invoice.voidedByName ? ` · ${invoice.voidedByName}` : ''}
          </p>
        </div>
      </div>
    </Card>
  )
}

export function InvoiceDetailPage({ invoiceId, onNavigate }: InvoiceDetailPageProps) {
  const invoice = getInvoiceById(invoiceId)
  const patient = invoice ? getPatientById(invoice.patientId) : undefined
  const visit = invoice ? getVisitForInvoice(invoice) : undefined
  const branch = invoice ? getBranchById(invoice.branchId) : undefined
  const insuranceProvider = invoice ? getInsuranceProviderById(invoice.insuranceProviderId) : undefined

  const totals = useMemo(() => {
    if (!invoice) return null
    return {
      due: originalDueAmount(invoice),
      paid: netPaidAmount(invoice),
      balance: invoiceBalance(invoice),
    }
  }, [invoice])

  if (!invoice || !patient) {
    return (
      <div className="space-y-6">
        <PageHeader
          title="Invoice not found"
          breadcrumb={
            <Breadcrumb
              items={[
                { label: 'Invoices', onClick: () => onNavigate('invoices') },
                { label: 'Not found' },
              ]}
            />
          }
        />
        <EmptyState
          variant="error"
          title="Invoice not found"
          description="The invoice you requested does not exist or has been removed."
          action={{ label: 'Back to invoices', onClick: () => onNavigate('invoices') }}
        />
      </div>
    )
  }

  const name = patientFullName(patient)
  const transition = resolveTransition(motionPresets['slide-up'])
  const hasLineDiscounts = invoice.items.some((item) => item.discountAmount > 0)
  const balanceLabel =
    invoice.status === 'voided' ? 'Balance at void' : 'Balance due'

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22 }}
      className="space-y-6"
    >
      <Breadcrumb
        items={[
          { label: 'Invoices', onClick: () => onNavigate('invoices') },
          { label: invoice.invoiceNumber ?? 'Draft invoice' },
        ]}
      />

      <Card variant="raised" padding="lg" className="relative overflow-hidden rounded-2xl !p-0">
        <PerforatedEdge />
        <div className="space-y-5 p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="flex min-w-0 items-start gap-4">
              <Avatar name={name} size="lg" />
              <div className="min-w-0 space-y-1.5">
                <div className="flex flex-wrap items-center gap-2">
                  <h1 className="font-mono text-h1 tracking-[0.02em] text-text-primary">
                    {invoice.invoiceNumber ?? 'Draft invoice'}
                  </h1>
                  <Badge color={invoiceStatusColor(invoice.status)} variant="soft">
                    {invoiceStatusLabel(invoice.status)}
                  </Badge>
                </div>
                <p className="text-body text-text-secondary">
                  Billed to{' '}
                  <button
                    type="button"
                    onClick={() => onNavigate(`patients/${patient.id}`)}
                    className="focus-ring rounded-sm font-medium text-text-link hover:underline"
                  >
                    {name}
                  </button>{' '}
                  <span className="tabular-nums text-text-tertiary">· {patient.mrn}</span>
                </p>
              </div>
            </div>

            <div className="shrink-0 text-end">
              <p className="text-overline text-text-tertiary">
                {invoice.status === 'voided' ? 'Balance at void' : 'Balance due'}
              </p>
              <p className="font-display text-display tabular-nums text-text-primary">
                <MoneyDisplay
                  amount={totals?.balance ?? 0}
                  currency={invoice.currency}
                  emphasis
                  className={cn(
                    (totals?.balance ?? 0) <= 0 && 'text-status-success-fg',
                  )}
                />
              </p>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4 border-t border-border-subtle pt-4 sm:grid-cols-4">
            <MetaItem
              label="Branch"
              value={
                <span className="inline-flex items-center gap-1.5">
                  <Building2 size={14} className="text-icon-muted" aria-hidden />
                  {branch?.name ?? '—'}
                </span>
              }
            />
            <MetaItem label="Created" value={formatDate(invoice.createdAt)} />
            <MetaItem
              label="Issued"
              value={invoice.issuedAt ? formatDate(invoice.issuedAt) : 'Not yet issued'}
            />
            <MetaItem
              label="Insurance"
              value={
                insuranceProvider ? (
                  <span className="inline-flex items-center gap-1.5">
                    <ShieldCheck size={14} className="text-icon-muted" aria-hidden />
                    {insuranceProvider.name}
                  </span>
                ) : (
                  'None on file'
                )
              }
            />
          </div>
        </div>
      </Card>

      {invoice.status === 'voided' ? <VoidedNotice invoice={invoice} /> : null}

      <motion.div
        className="grid gap-4 sm:grid-cols-2"
        initial="hidden"
        animate="visible"
        variants={staggerChildren(60)}
      >
        <motion.div variants={motionPresets['row-enter'].variants} transition={transition}>
          <LinkCard
            eyebrow="Patient"
            icon={UserRound}
            title={name}
            subtitle={`${patient.mrn} · ${patient.phone}`}
            actionLabel="View patient profile"
            onAction={() => onNavigate(`patients/${patient.id}`)}
          />
        </motion.div>

        <motion.div variants={motionPresets['row-enter'].variants} transition={transition}>
          {visit ? (
            <LinkCard
              eyebrow="Visit"
              icon={Stethoscope}
              title={formatDate(visit.date)}
              subtitle={`${visit.doctor} · ${visit.branch}`}
              badge={
                <Badge size="sm" color="success" variant="soft">
                  Completed
                </Badge>
              }
              actionLabel="View visit in patient record"
              onAction={() => onNavigate(`patients/${patient.id}`)}
            />
          ) : (
            <Card variant="flat" padding="lg" className="flex h-full items-center rounded-2xl">
              <div className="flex items-start gap-3">
                <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-surface-muted text-icon-muted">
                  <CalendarPlus size={18} strokeWidth={1.75} aria-hidden />
                </span>
                <p className="text-body-sm text-text-secondary">
                  The source visit for this invoice is no longer available.
                </p>
              </div>
            </Card>
          )}
        </motion.div>
      </motion.div>

      <Card variant="raised" padding="lg" className="overflow-hidden rounded-2xl !p-0">
        <div className="border-b border-border-subtle px-6 py-4">
          <InvoiceSectionTitle icon={ReceiptText} title="Line items" />
        </div>

        <div className="overflow-x-auto px-6 pt-4">
          <table className="w-full text-body-sm">
            <thead>
              <tr className="border-b border-border-subtle text-start text-overline text-text-tertiary">
                <th className="pb-2.5 font-medium">Service</th>
                <th className="hidden pb-2.5 text-end font-medium sm:table-cell">Unit</th>
                <th className="w-16 pb-2.5 text-center font-medium">Qty</th>
                {hasLineDiscounts ? (
                  <th className="hidden pb-2.5 text-end font-medium sm:table-cell">Discount</th>
                ) : null}
                <th className="pb-2.5 text-end font-medium">Amount</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle/70">
              {invoice.items.map((item) => (
                <tr key={item.id}>
                  <td className="py-3.5 pe-3 text-text-primary">{item.description}</td>
                  <td className="hidden py-3.5 text-end tabular-nums text-text-secondary sm:table-cell">
                    <MoneyDisplay amount={item.unitPrice} currency={invoice.currency} />
                  </td>
                  <td className="py-3.5 text-center tabular-nums text-text-secondary">
                    {item.quantity}
                  </td>
                  {hasLineDiscounts ? (
                    <td className="hidden py-3.5 text-end tabular-nums text-status-success-fg sm:table-cell">
                      {item.discountAmount > 0
                        ? discountLabel(item.discountKind, item.discountValue)
                        : '—'}
                    </td>
                  ) : null}
                  <td className="py-3.5 text-end tabular-nums">
                    <MoneyDisplay amount={item.lineTotal} currency={invoice.currency} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="mt-2 border-t border-dashed border-border-default bg-surface-sunken/20 px-6 py-5">
          <dl className="ms-auto max-w-sm space-y-2">
            <div className="flex items-baseline justify-between">
              <dt className="text-body-sm text-text-secondary">Subtotal</dt>
              <dd>
                <MoneyDisplay amount={invoice.subtotal} currency={invoice.currency} />
              </dd>
            </div>
            {invoice.discountAmount > 0 ? (
              <div className="flex items-baseline justify-between text-status-success-fg">
                <dt className="flex items-center gap-1.5 text-body-sm">
                  <Tag size={13} aria-hidden />
                  Invoice discount
                  {invoice.discountKind ? ` (${discountLabel(invoice.discountKind, invoice.discountValue)})` : ''}
                </dt>
                <dd>
                  <MoneyDisplay amount={invoice.discountAmount} currency={invoice.currency} negative />
                </dd>
              </div>
            ) : null}
            {invoice.insuranceCoveredAmount > 0 ? (
              <div className="flex items-baseline justify-between text-status-success-fg">
                <dt className="flex items-center gap-1.5 text-body-sm">
                  <ShieldCheck size={13} aria-hidden />
                  Insurance covered
                  {insuranceProvider ? ` (${insuranceProvider.name})` : ''}
                </dt>
                <dd>
                  <MoneyDisplay
                    amount={invoice.insuranceCoveredAmount}
                    currency={invoice.currency}
                    negative
                  />
                </dd>
              </div>
            ) : null}
            <div className="flex items-baseline justify-between border-t border-border-subtle pt-3">
              <dt className="font-display text-body-strong text-text-primary">Amount due</dt>
              <dd className="font-display text-h2 tabular-nums text-text-primary">
                <MoneyDisplay amount={totals?.due ?? 0} currency={invoice.currency} emphasis />
              </dd>
            </div>
          </dl>
        </div>
      </Card>

      <Card variant="raised" padding="lg" className="overflow-hidden rounded-2xl !p-0">
        <div className="border-b border-border-subtle px-6 py-4">
          <InvoiceSectionTitle icon={Wallet} title="Payments" />
        </div>

        {invoice.payments.length > 0 ? (
          <div className="overflow-x-auto px-6 pt-4">
            <table className="w-full text-body-sm">
              <thead>
                <tr className="border-b border-border-subtle text-start text-overline text-text-tertiary">
                  <th className="pb-2.5 font-medium">Payment</th>
                  <th className="hidden pb-2.5 text-end font-medium sm:table-cell">Recorded</th>
                  <th className="hidden pb-2.5 text-end font-medium md:table-cell">By</th>
                  <th className="pb-2.5 text-end font-medium">Amount</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle/70">
                {invoice.payments.map((payment) => (
                  <PaymentLedgerRow
                    key={payment.id}
                    payment={payment}
                    currency={invoice.currency}
                  />
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="px-6 py-8">
            <EmptyState
              variant="first-run"
              title="No payments yet"
              description={
                invoice.status === 'draft'
                  ? 'Issue this invoice before recording a payment.'
                  : 'Payments recorded against this invoice will appear here.'
              }
            />
          </div>
        )}

        <div className="mt-2 border-t border-dashed border-border-default bg-surface-sunken/20 px-6 py-5">
          <dl className="ms-auto max-w-sm space-y-2">
            <div className="flex items-baseline justify-between">
              <dt className="text-body-sm text-text-secondary">Amount due</dt>
              <dd className="tabular-nums text-text-primary">
                <MoneyDisplay amount={totals?.due ?? 0} currency={invoice.currency} emphasis />
              </dd>
            </div>
            {invoice.payments.length > 0 ? (
              <div className="flex items-baseline justify-between">
                <dt className="text-body-sm text-text-secondary">Net paid</dt>
                <dd className="tabular-nums text-text-primary">
                  <MoneyDisplay amount={totals?.paid ?? 0} currency={invoice.currency} />
                </dd>
              </div>
            ) : null}
            <div className="flex items-baseline justify-between border-t border-border-subtle pt-3">
              <dt className="font-display text-body-strong text-text-primary">{balanceLabel}</dt>
              <dd
                className={cn(
                  'font-display text-h2 tabular-nums',
                  (totals?.balance ?? 0) <= 0 ? 'text-status-success-fg' : 'text-text-primary',
                )}
              >
                <MoneyDisplay
                  amount={totals?.balance ?? 0}
                  currency={invoice.currency}
                  emphasis
                />
              </dd>
            </div>
          </dl>
        </div>
      </Card>

      <Card variant="flat" padding="md" className="rounded-xl border border-border-subtle">
        <div className="flex items-start gap-3">
          <CalendarCheck size={16} className="mt-0.5 shrink-0 text-icon-muted" aria-hidden />
          <p className="text-caption text-text-secondary">
            Last updated {formatDateTime(invoice.updatedAt)}. Every invoice is tied to exactly one
            completed visit — the balance above is recomputed from the line items, discounts,
            insurance coverage, and payment ledger shown here.
          </p>
        </div>
      </Card>
    </motion.div>
  )
}
