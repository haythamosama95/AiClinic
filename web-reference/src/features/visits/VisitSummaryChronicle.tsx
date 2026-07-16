import type { ReactNode } from 'react'
import {
  ArrowLeft,
  FileText,
  LayoutGrid,
  Printer,
  RotateCcw,
} from 'lucide-react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { Card } from '@/components/card/Card'
import { Timeline } from '@/components/timeline/Timeline'
import type { Patient } from '@/data/patients'
import { patientFullName } from '@/data/patients'
import { motionPresets, resolveTransition } from '@/lib/motion'
import {
  getDurationLabel,
  getFrequencyLabel,
  getInvestigationLabel,
  getMedicationLabel,
  getVitalSignById,
} from './mock-data'
import type { VisitFormData } from './types'

export type VisitSummaryChronicleProps = {
  patient: Patient
  form: VisitFormData
  finalizedAt: Date
  onBack: () => void
  onEdit: () => void
  onNewVisit: () => void
}

function ChronicleSection({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <section className="space-y-3">
      <h3 className="font-display text-h3 text-text-primary">{title}</h3>
      <div className="space-y-3 text-body-sm text-text-primary">{children}</div>
    </section>
  )
}

function ProseField({ label, value }: { label: string; value: string }) {
  if (!value.trim()) return null
  return (
    <div>
      <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">{label}</p>
      <p className="mt-1 whitespace-pre-wrap">{value}</p>
    </div>
  )
}

function InlineList({ items }: { items: string[] }) {
  if (items.length === 0) return <p className="text-text-tertiary">None recorded</p>
  return <p>{items.join(' · ')}</p>
}

export function VisitSummaryChronicle({
  patient,
  form,
  finalizedAt,
  onBack,
  onEdit,
  onNewVisit,
}: VisitSummaryChronicleProps) {
  const preset = motionPresets['fade-scale']
  const transition = resolveTransition(preset)

  const formattedDate = finalizedAt.toLocaleString('en-GB', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })

  const chronicLabels = form.chronicConditions.map((item) =>
    item.meta ? `${item.label} (${item.meta})` : item.label,
  )
  const allergyLabels = form.allergies.map((item) =>
    item.meta ? `${item.label} (${item.meta})` : item.label,
  )
  const medicationLabels = form.currentMedications.map((item) =>
    item.meta ? `${item.label} ${item.meta}` : item.label,
  )

  const vitalLines = form.vitalSigns.map((vs) => {
    const def = getVitalSignById(vs.vitalSignId)
    const label = def?.label ?? vs.vitalSignId
    const value = vs.value ? `${vs.value} ${def?.unit ?? ''}`.trim() : '—'
    return `${label}: ${value}`
  })

  const investigationLines = form.investigationsNeeded.map((item) => {
    const label = getInvestigationLabel(item.investigationId)
    return item.note ? `${label} — ${item.note}` : label
  })

  const treatmentLines = form.treatmentPlan.map((rx) => {
    const name = rx.medicationId ? getMedicationLabel(rx.medicationId) : 'Unspecified'
    const details = [rx.dosage, getFrequencyLabel(rx.frequency), getDurationLabel(rx.duration)]
      .filter(Boolean)
      .join(', ')
    return details ? `${name} (${details})` : name
  })

  const documentLines = form.documents.map((doc) => doc.name)

  const timelineEvents = [
    {
      id: 'intake',
      timestamp: formattedDate,
      title: 'Intake',
      group: 'Encounter record',
      description: (
        <div className="space-y-2">
          <ProseField label="Chief complaint" value={form.complaint} />
          <ProseField label="History" value={form.history} />
          <div>
            <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">
              Chronic conditions
            </p>
            <InlineList items={chronicLabels} />
          </div>
          <div>
            <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">
              Allergies
            </p>
            <InlineList items={allergyLabels} />
          </div>
          <div>
            <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">
              Current medications
            </p>
            <InlineList items={medicationLabels} />
          </div>
        </div>
      ),
    },
    {
      id: 'findings',
      timestamp: formattedDate,
      title: 'Findings & diagnosis',
      description: (
        <div className="space-y-2">
          <ProseField label="Examination" value={form.examination} />
          <div>
            <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">
              Vital signs
            </p>
            <InlineList items={vitalLines} />
          </div>
          <ProseField label="Diagnosis" value={form.diagnosis} />
        </div>
      ),
    },
    {
      id: 'treatment',
      timestamp: formattedDate,
      title: 'Treatment',
      description: (
        <div className="space-y-2">
          <ProseField label="Treatment notes" value={form.treatmentNotes} />
          <div>
            <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">
              Investigations ordered
            </p>
            <InlineList items={investigationLines} />
          </div>
          <div>
            <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">
              Prescriptions
            </p>
            <InlineList items={treatmentLines} />
          </div>
          <div>
            <p className="text-caption font-medium uppercase tracking-wider text-text-tertiary">
              Attachments
            </p>
            {documentLines.length > 0 ? (
              <ul className="mt-1 space-y-1">
                {documentLines.map((name) => (
                  <li key={name} className="flex items-center gap-2">
                    <FileText size={14} className="shrink-0 text-icon-muted" aria-hidden />
                    {name}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-text-tertiary">No attachments</p>
            )}
          </div>
        </div>
      ),
    },
  ]

  return (
    <motion.div
      initial="hidden"
      animate="visible"
      variants={preset.variants}
      transition={transition}
      className="space-y-6"
    >
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-overline text-text-tertiary">Encounter chronicle</p>
          <h2 className="mt-1 font-display text-h2 text-text-primary">
            {patientFullName(patient)}
          </h2>
          <p className="mt-1 text-body-sm text-text-secondary">
            MRN {patient.mrn} · {formattedDate}
          </p>
        </div>

        <div className="flex flex-wrap gap-2 print:hidden">
          <Button variant="ghost" leadingIcon={<LayoutGrid size={16} />} onClick={onBack}>
            Card view
          </Button>
          <Button variant="secondary" leadingIcon={<RotateCcw size={16} />} onClick={onEdit}>
            Edit visit
          </Button>
          <Button variant="secondary" leadingIcon={<Printer size={16} />} onClick={() => window.print()}>
            Print
          </Button>
          <Button variant="primary" leadingIcon={<ArrowLeft size={16} />} onClick={onNewVisit}>
            New visit
          </Button>
        </div>
      </div>

      <Card variant="raised" padding="lg" className="max-w-3xl">
        <ChronicleSection title="Continuous record">
          <Timeline events={timelineEvents} />
        </ChronicleSection>
      </Card>
    </motion.div>
  )
}
