import { useEffect } from 'react'

export interface ToastItem {
  id: string
  message: string
  variant: 'ok' | 'error'
}

interface ToastStackProps {
  toasts: ToastItem[]
  onDismiss: (id: string) => void
  durationMs?: number
}

export function ToastStack({
  toasts,
  onDismiss,
  durationMs = 5000,
}: ToastStackProps) {
  return (
    <div className="toast-stack" aria-live="polite" aria-relevant="additions">
      {toasts.map((toast) => (
        <ToastCard
          key={toast.id}
          toast={toast}
          durationMs={durationMs}
          onDismiss={onDismiss}
        />
      ))}
    </div>
  )
}

interface ToastCardProps {
  toast: ToastItem
  durationMs: number
  onDismiss: (id: string) => void
}

function ToastCard({ toast, durationMs, onDismiss }: ToastCardProps) {
  useEffect(() => {
    const timer = window.setTimeout(() => {
      onDismiss(toast.id)
    }, durationMs)
    return () => window.clearTimeout(timer)
  }, [durationMs, onDismiss, toast.id])

  return (
    <div
      className={`toast toast--${toast.variant}`}
      role={toast.variant === 'error' ? 'alert' : 'status'}
    >
      <p className="toast__message">{toast.message}</p>
      <button
        type="button"
        className="toast__dismiss"
        aria-label="Dismiss notification"
        onClick={() => onDismiss(toast.id)}
      >
        ×
      </button>
    </div>
  )
}
