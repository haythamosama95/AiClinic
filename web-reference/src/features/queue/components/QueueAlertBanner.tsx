import { AlertTriangle } from 'lucide-react'

type QueueAlertBannerProps = {
  message: string
  onDismiss?: () => void
}

export function QueueAlertBanner({ message, onDismiss }: QueueAlertBannerProps) {
  return (
    <div
      className="flex items-center justify-between gap-3 rounded-lg border border-status-warning-border bg-status-warning-surface px-4 py-2.5"
      role="alert"
    >
      <div className="flex items-center gap-2">
        <AlertTriangle className="h-4 w-4 shrink-0 text-status-warning-fg" aria-hidden="true" />
        <p className="text-sm font-medium text-status-warning-fg">{message}</p>
      </div>
      {onDismiss && (
        <button
          type="button"
          onClick={onDismiss}
          className="shrink-0 text-xs font-medium text-status-warning-fg hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-status-warning-fg"
        >
          Dismiss
        </button>
      )}
    </div>
  )
}
