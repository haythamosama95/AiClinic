import { type HTMLAttributes, type ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type DividerProps = HTMLAttributes<HTMLDivElement> & {
  orientation?: 'horizontal' | 'vertical'
  label?: ReactNode
}

export function Divider({
  orientation = 'horizontal',
  label,
  className,
  ...props
}: DividerProps) {
  if (orientation === 'vertical') {
    return (
      <div
        role="separator"
        aria-orientation="vertical"
        className={cn('w-px self-stretch bg-border-subtle', className)}
        {...props}
      />
    )
  }

  if (label) {
    return (
      <div
        role="separator"
        className={cn('flex items-center gap-3', className)}
        {...props}
      >
        <span className="h-px flex-1 bg-border-subtle" aria-hidden />
        <span className="text-caption text-text-tertiary">{label}</span>
        <span className="h-px flex-1 bg-border-subtle" aria-hidden />
      </div>
    )
  }

  return (
    <hr
      className={cn('border-0 border-t border-border-subtle', className)}
      {...props}
    />
  )
}
