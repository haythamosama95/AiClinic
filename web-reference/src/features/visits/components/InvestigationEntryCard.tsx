import { Pencil, Trash2 } from 'lucide-react'
import { motion } from 'motion/react'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { EntryCardField, EntryCardFieldsRow } from './EntryCardField'

export type InvestigationEntryCardProps = {
  investigation: ComboboxItem
  note: string
  onEdit: () => void
  onRemove: () => void
  className?: string
}

export function InvestigationEntryCard({
  investigation,
  note,
  onEdit,
  onRemove,
  className,
}: InvestigationEntryCardProps) {
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
              label="Edit investigation"
              size="sm"
              className="text-text-tertiary"
              onClick={onEdit}
            />
            <IconButton
              icon={<Trash2 size={15} />}
              label="Remove investigation"
              size="sm"
              className="text-text-tertiary"
              onClick={onRemove}
            />
          </>
        }
      >
        <EntryCardField label="Investigation">
          <span className="font-medium">{investigation.label}</span>
        </EntryCardField>
        <EntryCardField label="Type">
          <span className="text-text-secondary">{investigation.meta ?? '—'}</span>
        </EntryCardField>
        <EntryCardField label="Note" className="flex-[1.5]">
          <span className={cn(!note && 'text-text-tertiary')}>{note || '—'}</span>
        </EntryCardField>
      </EntryCardFieldsRow>
    </motion.article>
  )
}
