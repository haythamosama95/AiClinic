import * as CheckboxPrimitive from '@radix-ui/react-checkbox'
import { Check, Minus } from 'lucide-react'
import { cn } from '@/lib/cn'

export type CheckboxProps = {
  id?: string
  checked?: boolean | 'indeterminate'
  defaultChecked?: boolean
  onCheckedChange?: (checked: boolean | 'indeterminate') => void
  disabled?: boolean
  invalid?: boolean
  label?: string
  className?: string
}

export function Checkbox({
  id,
  checked,
  defaultChecked,
  onCheckedChange,
  disabled,
  invalid,
  label,
  className,
}: CheckboxProps) {
  const control = (
    <CheckboxPrimitive.Root
      id={id}
      checked={checked}
      defaultChecked={defaultChecked}
      onCheckedChange={onCheckedChange}
      disabled={disabled}
      aria-invalid={invalid || undefined}
      className={cn(
        'focus-ring peer inline-flex size-5 shrink-0 items-center justify-center rounded-sm border border-border-default bg-surface-default',
        'transition-colors duration-[var(--duration-fast)]',
        'data-[state=checked]:border-action-primary data-[state=checked]:bg-action-primary data-[state=checked]:text-action-primary-fg',
        'data-[state=indeterminate]:border-action-primary data-[state=indeterminate]:bg-action-primary data-[state=indeterminate]:text-action-primary-fg',
        'disabled:cursor-not-allowed disabled:opacity-50',
        invalid && 'border-status-danger-border',
        className,
      )}
    >
      <CheckboxPrimitive.Indicator className="flex items-center justify-center">
        {checked === 'indeterminate' ? (
          <Minus className="size-3.5" strokeWidth={3} />
        ) : (
          <Check className="size-3.5" strokeWidth={3} />
        )}
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  )

  if (!label) return control

  return (
    <label
      htmlFor={id}
      className={cn(
        'inline-flex cursor-pointer items-center gap-2 text-body text-text-primary',
        disabled && 'cursor-not-allowed opacity-50',
      )}
    >
      {control}
      <span>{label}</span>
    </label>
  )
}
