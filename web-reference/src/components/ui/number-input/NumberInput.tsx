import { Minus, Plus } from 'lucide-react'
import {
  forwardRef,
  useCallback,
  type InputHTMLAttributes,
  type KeyboardEvent,
} from 'react'
import { cn } from '@/lib/cn'
import {
  bareInputClasses,
  inputWrapperClasses,
  type InputSize,
} from '../input-base/input-styles'

export type NumberInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'size' | 'type'> & {
  size?: InputSize
  invalid?: boolean
  showSteppers?: boolean
  min?: number
  max?: number
  step?: number
  onValueChange?: (value: number | null) => void
}

function clamp(n: number, min?: number, max?: number) {
  let v = n
  if (min !== undefined) v = Math.max(min, v)
  if (max !== undefined) v = Math.min(max, v)
  return v
}

export const NumberInput = forwardRef<HTMLInputElement, NumberInputProps>(function NumberInput(
  {
    size = 'md',
    invalid,
    showSteppers = true,
    min,
    max,
    step = 1,
    disabled,
    readOnly,
    className,
    value,
    defaultValue,
    onChange,
    onValueChange,
    ...props
  },
  ref,
) {
  const stepValue = (delta: number) => {
    const current = Number(value ?? defaultValue ?? 0)
    const next = clamp(current + delta * step, min, max)
    onValueChange?.(next)
    onChange?.({
      target: { value: String(next) },
    } as React.ChangeEvent<HTMLInputElement>)
  }

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowUp') {
      e.preventDefault()
      stepValue(1)
    } else if (e.key === 'ArrowDown') {
      e.preventDefault()
      stepValue(-1)
    }
  }

  const stepperBtn = useCallback(
    (delta: number, label: string) => (
      <button
        type="button"
        disabled={disabled || readOnly}
        onClick={() => stepValue(delta)}
        className="focus-ring inline-flex size-7 shrink-0 items-center justify-center rounded-sm text-icon-default hover:bg-surface-hover disabled:opacity-50"
        aria-label={label}
      >
        {delta > 0 ? <Plus className="size-4" /> : <Minus className="size-4" />}
      </button>
    ),
    [disabled, readOnly, stepValue],
  )

  return (
    <div
      className={inputWrapperClasses({
        size,
        invalid,
        disabled,
        readOnly,
        className: cn('gap-1', className),
      })}
    >
      {showSteppers ? stepperBtn(-1, 'Decrease') : null}
      <input
        ref={ref}
        type="number"
        inputMode="decimal"
        disabled={disabled}
        readOnly={readOnly}
        min={min}
        max={max}
        step={step}
        value={value}
        defaultValue={defaultValue}
        onChange={onChange}
        onKeyDown={onKeyDown}
        className={cn(bareInputClasses(), 'text-end tabular-nums')}
        {...props}
      />
      {showSteppers ? stepperBtn(1, 'Increase') : null}
    </div>
  )
})
