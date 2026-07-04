import { X } from 'lucide-react'
import type { ReactNode } from 'react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'

export type BulkActionBarProps = {
  count: number
  itemLabel?: string
  actions?: ReactNode
  onClear: () => void
  className?: string
}

export function BulkActionBar({
  count,
  itemLabel = 'selected',
  actions,
  onClear,
  className,
}: BulkActionBarProps) {
  if (count === 0) return null

  return (
    <div
      role="region"
      aria-label="Bulk actions"
      className={cn(
        'flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border-default bg-surface-raised px-4 py-3 shadow-elevation-2',
        className,
      )}
    >
      <p className="text-body-strong tabular-nums text-text-primary">
        {count} {itemLabel}
      </p>
      <div className="flex flex-wrap items-center gap-2">
        {actions}
        <Button
          variant="ghost"
          size="sm"
          leadingIcon={<X size={14} />}
          onClick={onClear}
        >
          Clear selection
        </Button>
      </div>
    </div>
  )
}
