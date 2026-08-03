import * as SwitchPrimitive from '@radix-ui/react-switch'
import { cn } from '@/lib/cn'

export type SwitchProps = {
  id?: string
  checked?: boolean
  defaultChecked?: boolean
  onCheckedChange?: (checked: boolean) => void
  disabled?: boolean
  invalid?: boolean
  label?: string
  className?: string
}

export function Switch({
  id,
  checked,
  defaultChecked,
  onCheckedChange,
  disabled,
  invalid,
  label,
  className,
}: SwitchProps) {
  const control = (
    <SwitchPrimitive.Root
      id={id}
      checked={checked}
      defaultChecked={defaultChecked}
      onCheckedChange={onCheckedChange}
      disabled={disabled}
      aria-invalid={invalid || undefined}
      className={cn(
        'focus-ring peer inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border border-border-default bg-surface-muted',
        'transition-colors duration-[var(--duration-fast)]',
        'data-[state=checked]:border-action-primary data-[state=checked]:bg-action-primary',
        'disabled:cursor-not-allowed disabled:opacity-50',
        invalid && 'border-status-danger-border',
        className,
      )}
    >
      <SwitchPrimitive.Thumb
        className={cn(
          'pointer-events-none block size-5 rounded-full bg-surface-default shadow-elevation-1',
          'transition-transform duration-[var(--duration-fast)]',
          'translate-x-0.5 data-[state=checked]:translate-x-[22px]',
          'rtl:data-[state=checked]:-translate-x-[22px]',
        )}
      />
    </SwitchPrimitive.Root>
  )

  if (!label) return control

  return (
    <label
      htmlFor={id}
      className={cn(
        'inline-flex cursor-pointer items-center gap-3 text-body text-text-primary',
        disabled && 'cursor-not-allowed opacity-50',
      )}
    >
      {control}
      <span>{label}</span>
    </label>
  )
}
