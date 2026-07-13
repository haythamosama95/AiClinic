import { Check } from 'lucide-react'
import { cn } from '@/lib/cn'

const STEPS = [
  { id: 'details', label: 'Details' },
  { id: 'schedule', label: 'Schedule' },
] as const

export type BookingStepRailProps = {
  currentStep: number
  className?: string
}

export function BookingStepRail({ currentStep, className }: BookingStepRailProps) {
  return (
    <ol
      className={cn('flex items-start justify-center', className)}
      aria-label="Booking progress"
    >
      {STEPS.map((step, index) => {
        const state =
          index < currentStep ? 'complete' : index === currentStep ? 'current' : 'upcoming'
        const isLast = index === STEPS.length - 1

        return (
          <li key={step.id} className="flex items-start">
            <div
              className="flex w-24 flex-col items-center gap-2"
              aria-current={state === 'current' ? 'step' : undefined}
            >
              <span
                className={cn(
                  'flex size-8 items-center justify-center rounded-full text-body-sm font-medium tabular-nums transition-colors',
                  state === 'complete' &&
                  'bg-action-primary text-action-primary-fg',
                  state === 'current' &&
                  'border border-border-focus bg-surface-default text-text-primary shadow-[0_0_0_3px_var(--focus-ring)]',
                  state === 'upcoming' &&
                  'border border-border-default bg-surface-muted text-text-tertiary',
                )}
                aria-hidden
              >
                {state === 'complete' ? <Check size={15} strokeWidth={2} /> : index + 1}
              </span>
              <span
                className={cn(
                  'text-center text-body-sm',
                  state === 'upcoming' ? 'text-text-tertiary' : 'font-medium text-text-primary',
                )}
              >
                {step.label}
              </span>
            </div>

            {!isLast ? (
              <span
                className={cn(
                  'mx-2 mt-4 h-px w-16 shrink-0 sm:w-24',
                  index < currentStep ? 'bg-action-primary' : 'bg-border-default',
                )}
                aria-hidden
              />
            ) : null}
          </li>
        )
      })}
    </ol>
  )
}
