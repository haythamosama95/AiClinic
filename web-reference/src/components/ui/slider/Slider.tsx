import * as SliderPrimitive from '@radix-ui/react-slider'
import { cn } from '@/lib/cn'

export type SliderProps = {
  id?: string
  value?: number[]
  defaultValue?: number[]
  onValueChange?: (value: number[]) => void
  min?: number
  max?: number
  step?: number
  disabled?: boolean
  invalid?: boolean
  showValue?: boolean
  formatValue?: (value: number) => string
  'aria-labelledby'?: string
  className?: string
}

export function Slider({
  id,
  value,
  defaultValue = [50],
  onValueChange,
  min = 0,
  max = 100,
  step = 1,
  disabled,
  invalid,
  showValue = true,
  formatValue = (v) => `${v}%`,
  className,
  ...aria
}: SliderProps) {
  const current = value ?? defaultValue

  return (
    <div className={cn('flex flex-col gap-2', className)}>
      {showValue ? (
        <output
          htmlFor={id}
          className="text-body-strong text-text-primary tabular-nums"
          aria-live="polite"
        >
          {formatValue(current[0] ?? 0)}
        </output>
      ) : null}
      <SliderPrimitive.Root
        id={id}
        value={value}
        defaultValue={defaultValue}
        onValueChange={onValueChange}
        min={min}
        max={max}
        step={step}
        disabled={disabled}
        aria-invalid={invalid || undefined}
        className={cn(
          'relative flex w-full touch-none select-none items-center',
          disabled && 'opacity-50',
        )}
        {...aria}
      >
        <SliderPrimitive.Track className="relative h-1.5 w-full grow overflow-hidden rounded-full bg-surface-muted">
          <SliderPrimitive.Range className="absolute h-full bg-action-primary" />
        </SliderPrimitive.Track>
        <SliderPrimitive.Thumb
          className={cn(
            'focus-ring block size-5 rounded-full border border-border-default bg-surface-default shadow-elevation-1',
            'transition-transform duration-[var(--duration-fast)]',
            'hover:scale-105 active:scale-95',
            invalid && 'border-status-danger-border',
          )}
        />
      </SliderPrimitive.Root>
    </div>
  )
}
