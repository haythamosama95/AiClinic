import { Pencil, Trash2 } from 'lucide-react'
import { motion } from 'motion/react'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import type { VitalSignDefinition } from '../types'

export type VitalSignEntryCardProps = {
  definition: VitalSignDefinition
  value: string
  onEdit: () => void
  onRemove: () => void
  className?: string
}

export function VitalSignEntryCard({
  definition,
  value,
  onEdit,
  onRemove,
  className,
}: VitalSignEntryCardProps) {
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
        'relative w-fit min-w-[9.5rem] max-w-full rounded-xl border border-border-subtle border-l-[3px] border-l-action-primary/50 bg-surface-default p-4',
        className,
      )}
    >
      <div className="flex items-center justify-between gap-3">
        <p className="whitespace-nowrap text-caption font-medium uppercase leading-none tracking-wider text-text-tertiary">
          {definition.label}
        </p>
        <div className="flex shrink-0 items-center">
          <IconButton
            icon={<Pencil size={15} />}
            label="Edit vital sign"
            size="sm"
            className="text-text-tertiary"
            onClick={onEdit}
          />
          <IconButton
            icon={<Trash2 size={15} />}
            label="Remove vital sign"
            size="sm"
            className="text-text-tertiary"
            onClick={onRemove}
          />
        </div>
      </div>

      <p className="mt-2 whitespace-nowrap font-display text-h2 leading-none tabular-nums text-text-primary">
        {value}
        <span className="ms-1.5 text-body-sm font-normal text-text-secondary">
          {definition.unit}
        </span>
      </p>
    </motion.article>
  )
}
