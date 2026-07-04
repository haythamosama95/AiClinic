import { AlertTriangle, RefreshCw } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'

export type ErrorStateProps = {
  title?: string
  message: string
  onRetry?: () => void
  retryLabel?: string
  className?: string
}

export function ErrorState({
  title = 'Failed to load',
  message,
  onRetry,
  retryLabel = 'Try again',
  className,
}: ErrorStateProps) {
  return (
    <div
      role="alert"
      className={cn(
        'flex flex-col items-center justify-center px-6 py-12 text-center',
        className,
      )}
    >
      <div className="mb-4 flex size-12 items-center justify-center rounded-full bg-status-danger-surface text-status-danger-fg">
        <AlertTriangle size={24} strokeWidth={1.5} aria-hidden />
      </div>
      <h3 className="text-h3 text-text-primary">{title}</h3>
      <p className="mt-2 max-w-sm text-body text-text-secondary">{message}</p>
      {onRetry ? (
        <Button
          variant="secondary"
          className="mt-6"
          onClick={onRetry}
          leadingIcon={<RefreshCw size={16} />}
        >
          {retryLabel}
        </Button>
      ) : null}
    </div>
  )
}
