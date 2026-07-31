import type { HTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type CardVariant = 'flat' | 'raised' | 'interactive' | 'ai'

const variantClasses: Record<CardVariant, string> = {
  flat: 'border border-border-default bg-surface-default shadow-elevation-0',
  raised: 'border border-border-subtle bg-surface-raised shadow-elevation-1',
  interactive:
    'border border-border-default bg-surface-default shadow-elevation-0 transition-colors duration-[var(--duration-instant)] hover:bg-surface-hover focus-within:border-border-focus cursor-pointer',
  ai: 'border border-border-ai bg-surface-ai shadow-elevation-0',
}

export type CardProps = HTMLAttributes<HTMLDivElement> & {
  variant?: CardVariant
  header?: ReactNode
  footer?: ReactNode
  padding?: 'sm' | 'md' | 'lg'
}

const paddingClasses = {
  sm: 'p-4',
  md: 'p-5',
  lg: 'p-6',
}

export function Card({
  variant = 'flat',
  header,
  footer,
  padding = 'md',
  className,
  children,
  ...props
}: CardProps) {
  return (
    <div
      className={cn('rounded-lg', variantClasses[variant], className)}
      {...props}
    >
      {header ? (
        <div className="border-b border-border-subtle px-5 py-4">{header}</div>
      ) : null}
      <div className={cn(!header && !footer && paddingClasses[padding], header && 'p-5', footer && !header && paddingClasses[padding])}>
        {children}
      </div>
      {footer ? (
        <div className="border-t border-border-subtle px-5 py-4">{footer}</div>
      ) : null}
    </div>
  )
}
