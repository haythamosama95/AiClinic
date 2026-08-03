import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type PageHeaderProps = {
  title: string
  description?: string
  breadcrumb?: ReactNode
  actions?: ReactNode
  tabs?: ReactNode
  className?: string
}

export function PageHeader({
  title,
  description,
  breadcrumb,
  actions,
  tabs,
  className,
}: PageHeaderProps) {
  return (
    <header className={cn('space-y-4', className)}>
      {breadcrumb ? <div>{breadcrumb}</div> : null}

      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <h1 className="text-h1 text-text-primary">{title}</h1>
          {description ? (
            <p className="max-w-2xl text-body text-text-secondary">{description}</p>
          ) : null}
        </div>
        {actions ? (
          <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>
        ) : null}
      </div>

      {tabs ? <div>{tabs}</div> : null}
    </header>
  )
}
