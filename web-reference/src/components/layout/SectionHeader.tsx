import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type SectionHeaderProps = {
  title: string
  description?: string
  actions?: ReactNode
  className?: string
}

export function SectionHeader({
  title,
  description,
  actions,
  className,
}: SectionHeaderProps) {
  return (
    <div className={cn('flex flex-wrap items-start justify-between gap-4', className)}>
      <div>
        <h2 className="text-overline text-text-tertiary">{title}</h2>
        {description ? (
          <p className="mt-1 text-body-sm text-text-secondary">{description}</p>
        ) : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </div>
  )
}
