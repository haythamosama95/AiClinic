type ConfirmDialogProps = {
  open: boolean
  title: string
  message: string
  confirmLabel: string
  onConfirm: () => void
  onCancel: () => void
  danger?: boolean
}

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  onConfirm,
  onCancel,
  danger = false,
}: ConfirmDialogProps) {
  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-surface-backdrop p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="confirm-dialog-title"
    >
      <div className="w-full max-w-sm rounded-xl border border-border-default bg-surface-default p-5 shadow-elevation-3">
        <h2 id="confirm-dialog-title" className="queue-heading text-lg font-semibold text-text-primary">
          {title}
        </h2>
        <p className="mt-2 text-sm text-text-secondary">{message}</p>
        <div className="mt-5 flex justify-end gap-2">
          <button
            type="button"
            onClick={onCancel}
            className="min-h-[48px] rounded-lg border border-border-default px-4 py-2 text-sm font-medium text-text-primary hover:bg-surface-hover focus:outline-none focus-visible:ring-2 focus-visible:ring-border-focus"
          >
            Go back
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className={`min-h-[48px] rounded-lg px-4 py-2 text-sm font-medium focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 ${
              danger
                ? 'bg-action-danger text-action-danger-fg hover:bg-action-danger-hover focus-visible:ring-action-danger'
                : 'bg-action-primary text-action-primary-fg hover:bg-action-primary-hover focus-visible:ring-border-focus'
            }`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
