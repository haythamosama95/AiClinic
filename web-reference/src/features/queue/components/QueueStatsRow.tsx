import {
  CalendarClock,
  CheckCircle2,
  Clock,
  Hourglass,
  Stethoscope,
  UserCheck,
} from 'lucide-react'
import { motion } from 'motion/react'
import type { LucideIcon } from 'lucide-react'
import { Card } from '@/components/card/Card'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import { formatWaitDuration } from '@/features/queue/queue-status'
import type { QueueStats } from '@/features/queue/types'

export type QueueStatsRowProps = {
  stats: QueueStats
  className?: string
}

type StatConfig = {
  key: string
  label: string
  icon: LucideIcon
  getValue: (stats: QueueStats) => string | number
  isWarning?: (stats: QueueStats) => boolean
}

const STAT_CONFIG: StatConfig[] = [
  {
    key: 'scheduled',
    label: 'Scheduled',
    icon: CalendarClock,
    getValue: (s) => s.scheduled,
  },
  {
    key: 'checkedIn',
    label: 'Checked in',
    icon: UserCheck,
    getValue: (s) => s.checkedIn,
  },
  {
    key: 'waiting',
    label: 'Waiting',
    icon: Hourglass,
    getValue: (s) => s.waiting,
    isWarning: (s) => s.waiting >= 3,
  },
  {
    key: 'inConsultation',
    label: 'In consultation',
    icon: Stethoscope,
    getValue: (s) => s.inConsultation,
  },
  {
    key: 'completed',
    label: 'Completed',
    icon: CheckCircle2,
    getValue: (s) => s.completed,
  },
  {
    key: 'avgWait',
    label: 'Avg wait',
    icon: Clock,
    getValue: (s) => formatWaitDuration(s.avgWaitMinutes),
    isWarning: (s) => s.avgWaitMinutes >= 20,
  },
]

export function QueueStatsRow({ stats, className }: QueueStatsRowProps) {
  const transition = resolveTransition(motionPresets.fade)

  return (
    <div
      className={cn(
        'grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6',
        className,
      )}
      role="list"
      aria-label="Queue statistics"
    >
      {STAT_CONFIG.map((config, index) => {
        const Icon = config.icon
        const warning = config.isWarning?.(stats) ?? false
        const value = config.getValue(stats)

        return (
          <motion.div
            key={config.key}
            role="listitem"
            initial={getReducedMotion() ? false : { opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{
              ...transition,
              delay: getReducedMotion() ? 0 : index * 0.05,
            }}
          >
            <Card
              variant="raised"
              padding="sm"
              className={cn(
                'relative overflow-hidden',
                warning && 'border-status-warning-border bg-status-warning-surface/40',
              )}
            >
              <div
                aria-hidden
                className={cn(
                  'pointer-events-none absolute inset-0 opacity-[0.06]',
                  warning
                    ? 'bg-[linear-gradient(135deg,var(--status-warning-fg)_0%,transparent_70%)]'
                    : 'bg-[linear-gradient(135deg,var(--color-teal-400)_0%,transparent_70%)]',
                )}
              />

              <div className="relative flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p
                    className={cn(
                      'font-mono text-h3 tabular-nums leading-none',
                      warning ? 'text-status-warning-fg' : 'text-text-primary',
                    )}
                  >
                    {value}
                  </p>
                  <p className="mt-1.5 text-caption text-text-secondary">{config.label}</p>
                </div>
                <span
                  className={cn(
                    'flex size-8 shrink-0 items-center justify-center rounded-lg',
                    warning
                      ? 'bg-status-warning-surface text-status-warning-fg'
                      : 'bg-surface-selected text-text-link',
                  )}
                >
                  <Icon size={15} strokeWidth={1.75} aria-hidden />
                </span>
              </div>
            </Card>
          </motion.div>
        )
      })}
    </div>
  )
}
