import { Pencil, Trash2 } from 'lucide-react'
import { motion } from 'motion/react'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import { getDurationLabel, getFrequencyLabel } from '../mock-data'
import { EntryCardField, EntryCardFieldsRow } from './EntryCardField'

export type TreatmentPlanEntryCardProps = {
  medicationLabel: string
  medicationMeta?: string
  dosage: string
  frequency: string
  duration: string
  onEdit: () => void
  onRemove: () => void
  className?: string
}

export function TreatmentPlanEntryCard({
  medicationLabel,
  medicationMeta,
  dosage,
  frequency,
  duration,
  onEdit,
  onRemove,
  className,
}: TreatmentPlanEntryCardProps) {
  const preset = motionPresets['fade-scale']
  const transition = resolveTransition(preset)

  return (
    <motion.article
      layout={!getReducedMotion()}
      variants={preset.variants}
      initial="hidden"
      animate="visible"
      exit="exit"
      transition={transition}
      className={cn(
        'w-full rounded-xl border border-border-subtle border-l-[3px] border-l-action-primary/50 bg-surface-default px-5 py-3.5',
        className,
      )}
    >
      <EntryCardFieldsRow
        actions={
          <>
            <IconButton
              icon={<Pencil size={15} />}
              label="Edit prescription"
              size="sm"
              className="text-text-tertiary"
              onClick={onEdit}
            />
            <IconButton
              icon={<Trash2 size={15} />}
              label="Remove prescription"
              size="sm"
              className="text-text-tertiary"
              onClick={onRemove}
            />
          </>
        }
      >
        <EntryCardField label="Medication">
          <span className="font-medium">
            {medicationLabel}
            {medicationMeta ? (
              <span className="font-normal text-text-tertiary"> · {medicationMeta}</span>
            ) : null}
          </span>
        </EntryCardField>
        <EntryCardField label="Dosage">
          <span className={cn(!dosage && 'text-text-tertiary')}>{dosage || '—'}</span>
        </EntryCardField>
        <EntryCardField label="Frequency">
          <span className={cn(!frequency && 'text-text-tertiary')}>
            {frequency ? getFrequencyLabel(frequency) : '—'}
          </span>
        </EntryCardField>
        <EntryCardField label="Duration">
          <span className={cn(!duration && 'text-text-tertiary')}>
            {duration ? getDurationLabel(duration) : '—'}
          </span>
        </EntryCardField>
      </EntryCardFieldsRow>
    </motion.article>
  )
}
