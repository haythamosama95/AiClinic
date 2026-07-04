import { Children, type ReactNode } from 'react'
import { cn } from '@/lib/cn'
import type { AvatarSize } from './Avatar'

const overlapClasses: Record<AvatarSize, string> = {
  xs: '-ms-1.5',
  sm: '-ms-2',
  md: '-ms-2.5',
  lg: '-ms-3',
  xl: '-ms-3.5',
}

const overflowSizeClasses: Record<AvatarSize, string> = {
  xs: 'size-5 text-[10px]',
  sm: 'size-6 text-caption',
  md: 'size-8 text-body-sm',
  lg: 'size-10 text-body',
  xl: 'size-12 text-title',
}

export type AvatarGroupProps = {
  children: ReactNode
  max?: number
  size?: AvatarSize
  className?: string
}

export function AvatarGroup({
  children,
  max = 4,
  size = 'md',
  className,
}: AvatarGroupProps) {
  const items = Children.toArray(children)
  const visible = items.slice(0, max)
  const overflow = items.length - max

  return (
    <div className={cn('flex items-center', className)} role="group" aria-label="Avatar group">
      {visible.map((child, index) => (
        <div
          key={index}
          className={cn(index > 0 && overlapClasses[size], 'ring-2 ring-surface-default rounded-full')}
        >
          {child}
        </div>
      ))}
      {overflow > 0 ? (
        <span
          className={cn(
            'inline-flex items-center justify-center rounded-full bg-surface-muted font-medium text-text-secondary ring-2 ring-surface-default',
            overlapClasses[size],
            overflowSizeClasses[size],
          )}
          aria-label={`${overflow} more`}
        >
          +{overflow}
        </span>
      ) : null}
    </div>
  )
}
