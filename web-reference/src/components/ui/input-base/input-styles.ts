import { cn } from '@/lib/cn'

export type InputSize = 'sm' | 'md' | 'lg'

export const inputSizeClasses: Record<InputSize, string> = {
  sm: 'h-8 text-body-sm',
  md: 'h-9 text-body',
  lg: 'h-11 text-body-lg',
}

export const inputPaddingClasses: Record<InputSize, string> = {
  sm: 'px-3',
  md: 'px-3',
  lg: 'px-4',
}

export function inputFieldClasses({
  size = 'md',
  invalid = false,
  disabled = false,
  readOnly = false,
  className,
}: {
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  readOnly?: boolean
  className?: string
}) {
  return cn(
    'w-full rounded-md border bg-surface-default text-text-primary tabular-nums',
    'placeholder:text-text-placeholder',
    'transition-[border-color,box-shadow] duration-[var(--duration-fast)]',
    'focus:outline-none focus-visible:border-border-focus focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)]',
    inputSizeClasses[size],
    inputPaddingClasses[size],
    invalid
      ? 'border-status-danger-border focus-visible:border-status-danger-fg focus-visible:ring-[color-mix(in_srgb,var(--status-danger-fg)_35%,transparent)]'
      : 'border-border-default',
    disabled && 'cursor-not-allowed bg-action-disabled-bg text-text-disabled',
    readOnly && 'cursor-default bg-surface-sunken',
    className,
  )
}

export function inputAffixClasses(size: InputSize = 'md') {
  return cn(
    'shrink-0 text-text-tertiary tabular-nums',
    size === 'sm' ? 'text-body-sm' : size === 'lg' ? 'text-body-lg' : 'text-body',
  )
}

export function inputWrapperClasses({
  size = 'md',
  invalid = false,
  disabled = false,
  readOnly = false,
  className,
}: {
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  readOnly?: boolean
  className?: string
}) {
  return cn(
    'flex w-full items-center gap-2 rounded-md border bg-surface-default',
    'transition-[border-color,box-shadow] duration-[var(--duration-fast)]',
    'has-[:focus-visible]:border-border-focus has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-[var(--focus-ring)]',
    inputSizeClasses[size],
    inputPaddingClasses[size],
    invalid
      ? 'border-status-danger-border has-[:focus-visible]:border-status-danger-fg has-[:focus-visible]:ring-[color-mix(in_srgb,var(--status-danger-fg)_35%,transparent)]'
      : 'border-border-default',
    disabled && 'cursor-not-allowed bg-action-disabled-bg',
    readOnly && 'bg-surface-sunken',
    className,
  )
}

export function bareInputClasses() {
  return cn(
    'min-w-0 flex-1 border-0 bg-transparent p-0 text-text-primary shadow-none',
    'placeholder:text-text-placeholder focus:outline-none focus-visible:ring-0',
    'disabled:cursor-not-allowed disabled:text-text-disabled',
    'read-only:cursor-default',
  )
}
