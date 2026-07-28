import { Check, ClipboardList, Microscope, Stethoscope } from 'lucide-react'
import { motion } from 'motion/react'
import { cn } from '@/lib/cn'
import { resolveTransition } from '@/lib/motion'
import type { VisitPhase } from './types'

const STEPS: {
  id: Exclude<VisitPhase, 'summary' | 'completed'>
  label: string
  icon: typeof Stethoscope
}[] = [
    { id: 'intake', label: 'Intake', icon: ClipboardList },
    { id: 'findings', label: 'Findings & diagnosis', icon: Microscope },
    { id: 'treatment', label: 'Treatment', icon: Stethoscope },
  ]

export type VisitStepRailProps = {
  currentPhase: VisitPhase
  onPhaseSelect?: (phase: Exclude<VisitPhase, 'summary' | 'completed'>) => void
  className?: string
}

function phaseIndex(phase: VisitPhase): number {
  if (phase === 'summary' || phase === 'completed') return STEPS.length
  return STEPS.findIndex((s) => s.id === phase)
}

function stepState(index: number, current: number, currentPhase: VisitPhase) {
  if (currentPhase === 'summary' || currentPhase === 'completed' || index < current) return 'complete'
  if (index === current) return 'current'
  return 'upcoming'
}

export function VisitStepRail({ currentPhase, onPhaseSelect, className }: VisitStepRailProps) {
  const current = phaseIndex(currentPhase)
  const transition = resolveTransition({ duration: 'quick', ease: 'out' })

  return (
    <ol
      className={cn('flex w-full items-start', className)}
      aria-label="Visit progress"
    >
      {STEPS.map((step, index) => {
        const state = stepState(index, current, currentPhase)
        const isLast = index === STEPS.length - 1
        const Icon = step.icon
        const connectorComplete = index < current || currentPhase === 'summary' || currentPhase === 'completed'
        const clickable = onPhaseSelect && state !== 'upcoming' && currentPhase !== 'summary' && currentPhase !== 'completed'

        return (
          <li
            key={step.id}
            className="relative flex min-w-0 flex-1 flex-col items-center"
            aria-current={state === 'current' ? 'step' : undefined}
          >
            {!isLast ? (
              <span
                className="absolute start-[calc(50%+0.75rem)] top-3 h-px w-[calc(100%-1.5rem)] overflow-hidden bg-border-default"
                aria-hidden
              >
                <motion.span
                  className="block h-full bg-action-primary"
                  initial={false}
                  animate={{ width: connectorComplete ? '100%' : '0%' }}
                  transition={transition}
                />
              </span>
            ) : null}

            <button
              type="button"
              disabled={!clickable}
              onClick={() => clickable && onPhaseSelect(step.id)}
              className={cn(
                'relative z-[1] flex size-6 items-center justify-center rounded-full border transition-all duration-[var(--duration-quick)] sm:size-7',
                state === 'complete' &&
                'border-action-primary bg-action-primary text-action-primary-fg',
                state === 'current' &&
                'border-[var(--color-teal-500)] bg-surface-default text-[var(--color-teal-600)] shadow-[0_0_0_2px_var(--surface-raised),0_0_0_4px_rgba(13,148,136,0.15)]',
                state === 'upcoming' &&
                'border-border-default bg-surface-default text-text-tertiary',
                clickable && 'cursor-pointer hover:border-[var(--color-teal-400)]',
                !clickable && 'cursor-default',
              )}
              aria-label={`${step.label}${state === 'complete' ? ' (completed)' : state === 'current' ? ' (current)' : ''}`}
            >
              {state === 'complete' ? (
                <Check size={12} strokeWidth={2.5} aria-hidden />
              ) : (
                <Icon size={12} strokeWidth={1.75} aria-hidden />
              )}
            </button>

            <p
              className={cn(
                'mt-1 w-full truncate px-1 text-center text-[11px] font-medium leading-tight sm:text-caption',
                state === 'current' ? 'text-[var(--color-teal-700)]' : 'text-text-secondary',
                state === 'upcoming' && 'text-text-tertiary',
              )}
            >
              <span className="hidden sm:inline">{step.label}</span>
              <span className="sm:hidden">
                {step.id === 'findings' ? 'Findings' : step.label}
              </span>
            </p>
          </li>
        )
      })}
    </ol>
  )
}
