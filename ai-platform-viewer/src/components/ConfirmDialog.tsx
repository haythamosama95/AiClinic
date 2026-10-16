interface ConfirmDialogProps {
  open: boolean
  title: string
  description: string
  confirmLabel: string
  busy?: boolean
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel,
  busy = false,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  if (!open) return null

  return (
    <div
      className="dialog-backdrop"
      role="presentation"
      onClick={busy ? undefined : onCancel}
    >
      <div
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 id="confirm-title">{title}</h2>
        <p>{description}</p>
        <div className="dialog__actions">
          <button
            type="button"
            className="ghost-button"
            onClick={onCancel}
            disabled={busy}
          >
            Cancel
          </button>
          <button
            type="button"
            className="danger-button"
            onClick={onConfirm}
            disabled={busy}
          >
            {busy ? 'Resetting…' : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
