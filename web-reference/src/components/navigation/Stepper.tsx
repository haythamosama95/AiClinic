import { Check } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'

export type StepState = 'complete' | 'current' | 'upcoming'

export type Step = {
  id: string
  label: string
  description?: string
}

export type StepperProps = {
  steps: Step[]
  currentStep: number
  orientation?: 'horizontal' | 'vertical'
  onBack?: () => void
  onNext?: () => void
  backLabel?: string
  nextLabel?: string
  className?: string
}

function stepState(index: number, current: number): StepState {
  if (index < current) return 'complete'
  if (index === current) return 'current'
  return 'upcoming'
}

export function Stepper({
  steps,
  currentStep,
  orientation = 'horizontal',
  onBack,
  onNext,
  backLabel = 'Back',
  nextLabel = 'Next',
  className,
}: StepperProps) {
  const isVertical = orientation === 'vertical'

  return (
    <div className={cn('space-y-6', className)}>
      <ol
        className={cn(
          'flex',
          isVertical ? 'flex-col gap-0' : 'flex-row items-start gap-0',
        )}
        aria-label="Progress"
      >
        {steps.map((step, index) => {
          const state = stepState(index, currentStep)
          const isLast = index === steps.length - 1

          return (
            <li
              key={step.id}
              className={cn(
                'relative flex',
                isVertical ? 'flex-row gap-3 pb-6' : 'flex-1 flex-col items-center',
                !isLast && isVertical && 'pb-6',
              )}
              aria-current={state === 'current' ? 'step' : undefined}
            >
              <div className={cn('flex items-center', isVertical ? 'flex-col' : 'w-full flex-col')}>
                <div className={cn('flex items-center', isVertical ? 'flex-col' : 'w-full')}>
                  <StepIndicator number={index + 1} state={state} />
                  {!isLast ? (
                    <Connector orientation={orientation} state={state} />
                  ) : null}
                </div>
                <div
                  className={cn(
                    'mt-2 text-center',
                    isVertical && 'mt-0 text-start',
                    !isVertical && 'px-2',
                  )}
                >
                  <p
                    className={cn(
                      'text-body-strong',
                      state === 'upcoming' ? 'text-text-tertiary' : 'text-text-primary',
                    )}
                  >
                    {step.label}
                  </p>
                  {step.description ? (
                    <p className="mt-0.5 text-caption text-text-secondary">{step.description}</p>
                  ) : null}
                </div>
              </div>
            </li>
          )
        })}
      </ol>

      {(onBack || onNext) && (
        <div className="flex justify-between gap-3 border-t border-border-subtle pt-4">
          {onBack ? (
            <Button variant="secondary" onClick={onBack} disabled={currentStep <= 0}>
              {backLabel}
            </Button>
          ) : (
            <span />
          )}
          {onNext ? (
            <Button
              variant="primary"
              onClick={onNext}
              disabled={currentStep >= steps.length - 1}
            >
              {nextLabel}
            </Button>
          ) : null}
        </div>
      )}
    </div>
  )
}

function StepIndicator({ number, state }: { number: number; state: StepState }) {
  return (
    <span
      className={cn(
        'relative z-[1] flex size-8 shrink-0 items-center justify-center rounded-full border text-body-sm font-medium tabular-nums transition-colors',
        state === 'complete' &&
          'border-action-primary bg-action-primary text-action-primary-fg',
        state === 'current' &&
          'border-border-focus bg-surface-default text-text-primary ring-2 ring-[var(--focus-ring)]',
        state === 'upcoming' &&
          'border-border-default bg-surface-default text-text-tertiary',
      )}
    >
      {state === 'complete' ? (
        <Check size={16} strokeWidth={1.5} aria-hidden />
      ) : (
        number
      )}
    </span>
  )
}

function Connector({
  orientation,
  state,
}: {
  orientation: 'horizontal' | 'vertical'
  state: StepState
}) {
  if (orientation === 'vertical') {
    return (
      <span
        className={cn(
          'absolute start-4 top-8 h-[calc(100%-2rem)] w-px -translate-x-1/2',
          state === 'complete' ? 'bg-action-primary' : 'bg-border-default',
        )}
        aria-hidden
      />
    )
  }

  return (
    <span
      className={cn(
        'mx-2 mt-4 h-px flex-1',
        state === 'complete' ? 'bg-action-primary' : 'bg-border-default',
      )}
      aria-hidden
    />
  )
}
