import { type HTMLAttributes } from 'react'
import { cn } from '@/lib/cn'

export type SkeletonVariant = 'text' | 'circular' | 'rectangular'

const variantClasses: Record<SkeletonVariant, string> = {
  text: 'h-4 w-full rounded-sm',
  circular: 'rounded-full',
  rectangular: 'rounded-md',
}

export type SkeletonProps = HTMLAttributes<HTMLDivElement> & {
  variant?: SkeletonVariant
  width?: string | number
  height?: string | number
}

export function Skeleton({
  variant = 'rectangular',
  width,
  height,
  className,
  style,
  ...props
}: SkeletonProps) {
  return (
    <div
      role="status"
      aria-busy="true"
      aria-label="Loading"
      className={cn(
        'skeleton-shimmer bg-surface-muted',
        variantClasses[variant],
        className,
      )}
      style={{
        width,
        height,
        ...style,
      }}
      {...props}
    />
  )
}
