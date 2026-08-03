import { Stethoscope } from 'lucide-react'
import { cn } from '@/lib/cn'

export type AiClinicMarkProps = {
  compact?: boolean
  className?: string
}

export function AiClinicMark({ compact = false, className }: AiClinicMarkProps) {
  return (
    <div className={cn('flex items-center gap-2.5', className)}>
      <span
        className={cn(
          'inline-flex shrink-0 items-center justify-center rounded-lg bg-action-primary text-action-primary-fg',
          compact ? 'size-8' : 'size-9',
        )}
        aria-hidden
      >
        <Stethoscope className={compact ? 'size-4' : 'size-[18px]'} strokeWidth={1.75} />
      </span>
      {!compact ? (
        <span className="text-h3 text-text-primary">
          Ai<span className="text-text-link">Clinic</span>
        </span>
      ) : null}
    </div>
  )
}
