import { X } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'
import { trapFocus } from '@/lib/focus-trap'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'

export type DialogSize = 'sm' | 'md' | 'lg' | 'full'

const sizeClasses: Record<DialogSize, string> = {
  sm: 'max-w-sm',
  md: 'max-w-lg',
  lg: 'max-w-2xl',
  full: 'max-w-[calc(100vw-2rem)] h-[calc(100dvh-2rem)]',
}

export type DialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: string
  size?: DialogSize
  children: ReactNode
  footer?: ReactNode
  className?: string
}

export function Dialog({
  open,
  onOpenChange,
  title,
  description,
  size = 'md',
  children,
  footer,
  className,
}: DialogProps) {
  const dialogRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLElement | null>(null)
  const titleId = useId()
  const descId = useId()

  const handleClose = useCallback(() => {
    onOpenChange(false)
    triggerRef.current?.focus()
  }, [onOpenChange])

  useEffect(() => {
    if (open) {
      triggerRef.current = document.activeElement as HTMLElement
      document.body.style.overflow = 'hidden'
      window.setTimeout(() => {
        const first = dialogRef.current?.querySelector<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
        )
        first?.focus()
      }, 50)
    } else {
      document.body.style.overflow = ''
    }
    return () => {
      document.body.style.overflow = ''
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault()
        handleClose()
      }
      if (dialogRef.current) trapFocus(dialogRef.current, e)
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, handleClose])

  const showBlur = !getReducedMotion()

  if (!open) return null

  return createPortal(
    <AnimatePresence>
      {open ? (
        <>
          <motion.button
            type="button"
            aria-label="Close dialog"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={resolveTransition(motionPresets.fade)}
            className={cn(
              'fixed inset-0 z-[var(--z-backdrop)] bg-surface-backdrop',
              showBlur && 'backdrop-blur-sm',
            )}
            onClick={handleClose}
          />
          <div className="fixed inset-0 z-[var(--z-modal)] flex items-center justify-center p-4">
            <motion.div
              ref={dialogRef}
              role="dialog"
              aria-modal="true"
              aria-labelledby={titleId}
              aria-describedby={description ? descId : undefined}
              initial="hidden"
              animate="visible"
              exit="exit"
              variants={motionPresets.modal.variants}
              transition={resolveTransition(motionPresets.modal)}
              className={cn(
                'flex w-full flex-col overflow-hidden rounded-xl border border-border-default bg-surface-raised shadow-elevation-3',
                sizeClasses[size],
                className,
              )}
            >
              <div className="flex shrink-0 items-start justify-between gap-4 border-b border-border-subtle px-6 py-4">
                <div>
                  <h2 id={titleId} className="text-h3 text-text-primary">
                    {title}
                  </h2>
                  {description ? (
                    <p id={descId} className="mt-1 text-body-sm text-text-secondary">
                      {description}
                    </p>
                  ) : null}
                </div>
                <IconButton
                  icon={<X size={18} />}
                  label="Close"
                  size="sm"
                  onClick={handleClose}
                />
              </div>
              <div className="flex-1 overflow-y-auto px-6 py-4">{children}</div>
              {footer ? (
                <div className="flex shrink-0 justify-end gap-2 border-t border-border-subtle px-6 py-4">
                  {footer}
                </div>
              ) : null}
            </motion.div>
          </div>
        </>
      ) : null}
    </AnimatePresence>,
    document.body,
  )
}

export type ConfirmationDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description: ReactNode
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'destructive' | 'financial'
  requireTypedConfirmation?: string
  onConfirm: () => void
  loading?: boolean
}

export function ConfirmationDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  variant = 'destructive',
  requireTypedConfirmation,
  onConfirm,
  loading,
}: ConfirmationDialogProps) {
  const [typed, setTyped] = useState('')

  const canConfirm =
    !requireTypedConfirmation || typed === requireTypedConfirmation

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={title}
      size="sm"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            {cancelLabel}
          </Button>
          <Button
            variant={variant === 'destructive' ? 'danger' : 'primary'}
            loading={loading}
            disabled={!canConfirm}
            onClick={() => {
              onConfirm()
              onOpenChange(false)
            }}
          >
            {confirmLabel}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <p className="text-body text-text-secondary">{description}</p>
        {requireTypedConfirmation ? (
          <div>
            <label htmlFor="confirm-input" className="text-body-sm text-text-secondary">
              Type <strong>{requireTypedConfirmation}</strong> to confirm
            </label>
            <input
              id="confirm-input"
              type="text"
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              className="focus-ring mt-2 w-full rounded-md border border-border-default bg-surface-default px-3 py-2 text-body"
            />
          </div>
        ) : null}
      </div>
    </Dialog>
  )
}
