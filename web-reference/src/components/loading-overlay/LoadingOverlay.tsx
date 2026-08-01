import type { ReactNode } from 'react'
import { Spinner } from '@/components/ui/spinner/Spinner'
import { cn } from '@/lib/cn'

export type LoadingOverlayProps = {
  loading?: boolean
  label?: string
  scoped?: boolean
  children?: ReactNode
  className?: string
}

export function LoadingOverlay({
  loading = true,
  label = 'Loading',
  scoped = false,
  children,
  className,
}: LoadingOverlayProps) {
  if (!loading && !children) return null

  const overlay = loading ? (
    <div
      role="status"
      aria-live="polite"
      aria-busy="true"
      className={cn(
        'flex flex-col items-center justify-center gap-3 bg-surface-default/80',
        scoped ? 'absolute inset-0 z-10 rounded-[inherit]' : 'fixed inset-0 z-[var(--z-modal)]',
        className,
      )}
    >
      <Spinner size="md" />
      <span className="text-body-sm text-text-secondary">{label}</span>
    </div>
  ) : null

  if (scoped && children) {
    return (
      <div className="relative">
        {children}
        {overlay}
      </div>
    )
  }

  return overlay
}
