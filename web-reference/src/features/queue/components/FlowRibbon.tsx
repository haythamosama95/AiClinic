import { motion } from 'motion/react'
import { useMemo } from 'react'
import { cn } from '@/lib/cn'
import { getReducedMotion, resolveTransition } from '@/lib/motion'
import type { QueueAppointment, QueueAppointmentStatus } from '@/features/queue/types'

export type FlowRibbonProps = {
  appointments: QueueAppointment[]
  className?: string
}

type FlowStage = {
  id: string
  label: string
  statuses: QueueAppointmentStatus[]
}

const FLOW_STAGES: FlowStage[] = [
  { id: 'scheduled', label: 'Scheduled', statuses: ['scheduled', 'confirmed'] },
  { id: 'checked_in', label: 'Checked in', statuses: ['checked_in'] },
  { id: 'waiting', label: 'Waiting', statuses: ['waiting', 'ready'] },
  { id: 'with_doctor', label: 'With doctor', statuses: ['in_consultation'] },
  { id: 'done', label: 'Done', statuses: ['completed'] },
]

function countByStage(appointments: QueueAppointment[], statuses: QueueAppointmentStatus[]) {
  return appointments.filter((a) => statuses.includes(a.status)).length
}

export function FlowRibbon({ appointments, className }: FlowRibbonProps) {
  const counts = useMemo(
    () =>
      FLOW_STAGES.map((stage) => ({
        ...stage,
        count: countByStage(appointments, stage.statuses),
      })),
    [appointments],
  )

  const maxCount = Math.max(...counts.map((s) => s.count), 1)
  const transition = resolveTransition({ duration: 'quick', ease: 'out' })

  return (
    <div
      className={cn(
        'relative overflow-hidden rounded-2xl border border-border-subtle bg-surface-default/80 p-4 backdrop-blur-sm sm:p-5',
        className,
      )}
      aria-label="Patient flow"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-[linear-gradient(120deg,var(--color-teal-50)_0%,transparent_45%,var(--color-teal-100)/30_100%)] opacity-60"
      />

      <ol className="relative flex w-full min-w-0 items-start gap-1 overflow-x-auto pb-1 sm:gap-0 sm:overflow-visible sm:pb-0">
        {counts.map((stage, index) => {
          const isLast = index === counts.length - 1
          const fillRatio = stage.count / maxCount
          const hasPatients = stage.count > 0

          return (
            <li
              key={stage.id}
              className="relative flex min-w-0 flex-1 flex-col items-center"
              aria-label={`${stage.label}: ${stage.count} patients`}
            >
              {!isLast ? (
                <span
                  className="absolute start-[calc(50%+1.25rem)] top-4 hidden h-0.5 w-[calc(100%-2.5rem)] overflow-hidden rounded-full bg-border-subtle sm:block"
                  aria-hidden
                >
                  <motion.span
                    className="block h-full rounded-full bg-[linear-gradient(90deg,var(--color-teal-400),var(--color-teal-600))]"
                    initial={false}
                    animate={{ width: `${Math.max(fillRatio * 100, hasPatients ? 18 : 0)}%` }}
                    transition={transition}
                  />
                </span>
              ) : null}

              <motion.div
                initial={getReducedMotion() ? false : { scale: 0.9, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{
                  ...transition,
                  delay: getReducedMotion() ? 0 : index * 0.06,
                }}
                className={cn(
                  'relative z-[1] flex min-w-[2.75rem] flex-col items-center rounded-xl border px-2 py-2 transition-colors sm:min-w-0 sm:px-3',
                  hasPatients
                    ? 'border-[var(--color-teal-300)] bg-surface-selected shadow-[0_0_0_1px_rgba(14,138,143,0.08)]'
                    : 'border-border-subtle bg-surface-default',
                )}
              >
                <span
                  className={cn(
                    'font-mono text-h3 tabular-nums leading-none',
                    hasPatients ? 'text-[var(--color-teal-700)]' : 'text-text-tertiary',
                  )}
                >
                  {stage.count}
                </span>
                <span
                  className={cn(
                    'mt-1 max-w-full truncate text-center text-[10px] font-medium leading-tight sm:text-caption',
                    hasPatients ? 'text-text-primary' : 'text-text-tertiary',
                  )}
                >
                  {stage.label}
                </span>
              </motion.div>
            </li>
          )
        })}
      </ol>
    </div>
  )
}
