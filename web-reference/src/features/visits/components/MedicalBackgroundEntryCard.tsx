import { Pencil, Trash2 } from 'lucide-react'
import { motion } from 'motion/react'
import { IconButton } from '@/components/actions/IconButton'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'

export type MedicalBackgroundAccent = 'warning' | 'danger' | 'info'

const accentStyles: Record<
  MedicalBackgroundAccent,
  { border: string; meta: string; noteRing: string }
> = {
  warning: {
    border: 'border-l-status-warning-border',
    meta: 'bg-status-warning-surface text-status-warning-fg',
    noteRing: 'focus-within:ring-status-warning-border/40',
  },
  danger: {
    border: 'border-l-status-danger-border',
    meta: 'bg-status-danger-surface text-status-danger-fg',
    noteRing: 'focus-within:ring-status-danger-border/40',
  },
  info: {
    border: 'border-l-status-info-border',
    meta: 'bg-status-info-surface text-status-info-fg',
    noteRing: 'focus-within:ring-status-info-border/40',
  },
}

export type MedicalBackgroundEntryCardProps = {
  item: ComboboxItem
  note: string
  accent: MedicalBackgroundAccent
  noteLabel: string
  notePlaceholder: string
  onNoteChange: (note: string) => void
  onEdit: () => void
  onRemove: () => void
  className?: string
}

export function MedicalBackgroundEntryCard({
  item,
  note,
  accent,
  noteLabel,
  notePlaceholder,
  onNoteChange,
  onEdit,
  onRemove,
  className,
}: MedicalBackgroundEntryCardProps) {
  const preset = motionPresets['fade-scale']
  const transition = resolveTransition(preset)
  const styles = accentStyles[accent]

  return (
    <motion.article
      layout={!getReducedMotion()}
      variants={preset.variants}
      initial="hidden"
      animate="visible"
      exit="exit"
      transition={transition}
      className={cn(
        'rounded-xl border border-border-subtle border-l-[3px] bg-surface-default',
        styles.border,
        className,
      )}
    >
      <div className="flex items-start gap-3 px-4 py-3.5">
        <div className="min-w-0 flex-1 space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <h4 className="text-body-strong text-text-primary">{item.label}</h4>
            {item.meta ? (
              <span
                className={cn(
                  'rounded-md px-1.5 py-0.5 font-mono text-[11px] font-medium tracking-wide',
                  styles.meta,
                )}
              >
                {item.meta}
              </span>
            ) : null}
          </div>

          <div
            className={cn(
              'rounded-lg ring-1 ring-transparent transition-shadow focus-within:ring-2',
              styles.noteRing,
            )}
          >
            <label htmlFor={`note-${item.id}`} className="sr-only">
              {noteLabel} for {item.label}
            </label>
            <Textarea
              id={`note-${item.id}`}
              rows={2}
              autoGrow
              value={note}
              onChange={(e) => onNoteChange(e.target.value)}
              placeholder={notePlaceholder}
              className="border-border-subtle bg-surface-muted/40 text-body-sm"
              aria-label={`${noteLabel} for ${item.label}`}
            />
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-0.5 border-s border-border-subtle ps-2">
          <IconButton
            icon={<Pencil size={15} />}
            label={`Edit ${item.label}`}
            size="sm"
            className="text-text-tertiary"
            onClick={onEdit}
          />
          <IconButton
            icon={<Trash2 size={15} />}
            label={`Remove ${item.label}`}
            size="sm"
            className="text-text-tertiary"
            onClick={onRemove}
          />
        </div>
      </div>
    </motion.article>
  )
}
