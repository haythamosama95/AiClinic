import { type HTMLAttributes, type ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type BadgeVariant = 'solid' | 'soft' | 'outline' | 'dot'
export type BadgeColor =
  | 'neutral'
  | 'success'
  | 'warning'
  | 'danger'
  | 'info'
  | 'teal'
  | 'ai'
export type BadgeSize = 'sm' | 'md'

const sizeClasses: Record<BadgeSize, string> = {
  sm: 'h-5 gap-1 px-1.5 text-caption',
  md: 'h-6 gap-1.5 px-2 text-body-sm',
}

const dotSizeClasses: Record<BadgeSize, string> = {
  sm: 'size-1.5',
  md: 'size-2',
}

const colorClasses: Record<
  BadgeVariant,
  Record<BadgeColor, string>
> = {
  solid: {
    neutral: 'bg-text-secondary text-text-inverse',
    success: 'bg-status-success-fg text-text-inverse',
    warning: 'bg-status-warning-fg text-text-inverse',
    danger: 'bg-status-danger-fg text-text-inverse',
    info: 'bg-status-info-fg text-text-inverse',
    teal: 'bg-action-primary text-action-primary-fg',
    ai: 'bg-action-ai text-action-ai-fg',
  },
  soft: {
    neutral: 'bg-surface-muted text-text-secondary',
    success: 'bg-status-success-surface text-status-success-fg',
    warning: 'bg-status-warning-surface text-status-warning-fg',
    danger: 'bg-status-danger-surface text-status-danger-fg',
    info: 'bg-status-info-surface text-status-info-fg',
    teal: 'bg-surface-selected text-text-link',
    ai: 'bg-surface-ai text-text-ai',
  },
  outline: {
    neutral: 'border border-border-default bg-transparent text-text-secondary',
    success:
      'border border-status-success-border bg-transparent text-status-success-fg',
    warning:
      'border border-status-warning-border bg-transparent text-status-warning-fg',
    danger:
      'border border-status-danger-border bg-transparent text-status-danger-fg',
    info: 'border border-status-info-border bg-transparent text-status-info-fg',
    teal: 'border border-border-focus bg-transparent text-text-link',
    ai: 'border border-border-ai bg-transparent text-text-ai',
  },
  dot: {
    neutral: 'bg-transparent text-text-secondary',
    success: 'bg-transparent text-status-success-fg',
    warning: 'bg-transparent text-status-warning-fg',
    danger: 'bg-transparent text-status-danger-fg',
    info: 'bg-transparent text-status-info-fg',
    teal: 'bg-transparent text-text-link',
    ai: 'bg-transparent text-text-ai',
  },
}

const dotFillClasses: Record<BadgeColor, string> = {
  neutral: 'bg-icon-muted',
  success: 'bg-status-success-fg',
  warning: 'bg-status-warning-fg',
  danger: 'bg-status-danger-fg',
  info: 'bg-status-info-fg',
  teal: 'bg-action-primary',
  ai: 'bg-action-ai',
}

export type BadgeProps = HTMLAttributes<HTMLSpanElement> & {
  variant?: BadgeVariant
  color?: BadgeColor
  size?: BadgeSize
  /** Accessible label when variant is `dot` and children are omitted */
  label?: string
  children?: ReactNode
}

export function Badge({
  variant = 'soft',
  color = 'neutral',
  size = 'md',
  label,
  children,
  className,
  ...props
}: BadgeProps) {
  const isDotOnly = variant === 'dot' && !children
  const accessibleLabel = label ?? (typeof children === 'string' ? children : undefined)

  return (
    <span
      role={isDotOnly ? 'status' : undefined}
      aria-label={isDotOnly ? accessibleLabel : undefined}
      className={cn(
        'inline-flex max-w-full items-center rounded-full font-medium whitespace-nowrap',
        sizeClasses[size],
        colorClasses[variant][color],
        className,
      )}
      {...props}
    >
      {variant === 'dot' ? (
        <span
          className={cn('shrink-0 rounded-full', dotSizeClasses[size], dotFillClasses[color])}
          aria-hidden={!isDotOnly}
        />
      ) : null}
      {children ? <span className="truncate">{children}</span> : null}
    </span>
  )
}
