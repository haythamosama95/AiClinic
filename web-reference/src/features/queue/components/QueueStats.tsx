import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ChevronLeft, ChevronRight, Minus, TrendingDown, TrendingUp } from 'lucide-react'
import { IconButton } from '@/components/actions/IconButton'
import type { KpiTrend, QueueKpiFilter, QueueStats as QueueStatsType } from '../types'
import { formatDuration, getKpiTrends } from '../utils'

type KpiCardId =
  | QueueKpiFilter
  | 'total'
  | 'avg_wait'
  | 'avg_consult'
  | 'queue_length'

type KpiCard = {
  id: KpiCardId
  label: string
  value: string | number
  valueClassName?: string
}

type QueueStatsProps = {
  stats: QueueStatsType
}

function trendToneClass(trend: KpiTrend): string {
  if (trend.direction === 'flat') return 'text-text-tertiary'
  const isGood =
    (trend.direction === 'up' && trend.favorableUp) ||
    (trend.direction === 'down' && !trend.favorableUp)
  return isGood ? 'text-status-success-fg' : 'text-status-warning-fg'
}

function trendSurfaceClass(trend: KpiTrend | undefined): string {
  if (!trend || trend.direction === 'flat') {
    return 'border-border-default bg-gradient-to-br from-surface-sunken/40 via-surface-default to-surface-default'
  }
  const isGood =
    (trend.direction === 'up' && trend.favorableUp) ||
    (trend.direction === 'down' && !trend.favorableUp)
  if (isGood) {
    return 'border-status-success-border/40 bg-gradient-to-br from-status-success-surface/70 via-surface-default to-surface-default'
  }
  return 'border-status-warning-border/40 bg-gradient-to-br from-status-warning-surface/70 via-surface-default to-surface-default'
}

function TrendIndicator({ trend }: { trend: KpiTrend }) {
  const tone = trendToneClass(trend)
  const Icon =
    trend.direction === 'up' ? TrendingUp : trend.direction === 'down' ? TrendingDown : Minus

  return (
    <span className={`inline-flex items-center gap-1 text-xs font-medium ${tone}`}>
      <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <span>{trend.label}</span>
    </span>
  )
}

export function QueueStats({ stats }: QueueStatsProps) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const [canScrollLeft, setCanScrollLeft] = useState(false)
  const [canScrollRight, setCanScrollRight] = useState(false)
  const trends = useMemo(() => getKpiTrends(), [])

  const cards: KpiCard[] = [
    { id: 'total', label: 'Total today', value: stats.total },
    {
      id: 'waiting',
      label: 'Waiting',
      value: stats.waiting,
      valueClassName: 'text-status-warning-fg',
    },
    {
      id: 'checked_in',
      label: 'Checked in',
      value: stats.checkedIn,
      valueClassName: 'text-action-primary',
    },
    {
      id: 'in_progress',
      label: 'In progress',
      value: stats.inProgress,
      valueClassName: 'text-status-info-fg',
    },
    {
      id: 'completed',
      label: 'Completed',
      value: stats.completed,
      valueClassName: 'text-status-success-fg',
    },
    {
      id: 'queue_length',
      label: 'Queue length',
      value: stats.currentQueueLength,
    },
    {
      id: 'avg_wait',
      label: 'Avg wait',
      value: formatDuration(stats.avgWaitMinutes),
    },
    {
      id: 'avg_consult',
      label: 'Avg consult',
      value: formatDuration(stats.avgConsultationMinutes),
    },
    { id: 'cancelled', label: 'Cancelled', value: stats.cancelled },
    {
      id: 'no_show',
      label: 'No show',
      value: stats.noShow,
      valueClassName: 'text-status-danger-fg',
    },
  ]

  const updateScrollState = useCallback(() => {
    const el = scrollRef.current
    if (!el) return
    setCanScrollLeft(el.scrollLeft > 4)
    setCanScrollRight(el.scrollLeft + el.clientWidth < el.scrollWidth - 4)
  }, [])

  useEffect(() => {
    const el = scrollRef.current
    if (!el) return
    updateScrollState()
    el.addEventListener('scroll', updateScrollState, { passive: true })
    const observer = new ResizeObserver(updateScrollState)
    observer.observe(el)
    return () => {
      el.removeEventListener('scroll', updateScrollState)
      observer.disconnect()
    }
  }, [updateScrollState, cards.length])

  function scrollByDirection(direction: 'left' | 'right') {
    const el = scrollRef.current
    if (!el) return
    const cardWidth = el.querySelector<HTMLElement>('[data-kpi-card]')?.offsetWidth ?? 180
    el.scrollBy({
      left: direction === 'left' ? -cardWidth * 2 : cardWidth * 2,
      behavior: 'smooth',
    })
  }

  return (
    <div className="relative" role="region" aria-label="Queue statistics carousel">
      <div className="pointer-events-none absolute inset-y-0 left-0 z-10 hidden w-10 bg-gradient-to-r from-surface-canvas to-transparent lg:block" />
      <div className="pointer-events-none absolute inset-y-0 right-0 z-10 hidden w-10 bg-gradient-to-l from-surface-canvas to-transparent lg:block" />

      <div className="flex items-center gap-2">
        <IconButton
          icon={<ChevronLeft className="h-4 w-4" />}
          label="Scroll statistics left"
          size="sm"
          variant="secondary"
          disabled={!canScrollLeft}
          onClick={() => scrollByDirection('left')}
          className="shrink-0"
        />

        <div
          ref={scrollRef}
          className="flex min-w-0 flex-1 gap-3 overflow-x-auto scroll-smooth pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          role="group"
          aria-label="Queue KPI cards"
        >
          {cards.map((card) => {
            const trend = trends[card.id]

            return (
              <div
                key={card.id}
                data-kpi-card
                className={`flex min-w-[calc(50%-0.375rem)] shrink-0 snap-start flex-col rounded-xl border px-4 py-4 text-left sm:min-w-[calc(33.333%-0.5rem)] md:min-w-[calc(25%-0.5625rem)] lg:min-w-[calc(20%-0.6rem)] xl:min-w-[calc(16.666%-0.625rem)] ${trendSurfaceClass(trend)}`}
                aria-label={`${card.label}: ${card.value}${trend ? `, ${trend.label}` : ''}`}
              >
                <span
                  className={`queue-mono text-2xl font-semibold leading-none tracking-tight text-text-primary sm:text-3xl ${card.valueClassName ?? ''}`}
                >
                  {card.value}
                </span>
                <span className="mt-2 text-xs font-medium text-text-secondary">{card.label}</span>
                {trend && (
                  <span className="mt-2">
                    <TrendIndicator trend={trend} />
                  </span>
                )}
              </div>
            )
          })}
        </div>

        <IconButton
          icon={<ChevronRight className="h-4 w-4" />}
          label="Scroll statistics right"
          size="sm"
          variant="secondary"
          disabled={!canScrollRight}
          onClick={() => scrollByDirection('right')}
          className="shrink-0"
        />
      </div>
    </div>
  )
}
