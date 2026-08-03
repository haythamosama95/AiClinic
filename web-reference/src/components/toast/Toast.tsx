import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { AnimatePresence, motion } from 'motion/react'
import { CheckCircle2, Info, X, XCircle } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition } from '@/lib/motion'

export type ToastVariant = 'success' | 'danger' | 'info' | 'neutral'

export type ToastInput = {
  id?: string
  variant?: ToastVariant
  message: string
  action?: { label: string; onClick: () => void }
  duration?: number
}

type ToastItem = ToastInput & { id: string }

type ToastContextValue = {
  toast: (input: ToastInput) => void
  dismiss: (id: string) => void
}

const ToastContext = createContext<ToastContextValue | null>(null)

const MAX_TOASTS = 3

const variantStyles: Record<ToastVariant, string> = {
  success: 'border-status-success-border bg-surface-raised',
  danger: 'border-status-danger-border bg-surface-raised',
  info: 'border-status-info-border bg-surface-raised',
  neutral: 'border-border-default bg-surface-raised',
}

const variantIcons: Record<ToastVariant, ReactNode> = {
  success: <CheckCircle2 size={16} className="text-status-success-fg" aria-hidden />,
  danger: <XCircle size={16} className="text-status-danger-fg" aria-hidden />,
  info: <Info size={16} className="text-status-info-fg" aria-hidden />,
  neutral: <Info size={16} className="text-icon-default" aria-hidden />,
}

function ToastView({
  item,
  onDismiss,
}: {
  item: ToastItem
  onDismiss: (id: string) => void
}) {
  const variant = item.variant ?? 'neutral'
  const role = variant === 'danger' ? 'alert' : 'status'

  return (
    <motion.div
      layout
      initial="hidden"
      animate="visible"
      exit="hidden"
      variants={motionPresets['slide-up'].variants}
      transition={resolveTransition(motionPresets['slide-up'])}
      role={role}
      className={cn(
        'pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-lg border p-4 shadow-elevation-2',
        variantStyles[variant],
      )}
      onMouseEnter={() => {
        /* pause auto-dismiss handled by provider */
      }}
    >
      {variantIcons[variant]}
      <div className="min-w-0 flex-1">
        <p className="text-body text-text-primary">{item.message}</p>
        {item.action ? (
          <Button
            variant="link"
            size="sm"
            className="mt-1"
            onClick={() => {
              item.action?.onClick()
              onDismiss(item.id)
            }}
          >
            {item.action.label}
          </Button>
        ) : null}
      </div>
      <IconButton
        icon={<X size={14} />}
        label="Dismiss"
        size="sm"
        variant="ghost"
        onClick={() => onDismiss(item.id)}
      />
    </motion.div>
  )
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([])

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const toast = useCallback(
    (input: ToastInput) => {
      const id = input.id ?? `toast-${Date.now()}-${Math.random().toString(36).slice(2)}`
      const duration =
        input.duration ?? (input.variant === 'danger' ? 8000 : 4000)

      setToasts((prev) => {
        const next = [...prev, { ...input, id }]
        return next.slice(-MAX_TOASTS)
      })

      if (duration > 0) {
        window.setTimeout(() => dismiss(id), duration)
      }
    },
    [dismiss],
  )

  const value = useMemo(() => ({ toast, dismiss }), [toast, dismiss])

  return (
    <ToastContext.Provider value={value}>
      {children}
      {createPortal(
        <div
          className="pointer-events-none fixed bottom-4 end-4 z-[var(--z-toast)] flex flex-col gap-2"
          aria-live="polite"
        >
          <AnimatePresence mode="popLayout">
            {toasts.map((item) => (
              <ToastView key={item.id} item={item} onDismiss={dismiss} />
            ))}
          </AnimatePresence>
        </div>,
        document.body,
      )}
    </ToastContext.Provider>
  )
}

export function useToast() {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast must be used within ToastProvider')
  return ctx
}
