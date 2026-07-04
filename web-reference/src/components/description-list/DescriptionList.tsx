import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type DescriptionItem = {
  label: string
  value: ReactNode
  tabular?: boolean
}

export type DescriptionListProps = {
  items: DescriptionItem[]
  columns?: 1 | 2
  className?: string
}

export function DescriptionList({
  items,
  columns = 2,
  className,
}: DescriptionListProps) {
  return (
    <dl
      className={cn(
        'grid gap-4',
        columns === 2 ? 'sm:grid-cols-2' : 'grid-cols-1',
        className,
      )}
    >
      {items.map((item) => (
        <div key={item.label} className="space-y-1">
          <dt className="text-caption text-text-tertiary">{item.label}</dt>
          <dd
            className={cn(
              'text-body text-text-primary',
              item.tabular && 'tabular-nums',
            )}
          >
            {item.value}
          </dd>
        </div>
      ))}
    </dl>
  )
}
