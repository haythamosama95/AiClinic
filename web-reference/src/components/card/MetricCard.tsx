import { TrendingDown, TrendingUp } from 'lucide-react'
import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'
import { Card } from './Card'

export type MetricDelta = {
  value: string
  direction: 'up' | 'down'
  positive?: boolean
}

export type MetricCardProps = {
  label: string
  value: string
  delta?: MetricDelta
  caption?: string
  sparkline?: ReactNode
  className?: string
}

export function MetricCard({
  label,
  value,
  delta,
  caption,
  sparkline,
  className,
}: MetricCardProps) {
  const deltaPositive = delta?.positive ?? delta?.direction === 'up'

  return (
    <Card variant="raised" className={cn('space-y-3', className)}>
      <p className="text-overline text-text-tertiary">{label}</p>
      <div className="flex items-end justify-between gap-4">
        <p className="text-display tabular-nums text-text-primary">{value}</p>
        {sparkline ? <div className="shrink-0">{sparkline}</div> : null}
      </div>
      {delta ? (
        <div className="flex items-center gap-1.5">
          {delta.direction === 'up' ? (
            <TrendingUp
              size={14}
              className={cn(deltaPositive ? 'text-status-success-fg' : 'text-status-danger-fg')}
              aria-hidden
            />
          ) : (
            <TrendingDown
              size={14}
              className={cn(deltaPositive ? 'text-status-success-fg' : 'text-status-danger-fg')}
              aria-hidden
            />
          )}
          <span
            className={cn(
              'text-body-sm tabular-nums',
              deltaPositive ? 'text-status-success-fg' : 'text-status-danger-fg',
            )}
          >
            {delta.value}
          </span>
        </div>
      ) : null}
      {caption ? <p className="text-caption text-text-secondary">{caption}</p> : null}
    </Card>
  )
}
