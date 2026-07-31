import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type ToolbarProps = {
  start?: ReactNode
  center?: ReactNode
  end?: ReactNode
  sticky?: boolean
  className?: string
}

export function Toolbar({
  start,
  center,
  end,
  sticky = false,
  className,
}: ToolbarProps) {
  return (
    <div
      className={cn(
        'flex flex-wrap items-center gap-3 rounded-lg border border-border-default bg-surface-default px-4 py-3',
        sticky && 'sticky top-0 z-sticky',
        className,
      )}
      role="toolbar"
    >
      {start ? <div className="flex flex-wrap items-center gap-2">{start}</div> : null}
      {center ? <div className="flex min-w-0 flex-1 justify-center">{center}</div> : null}
      {end ? (
        <div className="ms-auto flex flex-wrap items-center gap-2">{end}</div>
      ) : null}
    </div>
  )
}
