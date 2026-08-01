import { AlertCircle, CheckCircle2, Info, Sparkles, X, XCircle } from 'lucide-react'
import type { ReactNode } from 'react'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'

export type AlertVariant = 'info' | 'success' | 'warning' | 'danger' | 'ai'

const variantStyles: Record<AlertVariant, { container: string; icon: string }> = {
  info: {
    container: 'border-status-info-border bg-status-info-surface text-status-info-fg',
    icon: 'text-status-info-fg',
  },
  success: {
    container: 'border-status-success-border bg-status-success-surface text-status-success-fg',
    icon: 'text-status-success-fg',
  },
  warning: {
    container: 'border-status-warning-border bg-status-warning-surface text-status-warning-fg',
    icon: 'text-status-warning-fg',
  },
  danger: {
    container: 'border-status-danger-border bg-status-danger-surface text-status-danger-fg',
    icon: 'text-status-danger-fg',
  },
  ai: {
    container: 'border-border-ai bg-surface-ai text-text-ai',
    icon: 'text-text-ai',
  },
}

const icons: Record<AlertVariant, ReactNode> = {
  info: <Info size={16} aria-hidden />,
  success: <CheckCircle2 size={16} aria-hidden />,
  warning: <AlertCircle size={16} aria-hidden />,
  danger: <XCircle size={16} aria-hidden />,
  ai: <Sparkles size={16} aria-hidden />,
}

export type AlertProps = {
  variant?: AlertVariant
  title: string
  children?: ReactNode
  actions?: ReactNode
  dismissible?: boolean
  onDismiss?: () => void
  className?: string
}

export function Alert({
  variant = 'info',
  title,
  children,
  actions,
  dismissible,
  onDismiss,
  className,
}: AlertProps) {
  const styles = variantStyles[variant]

  return (
    <div
      role={variant === 'danger' ? 'alert' : 'status'}
      className={cn(
        'flex gap-3 rounded-lg border p-4',
        styles.container,
        className,
      )}
    >
      <span className={cn('mt-0.5 shrink-0', styles.icon)}>{icons[variant]}</span>
      <div className="min-w-0 flex-1">
        <p className="text-body-strong">{title}</p>
        {children ? (
          <div className="mt-1 text-body-sm opacity-90">{children}</div>
        ) : null}
        {actions ? <div className="mt-3 flex flex-wrap gap-2">{actions}</div> : null}
      </div>
      {dismissible ? (
        <IconButton
          icon={<X size={16} />}
          label="Dismiss alert"
          size="sm"
          variant="ghost"
          onClick={onDismiss}
          className="shrink-0"
        />
      ) : null}
    </div>
  )
}
