import type { ReactNode } from 'react'
import { ArrowLeft, CheckCircle2, FileText } from 'lucide-react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { Card } from '@/components/card/Card'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition, staggerChildren } from '@/lib/motion'
import {
<<<<<<< HEAD
=======
  getAllergyById,
  getChronicConditionById,
  getCurrentMedicationById,
>>>>>>> master
  getDurationLabel,
  getFrequencyLabel,
  getInvestigationLabel,
  getMedicationLabel,
  getVitalSignById,
} from './mock-data'
<<<<<<< HEAD
import type { VisitFormData } from './types'
=======
import type { MedicalBackgroundEntry, VisitFormData } from './types'
>>>>>>> master

export type VisitSummaryProps = {
  form: VisitFormData
  onEdit: () => void
  onFinalize: () => void
}

type LedgerRow = {
  label: string
  value: ReactNode
}

function LedgerEmpty() {
  return <span className="text-text-tertiary">—</span>
}

function LedgerText({ value }: { value: string }) {
  if (!value.trim()) return <LedgerEmpty />
  return <span className="whitespace-pre-wrap">{value}</span>
}

<<<<<<< HEAD
function LedgerInlineList({
  items,
  emptyLabel = '—',
}: {
  items: { id: string; label: string; meta?: string }[]
  emptyLabel?: string
}) {
  if (items.length === 0) {
=======
function LedgerBackgroundList({
  entries,
  resolveItem,
  emptyLabel,
}: {
  entries: MedicalBackgroundEntry[]
  resolveItem: (id: string) => { label: string; meta?: string } | undefined
  emptyLabel: string
}) {
  if (entries.length === 0) {
>>>>>>> master
    return <span className="text-text-tertiary">{emptyLabel}</span>
  }

  return (
<<<<<<< HEAD
    <span>
      {items.map((item, index) => (
        <span key={item.id}>
          {index > 0 ? <span className="text-text-tertiary"> · </span> : null}
          {item.label}
          {item.meta ? (
            <span className="text-text-secondary"> ({item.meta})</span>
          ) : null}
        </span>
      ))}
    </span>
=======
    <ul className="space-y-1.5">
      {entries.map((entry) => {
        const item = resolveItem(entry.itemId)
        if (!item) return null
        return (
          <li key={entry.id}>
            <span className="font-medium">{item.label}</span>
            {item.meta ? (
              <span className="text-text-secondary"> ({item.meta})</span>
            ) : null}
            {entry.note ? (
              <span className="text-text-secondary"> — {entry.note}</span>
            ) : null}
          </li>
        )
      })}
    </ul>
>>>>>>> master
  )
}

function LedgerSection({
  title,
  rows,
  isLast = false,
  delay = 0,
}: {
  title: string
  rows: LedgerRow[]
  isLast?: boolean
  delay?: number
}) {
  const preset = motionPresets['slide-up']
  const transition = resolveTransition(preset)
  const visibleRows = rows.filter((row) => row.value !== null)

  if (visibleRows.length === 0) return null

  return (
    <motion.section
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ ...transition, delay }}
      className={cn(!isLast && 'border-b border-border-default')}
      aria-label={title}
    >
      <h3 className="px-5 py-3 font-display text-body-strong text-text-primary sm:hidden">
        {title}
      </h3>

      <dl
        className={cn(
          'grid text-body-sm',
          'max-sm:grid-cols-[minmax(5.75rem,38%)_1fr] max-sm:gap-x-4 max-sm:px-5',
          'sm:grid-cols-[minmax(5.5rem,7rem)_minmax(7rem,10.5rem)_1fr] sm:gap-x-5 sm:px-6',
        )}
      >
        <dt
          className={cn(
            'hidden font-display text-body-strong text-text-primary sm:block',
            'border-e border-border-subtle py-3 pe-4',
          )}
          style={{ gridRow: `1 / span ${visibleRows.length}` }}
        >
          {title}
        </dt>

        {visibleRows.map((row, index) => (
          <LedgerEntry
            key={row.label}
            label={row.label}
            value={row.value}
            isLast={index === visibleRows.length - 1}
          />
        ))}
      </dl>
    </motion.section>
  )
}

function LedgerEntry({
  label,
  value,
  isLast,
}: {
  label: string
  value: ReactNode
  isLast: boolean
}) {
  return (
    <>
      <dt
        className={cn(
          'py-3 text-caption text-text-tertiary',
          !isLast && 'border-b border-border-subtle',
        )}
      >
        {label}
      </dt>
      <dd
        className={cn(
          'py-3 text-text-primary',
          !isLast && 'border-b border-border-subtle',
        )}
      >
        {value}
      </dd>
    </>
  )
}

export function VisitSummary({ form, onEdit, onFinalize }: VisitSummaryProps) {
  const preset = motionPresets['fade-scale']
  const transition = resolveTransition(preset)

  const intakeRows: LedgerRow[] = [
    { label: 'Complaint', value: <LedgerText value={form.complaint} /> },
    { label: 'History', value: <LedgerText value={form.history} /> },
    {
      label: 'Chronic conditions',
<<<<<<< HEAD
      value: <LedgerInlineList items={form.chronicConditions} emptyLabel="None recorded" />,
    },
    {
      label: 'Allergies',
      value: <LedgerInlineList items={form.allergies} emptyLabel="None recorded" />,
    },
    {
      label: 'Current medications',
      value: <LedgerInlineList items={form.currentMedications} emptyLabel="None recorded" />,
=======
      value: (
        <LedgerBackgroundList
          entries={form.chronicConditions}
          resolveItem={getChronicConditionById}
          emptyLabel="None recorded"
        />
      ),
    },
    {
      label: 'Allergies',
      value: (
        <LedgerBackgroundList
          entries={form.allergies}
          resolveItem={getAllergyById}
          emptyLabel="None recorded"
        />
      ),
    },
    {
      label: 'Current medications',
      value: (
        <LedgerBackgroundList
          entries={form.currentMedications}
          resolveItem={getCurrentMedicationById}
          emptyLabel="None recorded"
        />
      ),
>>>>>>> master
    },
  ]

  const findingsRows: LedgerRow[] = [
    { label: 'Examination', value: <LedgerText value={form.examination} /> },
    {
      label: 'Vital signs',
      value:
        form.vitalSigns.length > 0 ? (
          <ul className="space-y-1">
            {form.vitalSigns.map((vs) => {
              const def = getVitalSignById(vs.vitalSignId)
              return (
                <li key={vs.id}>
                  <span className="text-text-secondary">{def?.label ?? vs.vitalSignId}</span>
                  <span className="text-text-tertiary"> · </span>
                  <span className="tabular-nums font-medium">
                    {vs.value || '—'}
                    {def?.unit ? ` ${def.unit}` : ''}
                  </span>
                </li>
              )
            })}
          </ul>
        ) : (
          <span className="text-text-tertiary">None recorded</span>
        ),
    },
    { label: 'Diagnosis', value: <LedgerText value={form.diagnosis} /> },
  ]

  const treatmentRows: LedgerRow[] = [
    { label: 'Treatment notes', value: <LedgerText value={form.treatmentNotes} /> },
    {
      label: 'Investigations',
      value:
        form.investigationsNeeded.length > 0 ? (
          <ul className="space-y-1.5">
            {form.investigationsNeeded.map((item) => (
              <li key={item.id}>
                <span className="font-medium">{getInvestigationLabel(item.investigationId)}</span>
                {item.note ? (
                  <span className="text-text-secondary"> — {item.note}</span>
                ) : null}
              </li>
            ))}
          </ul>
        ) : (
          <span className="text-text-tertiary">None ordered</span>
        ),
    },
    {
      label: 'Treatment plan',
      value:
        form.treatmentPlan.length > 0 ? (
          <ul className="space-y-1.5">
            {form.treatmentPlan.map((rx) => (
              <li key={rx.id}>
                <span className="font-medium">
                  {rx.medicationId ? getMedicationLabel(rx.medicationId) : 'Unspecified'}
                </span>
                <span className="text-text-secondary">
                  {' — '}
                  {[rx.dosage, getFrequencyLabel(rx.frequency), getDurationLabel(rx.duration)]
                    .filter(Boolean)
                    .join(' · ')}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <span className="text-text-tertiary">None prescribed</span>
        ),
    },
    {
      label: 'Attachments',
      value:
        form.documents.length > 0 ? (
          <ul className="space-y-1">
            {form.documents.map((doc) => (
              <li key={doc.id} className="flex items-center gap-2">
                <FileText size={14} className="shrink-0 text-icon-muted" aria-hidden />
                {doc.name}
              </li>
            ))}
          </ul>
        ) : (
          <span className="text-text-tertiary">No attachments</span>
        ),
    },
  ]

  return (
    <motion.div
      initial="hidden"
      animate="visible"
      variants={staggerChildren(60)}
      className="space-y-6"
    >
      <motion.div variants={preset.variants} transition={transition}>
        <Card variant="raised" padding="sm" className="overflow-hidden rounded-2xl">
          <div className="border-b border-status-warning-border bg-status-warning-surface px-5 py-4 sm:px-6">
            <p className="text-overline text-status-warning-fg">Pending review</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Verify intake, findings, and treatment before finalizing this encounter.
            </p>
          </div>

          <LedgerSection title="Intake" rows={intakeRows} delay={0.05} />
          <LedgerSection title="Findings & diagnosis" rows={findingsRows} delay={0.1} />
          <LedgerSection title="Treatment" rows={treatmentRows} delay={0.15} isLast />

          <div className="flex flex-col-reverse gap-3 border-t border-border-subtle px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
            <Button
              variant="secondary"
              leadingIcon={<ArrowLeft size={16} />}
              onClick={onEdit}
            >
              Edit visit
            </Button>
            <Button
              variant="primary"
              trailingIcon={<CheckCircle2 size={16} />}
              onClick={onFinalize}
            >
              Finalize visit
            </Button>
          </div>
        </Card>
      </motion.div>
    </motion.div>
  )
}
