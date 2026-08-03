import * as RadioGroupPrimitive from '@radix-ui/react-radio-group'
import { cn } from '@/lib/cn'

export type RadioOption = {
  value: string
  label: string
  disabled?: boolean
}

export type RadioGroupProps = {
  name?: string
  value?: string
  defaultValue?: string
  onValueChange?: (value: string) => void
  options: RadioOption[]
  orientation?: 'vertical' | 'horizontal'
  disabled?: boolean
  invalid?: boolean
  'aria-labelledby'?: string
  className?: string
}

export function RadioGroup({
  value,
  defaultValue,
  onValueChange,
  options,
  orientation = 'vertical',
  disabled,
  invalid,
  className,
  ...aria
}: RadioGroupProps) {
  return (
    <RadioGroupPrimitive.Root
      value={value}
      defaultValue={defaultValue}
      onValueChange={onValueChange}
      disabled={disabled}
      orientation={orientation}
      className={cn(
        'flex gap-3',
        orientation === 'vertical' ? 'flex-col' : 'flex-row flex-wrap',
        className,
      )}
      aria-invalid={invalid || undefined}
      {...aria}
    >
      {options.map((opt) => (
        <label
          key={opt.value}
          className={cn(
            'inline-flex cursor-pointer items-center gap-2 text-body text-text-primary',
            (disabled || opt.disabled) && 'cursor-not-allowed opacity-50',
          )}
        >
          <RadioGroupPrimitive.Item
            value={opt.value}
            disabled={opt.disabled}
            className={cn(
              'focus-ring inline-flex size-5 shrink-0 items-center justify-center rounded-full border border-border-default bg-surface-default',
              'transition-colors duration-[var(--duration-fast)]',
              'data-[state=checked]:border-action-primary',
              'disabled:cursor-not-allowed',
              invalid && 'border-status-danger-border',
            )}
          >
            <RadioGroupPrimitive.Indicator className="flex items-center justify-center">
              <span className="size-2.5 rounded-full bg-action-primary" />
            </RadioGroupPrimitive.Indicator>
          </RadioGroupPrimitive.Item>
          <span>{opt.label}</span>
        </label>
      ))}
    </RadioGroupPrimitive.Root>
  )
}
