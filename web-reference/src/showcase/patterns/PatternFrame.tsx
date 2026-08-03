import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export function PatternFrame({
  children,
  className,
  minHeight,
}: {
  children: ReactNode
  className?: string
  minHeight?: string
}) {
  return (
    <div
      className={cn(
        'overflow-hidden rounded-lg border border-border-default bg-surface-canvas',
        className,
      )}
      style={minHeight ? { minHeight } : undefined}
    >
      {children}
    </div>
  )
}
