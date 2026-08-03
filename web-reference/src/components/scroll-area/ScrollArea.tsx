import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type ScrollAreaProps = HTMLAttributes<HTMLDivElement> & {
  children: ReactNode
  maxHeight?: string | number
  fadeEdges?: boolean
}

export function ScrollArea({
  children,
  maxHeight = 240,
  fadeEdges = true,
  className,
  ...props
}: ScrollAreaProps) {
  return (
    <div className={cn('relative', className)} {...props}>
      {fadeEdges ? (
        <>
          <div
            className="pointer-events-none absolute inset-x-0 top-0 z-10 h-4 bg-gradient-to-b from-surface-default to-transparent"
            aria-hidden
          />
          <div
            className="pointer-events-none absolute inset-x-0 bottom-0 z-10 h-4 bg-gradient-to-t from-surface-default to-transparent"
            aria-hidden
          />
        </>
      ) : null}
      <div
        className="overflow-auto overscroll-contain [scrollbar-width:thin] [scrollbar-color:var(--border-default)_transparent]"
        style={{ maxHeight }}
        tabIndex={0}
        role="region"
        aria-label="Scrollable content"
      >
        {children}
      </div>
    </div>
  )
}
