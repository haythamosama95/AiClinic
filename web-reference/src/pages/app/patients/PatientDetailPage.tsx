import {
  Building2,
  Download,
  Mail,
  MapPin,
  Phone,
} from 'lucide-react'
import { motion } from 'motion/react'
import { useMemo, useState, type ReactNode } from 'react'
import { Button } from '@/components/actions/Button'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { Card } from '@/components/card/Card'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { PageHeader } from '@/components/layout/PageHeader'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { Tabs } from '@/components/navigation/Tabs'
import { Skeleton } from '@/components/skeleton/Skeleton'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition, staggerChildren } from '@/lib/motion'
import {
  downloadPatientDocument,
  formatDate,
  formatFileSize,
  getDocumentsForPatient,
  getInvoicesForPatient,
  getPatientById,
  getVisitById,
  getVisitsForPatient,
  invoiceStatusColor,
  patientFullName,
  patientStatusColor,
  type PatientDocument,
  type PatientInvoice,
  type PatientVisit,
} from '@/data/patients'

type DateStamp = {
  day: number
  month: string
  year: number
  weekday: string
}

type InvoiceDueMeta = {
  label: string
  urgent: boolean
}

const INVOICE_STATUS_BAND: Record<
  PatientInvoice['status'],
  { band: string; accent: string }
> = {
  paid: {
    band: 'border-status-success-border bg-status-success-surface',
    accent: 'text-status-success-fg',
  },
  sent: {
    band: 'border-status-warning-border bg-status-warning-surface',
    accent: 'text-status-warning-fg',
  },
  overdue: {
    band: 'border-status-danger-border bg-status-danger-surface',
    accent: 'text-status-danger-fg',
  },
  draft: {
    band: 'border-border-subtle bg-surface-muted',
    accent: 'text-text-secondary',
  },
  cancelled: {
    band: 'border-border-subtle bg-surface-sunken',
    accent: 'text-text-tertiary',
  },
}

function toDateStamp(iso: string): DateStamp {
  const date = new Date(`${iso}T00:00:00`)
  return {
    day: date.getDate(),
    month: date.toLocaleDateString('en-GB', { month: 'short' }).toUpperCase(),
    year: date.getFullYear(),
    weekday: date.toLocaleDateString('en-GB', { weekday: 'long' }),
  }
}

function practitionerInitials(name: string): string {
  const parts = name.replace(/^Dr\.\s*/i, '').trim().split(/\s+/)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return `${parts[0][0] ?? ''}${parts[parts.length - 1][0] ?? ''}`.toUpperCase()
}

function invoiceDueMeta(invoice: PatientInvoice): InvoiceDueMeta {
  if (invoice.status === 'paid' || invoice.status === 'cancelled') {
    return { label: `Due ${formatDate(invoice.dueDate)}`, urgent: false }
  }

  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const due = new Date(`${invoice.dueDate}T00:00:00`)
  const diffDays = Math.round((due.getTime() - today.getTime()) / (1000 * 60 * 60 * 24))

  if (invoice.status === 'overdue' || diffDays < 0) {
    const overdueDays = Math.abs(diffDays)
    return {
      label: overdueDays === 1 ? '1 day overdue' : `${overdueDays} days overdue`,
      urgent: true,
    }
  }
  if (diffDays === 0) return { label: 'Due today', urgent: true }
  if (diffDays <= 7) {
    return { label: diffDays === 1 ? 'Due tomorrow' : `Due in ${diffDays} days`, urgent: true }
  }
  return { label: `Due ${formatDate(invoice.dueDate)}`, urgent: false }
}

function RecordCardGrid({ children }: { children: ReactNode }) {
  return (
    <motion.div
      className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3"
      initial="hidden"
      animate="visible"
      variants={staggerChildren(45)}
    >
      {children}
    </motion.div>
  )
}

function RecordCardShell({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <motion.article
      variants={motionPresets['row-enter'].variants}
      transition={resolveTransition(motionPresets['row-enter'])}
      className={cn(
        'group h-full overflow-hidden rounded-2xl border border-border-subtle',
        'bg-[linear-gradient(165deg,var(--surface-default)_0%,color-mix(in_srgb,var(--color-teal-50)_28%,var(--surface-default))_100%)]',
        'shadow-elevation-1 transition-[box-shadow,transform,border-color] duration-[var(--duration-base)]',
        'hover:-translate-y-0.5 hover:border-border-default hover:shadow-elevation-2',
        'motion-reduce:transform-none motion-reduce:transition-none',
        className,
      )}
    >
      {children}
    </motion.article>
  )
}

export type PatientDetailPageProps = {
  patientId: string
  onNavigate: (route: string) => void
}

const TAB_ITEMS = [
  { id: 'visits', label: 'Visits' },
  { id: 'documents', label: 'Documents' },
  { id: 'billing', label: 'Billing' },
]

function VisitCard({ visit }: { visit: PatientVisit }) {
  const stamp = toDateStamp(visit.date)

  return (
    <RecordCardShell>
      <div className="flex h-full min-h-[9.5rem]">
        <div
          className={cn(
            'flex w-[5.25rem] shrink-0 flex-col items-center justify-center gap-0.5',
            'border-e border-border-subtle bg-[linear-gradient(180deg,color-mix(in_srgb,var(--color-teal-100)_55%,var(--surface-default))_0%,color-mix(in_srgb,var(--color-teal-50)_80%,var(--surface-default))_100%)]',
            'px-2 py-5 text-center',
          )}
          aria-hidden
        >
          <span className="font-display text-[2rem] leading-none font-semibold tabular-nums text-text-primary">
            {stamp.day}
          </span>
          <span className="text-overline tracking-[0.14em] text-text-secondary">{stamp.month}</span>
          <span className="text-caption tabular-nums text-text-tertiary">{stamp.year}</span>
        </div>

        <div className="flex min-w-0 flex-1 flex-col justify-between gap-5 p-5">
          <div className="space-y-3">
            <p className="text-overline text-text-tertiary">{stamp.weekday}</p>
            <div className="flex items-start gap-3">
              <div
                className={cn(
                  'flex size-10 shrink-0 items-center justify-center rounded-full',
                  'border border-border-subtle bg-surface-default font-mono text-caption font-medium text-text-secondary',
                  'shadow-elevation-0',
                )}
                aria-hidden
              >
                {practitionerInitials(visit.doctor)}
              </div>
              <div className="min-w-0 space-y-1">
                <p className="text-body-strong text-text-primary">{visit.doctor}</p>
                <p className="text-caption text-text-tertiary">Attending physician</p>
              </div>
            </div>
          </div>

          <div className="inline-flex w-fit max-w-full items-center gap-2 rounded-full border border-border-subtle bg-surface-default/80 px-3 py-1.5 text-body-sm text-text-secondary backdrop-blur-[2px]">
            <Building2 size={14} className="shrink-0 text-icon-muted" aria-hidden />
            <span className="truncate">{visit.branch}</span>
          </div>
        </div>
      </div>
    </RecordCardShell>
  )
}

function InvoiceCard({ invoice }: { invoice: PatientInvoice }) {
  const statusTheme = INVOICE_STATUS_BAND[invoice.status]
  const dueMeta = invoiceDueMeta(invoice)

  return (
    <RecordCardShell>
      <div
        className={cn(
          'flex items-center justify-between gap-3 border-b px-5 py-3',
          statusTheme.band,
        )}
      >
        <p className="truncate font-mono text-caption uppercase tracking-[0.08em] text-text-secondary">
          {invoice.number}
        </p>
        <Badge color={invoiceStatusColor(invoice.status)} variant="soft">
          {invoice.status.charAt(0).toUpperCase() + invoice.status.slice(1)}
        </Badge>
      </div>

      <div className="space-y-5 p-5">
        <div className="space-y-1">
          <p className="text-overline text-text-tertiary">Balance</p>
          <p className="font-display text-display tabular-nums text-text-primary">
            <MoneyDisplay amount={invoice.total} emphasis />
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3 border-t border-border-subtle/80 pt-4">
          <div className="space-y-1">
            <p className="text-overline text-text-tertiary">Issued</p>
            <p className="text-body-sm tabular-nums text-text-primary">{formatDate(invoice.date)}</p>
          </div>
          <div className="space-y-1 text-end">
            <p className="text-overline text-text-tertiary">Payment</p>
            <p
              className={cn(
                'text-body-sm tabular-nums',
                dueMeta.urgent ? statusTheme.accent : 'text-text-primary',
              )}
            >
              {dueMeta.label}
            </p>
          </div>
        </div>
      </div>
    </RecordCardShell>
  )
}

function documentExtension(name: string, fallback: string): string {
  const match = name.match(/\.([^.]+)$/)
  return (match?.[1] ?? fallback).toUpperCase()
}

function DocumentCard({ document }: { document: PatientDocument }) {
  const visit = getVisitById(document.visitId)
  const extension = documentExtension(document.name, document.fileType)
  const visitStamp = visit ? toDateStamp(visit.date) : null

  return (
    <RecordCardShell
      className={cn(
        'bg-[linear-gradient(165deg,var(--surface-default)_0%,color-mix(in_srgb,var(--color-neutral-100)_55%,var(--surface-default))_100%)]',
      )}
    >
      <div className="flex h-full min-h-[11rem] flex-col">
        <div className="flex min-h-0 flex-1">
          <div
            className={cn(
              'flex w-[5.25rem] shrink-0 flex-col items-center justify-center gap-1',
              'border-e border-border-subtle bg-[linear-gradient(180deg,var(--surface-muted)_0%,var(--surface-sunken)_100%)]',
              'px-2 py-5 text-center',
            )}
            aria-hidden
          >
            <span className="font-mono text-[1.125rem] leading-none font-semibold tracking-[0.06em] text-text-primary">
              {extension}
            </span>
            <span className="text-caption tabular-nums text-text-tertiary">
              {formatFileSize(document.sizeBytes)}
            </span>
          </div>

          <div className="flex min-w-0 flex-1 flex-col gap-4 p-5">
            <div className="space-y-1">
              <p className="text-overline text-text-tertiary">Patient file</p>
              <p className="line-clamp-2 text-body-strong text-text-primary">{document.name}</p>
            </div>

            <div className="rounded-xl border border-border-subtle/90 bg-surface-sunken/70 p-3">
              <p className="text-overline text-text-tertiary">Linked visit</p>
              {visit && visitStamp ? (
                <div className="mt-2 flex items-start gap-3">
                  <div
                    className={cn(
                      'flex w-11 shrink-0 flex-col items-center rounded-md border border-border-subtle',
                      'bg-surface-default px-1.5 py-1.5 text-center',
                    )}
                    aria-hidden
                  >
                    <span className="font-display text-body-strong leading-none tabular-nums text-text-primary">
                      {visitStamp.day}
                    </span>
                    <span className="mt-0.5 text-[0.625rem] font-medium tracking-[0.12em] text-text-tertiary uppercase">
                      {visitStamp.month}
                    </span>
                  </div>
                  <div className="min-w-0 space-y-1">
                    <p className="truncate text-body-sm text-text-primary">{visit.doctor}</p>
                    <p className="inline-flex max-w-full items-center gap-1.5 text-caption text-text-secondary">
                      <Building2 size={12} className="shrink-0 text-icon-muted" aria-hidden />
                      <span className="truncate">{visit.branch}</span>
                    </p>
                  </div>
                </div>
              ) : (
                <p className="mt-2 text-body-sm text-text-secondary">Visit link unavailable</p>
              )}
            </div>
          </div>
        </div>

        <div className="border-t border-border-subtle/80 px-5 py-3">
          <Button
            variant="secondary"
            size="sm"
            className="w-full"
            leadingIcon={<Download size={15} />}
            onClick={() => downloadPatientDocument(document, visit)}
          >
            Download file
          </Button>
        </div>
      </div>
    </RecordCardShell>
  )
}

export function PatientDetailPage({ patientId, onNavigate }: PatientDetailPageProps) {
  const [tab, setTab] = useState('visits')
  const patient = getPatientById(patientId)
  const visits = useMemo(
    () => (patient ? getVisitsForPatient(patient.id) : []),
    [patient],
  )
  const documents = useMemo(
    () => (patient ? getDocumentsForPatient(patient.id) : []),
    [patient],
  )
  const invoices = useMemo(
    () => (patient ? getInvoicesForPatient(patient.id) : []),
    [patient],
  )

  if (!patient) {
    return (
      <div className="space-y-6">
        <PageHeader
          title="Patient not found"
          breadcrumb={
            <Breadcrumb
              items={[
                { label: 'Patients', onClick: () => onNavigate('patients') },
                { label: 'Not found' },
              ]}
            />
          }
        />
        <EmptyState
          variant="error"
          title="Patient not found"
          description="The patient record you requested does not exist or has been removed."
          action={{ label: 'Back to patients', onClick: () => onNavigate('patients') }}
        />
      </div>
    )
  }

  const name = patientFullName(patient)

  return (
    <div className="space-y-6">
      <div className="space-y-4">
        <Breadcrumb
          items={[
            { label: 'Patients', onClick: () => onNavigate('patients') },
            { label: name },
          ]}
        />

        <Card variant="raised" padding="lg" className="overflow-hidden !p-0">
          <div className="space-y-4 p-6">
            <div className="flex min-w-0 items-start gap-4">
              <Avatar name={name} size="xl" />
              <div className="min-w-0 flex-1 space-y-3">
                <div className="flex flex-wrap items-center gap-3">
                  <h1 className="text-h1 text-text-primary">{name}</h1>
                  <Badge color={patientStatusColor(patient.status)} variant="soft">
                    {patient.status.charAt(0).toUpperCase() + patient.status.slice(1)}
                  </Badge>
                </div>
                <p className="text-body text-text-secondary">
                  {patient.mrn} · {patient.gender} · DOB{' '}
                  <span className="tabular-nums">{formatDate(patient.dateOfBirth)}</span>
                </p>
                <div className="flex flex-wrap gap-x-4 gap-y-2 text-body-sm text-text-secondary">
                  <span className="inline-flex items-center gap-1.5">
                    <Phone size={14} className="text-icon-muted" aria-hidden />
                    <span className="tabular-nums">{patient.phone}</span>
                  </span>
                  <span className="inline-flex items-center gap-1.5">
                    <Mail size={14} className="text-icon-muted" aria-hidden />
                    {patient.email}
                  </span>
                  <span className="inline-flex items-center gap-1.5">
                    <MapPin size={14} className="text-icon-muted" aria-hidden />
                    {patient.address}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div className="border-t border-border-subtle px-6">
            <Tabs
              items={TAB_ITEMS}
              value={tab}
              onChange={setTab}
              aria-label="Patient sections"
              className="border-b-0"
            />
          </div>
        </Card>
      </div>

      {tab === 'visits' ? (
        visits.length > 0 ? (
          <RecordCardGrid>
            {visits.map((visit) => (
              <VisitCard key={visit.id} visit={visit} />
            ))}
          </RecordCardGrid>
        ) : (
          <EmptyState
            variant="first-run"
            title="No visits yet"
            description="This patient has no recorded visits."
          />
        )
      ) : null}

      {tab === 'documents' ? (
        documents.length > 0 ? (
          <RecordCardGrid>
            {documents.map((document) => (
              <DocumentCard key={document.id} document={document} />
            ))}
          </RecordCardGrid>
        ) : (
          <EmptyState
            variant="first-run"
            title="No documents"
            description="No documents have been uploaded for this patient yet."
          />
        )
      ) : null}

      {tab === 'billing' ? (
        invoices.length > 0 ? (
          <RecordCardGrid>
            {invoices.map((invoice) => (
              <InvoiceCard key={invoice.id} invoice={invoice} />
            ))}
          </RecordCardGrid>
        ) : (
          <EmptyState
            variant="first-run"
            title="No invoices"
            description="No billing records for this patient."
          />
        )
      ) : null}
    </div>
  )
}

/** Loading skeleton for future async data */
export function PatientDetailSkeleton() {
  return (
    <div className="space-y-6">
      <Skeleton className="h-24 w-full rounded-lg" />
      <Skeleton className="h-32 w-full rounded-lg" />
      <Skeleton className="h-96 w-full rounded-lg" />
    </div>
  )
}
