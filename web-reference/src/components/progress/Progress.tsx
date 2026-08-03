import { type HTMLAttributes } from 'react'
import { cn } from '@/lib/cn'

export type ProgressVariant = 'bar' | 'circular' | 'steps'

export type ProgressProps = HTMLAttributes<HTMLDivElement> & {
  variant?: ProgressVariant
  /** 0–100 for bar and circular determinate */
  value?: number
  /** Total steps for `steps` variant */
  steps?: number
  /** Current step (1-based) for `steps` variant */
  currentStep?: number
  /** Show percent label on bar variant */
  showLabel?: boolean
  indeterminate?: boolean
  size?: 'sm' | 'md'
}

export function Progress({
  variant = 'bar',
  value = 0,
  steps = 4,
  currentStep = 1,
  showLabel = false,
  indeterminate = false,
  size = 'md',
  className,
  ...props
}: ProgressProps) {
  const clamped = Math.min(100, Math.max(0, value))

  if (variant === 'circular') {
    const dim = size === 'sm' ? 20 : 28
    const stroke = 2
    const radius = (dim - stroke) / 2
    const circumference = 2 * Math.PI * radius
    const offset = indeterminate
      ? circumference * 0.75
      : circumference - (clamped / 100) * circumference

    return (
      <div
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={indeterminate ? undefined : clamped}
        aria-label={indeterminate ? 'Loading' : `${clamped}% complete`}
        className={cn('inline-flex', className)}
        {...props}
      >
        <svg
          width={dim}
          height={dim}
          viewBox={`0 0 ${dim} ${dim}`}
          className={cn(indeterminate && 'progress-spin')}
        >
          <circle
            cx={dim / 2}
            cy={dim / 2}
            r={radius}
            fill="none"
            stroke="var(--surface-muted)"
            strokeWidth={stroke}
          />
          <circle
            cx={dim / 2}
            cy={dim / 2}
            r={radius}
            fill="none"
            stroke="var(--action-primary)"
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={offset}
            transform={`rotate(-90 ${dim / 2} ${dim / 2})`}
            className="transition-[stroke-dashoffset] duration-[var(--duration-base)] ease-[var(--ease-linear)]"
          />
        </svg>
      </div>
    )
  }

  if (variant === 'steps') {
    const safeStep = Math.min(Math.max(1, currentStep), steps)
    return (
      <div
        role="progressbar"
        aria-valuemin={1}
        aria-valuemax={steps}
        aria-valuenow={safeStep}
        aria-label={`Step ${safeStep} of ${steps}`}
        className={cn('flex gap-1', className)}
        {...props}
      >
        {Array.from({ length: steps }, (_, index) => {
          const stepNumber = index + 1
          const isComplete = stepNumber < safeStep
          const isCurrent = stepNumber === safeStep
          return (
            <span
              key={stepNumber}
              className={cn(
                'h-1 flex-1 rounded-full transition-colors duration-[var(--duration-instant)]',
                isComplete || isCurrent ? 'bg-action-primary' : 'bg-surface-muted',
                isCurrent && 'opacity-80',
              )}
              aria-hidden
            />
          )
        })}
      </div>
    )
  }

  return (
    <div className={cn('w-full', className)} {...props}>
      <div
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={indeterminate ? undefined : clamped}
        aria-label={indeterminate ? 'Loading' : `${clamped}% complete`}
        className={cn(
          'w-full overflow-hidden rounded-full bg-surface-muted',
          size === 'sm' ? 'h-1' : 'h-1.5',
        )}
      >
        <div
          className={cn(
            'h-full rounded-full bg-action-primary transition-[width] duration-[var(--duration-base)] ease-[var(--ease-linear)]',
            indeterminate && 'progress-indeterminate w-1/3',
          )}
          style={indeterminate ? undefined : { width: `${clamped}%` }}
        />
      </div>
      {showLabel ? (
        <p className="mt-1 text-end text-caption text-text-tertiary tabular-nums">
          {clamped}%
        </p>
      ) : null}
    </div>
  )
}
