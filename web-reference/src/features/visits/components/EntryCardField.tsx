import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type EntryCardFieldProps = {
  label: string
  children: ReactNode
  className?: string
}

export function EntryCardField({ label, children, className }: EntryCardFieldProps) {
  return (
    <div className={cn('min-w-0 flex-1', className)}>
      <div className="flex items-baseline gap-2">
        <span className="shrink-0 text-caption text-text-tertiary">{label}</span>
        <div className="min-w-0 truncate text-body-sm text-text-primary">{children}</div>
      </div>
    </div>
  )
}

export type EntryCardFieldsRowProps = {
  children: ReactNode
  actions?: ReactNode
  className?: string
}

export function EntryCardFieldsRow({ children, actions, className }: EntryCardFieldsRowProps) {
  return (
    <div className={cn('flex w-full items-center gap-5', className)}>
      <div className="flex min-w-0 flex-1 items-center justify-between gap-5 lg:gap-8">
        {children}
      </div>
      {actions ? (
        <div className="flex shrink-0 items-center border-s border-border-subtle ps-4">
          {actions}
        </div>
      ) : null}
    </div>
  )
}
