import { X } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import { useCallback, useEffect, useId, useRef, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'
import { trapFocus } from '@/lib/focus-trap'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'

export type DrawerSide = 'inline-end' | 'inline-start' | 'bottom'
export type DrawerSize = 'sm' | 'md' | 'lg'

const sizeClasses: Record<DrawerSize, string> = {
  sm: 'max-w-sm',
  md: 'max-w-md',
  lg: 'max-w-xl',
}

export type DrawerProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: string
  side?: DrawerSide
  size?: DrawerSize
  modal?: boolean
  children: ReactNode
  footer?: ReactNode
  className?: string
}

export function Drawer({
  open,
  onOpenChange,
  title,
  description,
  side = 'inline-end',
  size = 'md',
  modal = true,
  children,
  footer,
  className,
}: DrawerProps) {
  const panelRef = useRef<HTMLDivElement>(null)
  const titleId = useId()
  const showBlur = !getReducedMotion()

  const handleClose = useCallback(() => onOpenChange(false), [onOpenChange])

  useEffect(() => {
    if (!open) return
    document.body.style.overflow = 'hidden'
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
      if (panelRef.current) trapFocus(panelRef.current, e)
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, handleClose])

  const drawerOffset =
    side === 'inline-end'
      ? 'var(--motion-drawer-offset, 100%)'
      : side === 'inline-start'
        ? 'calc(-1 * var(--motion-drawer-offset, 100%))'
        : '100%'

  if (!open) return null

  return createPortal(
    <AnimatePresence>
      {open ? (
        <>
          {modal ? (
            <motion.button
              type="button"
              aria-label="Close drawer"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className={cn(
                'fixed inset-0 z-[var(--z-backdrop)] bg-surface-backdrop',
                showBlur && 'backdrop-blur-sm',
              )}
              onClick={handleClose}
            />
          ) : null}
          <motion.div
            ref={panelRef}
            role="dialog"
            aria-modal={modal}
            aria-labelledby={titleId}
            initial={{ x: drawerOffset, y: side === 'bottom' ? drawerOffset : 0 }}
            animate={{ x: 0, y: 0 }}
            exit={{ x: drawerOffset, y: side === 'bottom' ? drawerOffset : 0 }}
            transition={resolveTransition(motionPresets.drawer)}
            style={{ '--motion-drawer-offset': '100%' } as React.CSSProperties}
            className={cn(
              'fixed z-[var(--z-modal)] flex flex-col border border-border-default bg-surface-raised shadow-elevation-3',
              side === 'bottom'
                ? 'inset-x-0 bottom-0 max-h-[85dvh] rounded-t-xl'
                : cn(
                  'inset-y-0 h-full',
                  side === 'inline-end' ? 'end-0 rounded-s-xl' : 'start-0 rounded-e-xl',
                  sizeClasses[size],
                ),
              className,
            )}
          >
            <div className="flex shrink-0 items-start justify-between gap-4 border-b border-border-subtle px-5 py-4">
              <div>
                <h2 id={titleId} className="text-h3 text-text-primary">
                  {title}
                </h2>
                {description ? (
                  <p className="mt-1 text-body-sm text-text-secondary">{description}</p>
                ) : null}
              </div>
              <IconButton icon={<X size={18} />} label="Close" size="sm" onClick={handleClose} />
            </div>
            <div className="flex-1 overflow-y-auto px-5 py-4">{children}</div>
            {footer ? (
              <div className="shrink-0 border-t border-border-subtle px-5 py-4">{footer}</div>
            ) : null}
          </motion.div>
        </>
      ) : null}
    </AnimatePresence>,
    document.body,
  )
}
