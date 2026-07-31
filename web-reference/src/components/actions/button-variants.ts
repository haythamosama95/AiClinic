import { cn } from '@/lib/cn'

export type ButtonVariant =
  | 'primary'
  | 'secondary'
  | 'ghost'
  | 'danger'
  | 'ai'
  | 'link'

export type ButtonSize = 'sm' | 'md' | 'lg'

export type IconButtonVariant = 'ghost' | 'secondary' | 'danger' | 'ai'

export type IconButtonSize = 'sm' | 'md' | 'lg'

const sizeStyles: Record<ButtonSize, string> = {
  sm: 'h-7 min-h-7 min-w-[4.5rem] gap-1.5 px-2 text-body-sm',
  md: 'h-9 min-h-9 min-w-[5.5rem] gap-2 px-3 text-body-strong',
  lg: 'h-11 min-h-11 min-w-[6.5rem] gap-2 px-4 text-body-strong',
}

const iconButtonSizeStyles: Record<IconButtonSize, string> = {
  sm: 'size-7 min-h-7 min-w-7',
  md: 'size-8 min-h-8 min-w-8',
  lg: 'size-10 min-h-10 min-w-10',
}

const variantStyles: Record<ButtonVariant, string> = {
  primary: cn(
    'bg-action-primary text-action-primary-fg',
    'hover:bg-action-primary-hover active:bg-action-primary-active',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
  secondary: cn(
    'border border-border-default bg-action-secondary text-action-secondary-fg',
    'hover:bg-surface-hover active:bg-surface-muted',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
  ghost: cn(
    'bg-transparent text-text-primary',
    'hover:bg-action-subtle-hover active:bg-surface-muted',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
  danger: cn(
    'bg-action-danger text-action-danger-fg',
    'hover:bg-action-danger-hover active:bg-action-danger-active',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
  ai: cn(
    'bg-action-ai text-action-ai-fg',
    'hover:bg-action-ai-hover active:bg-action-ai',
    'focus-visible:outline-[var(--focus-ring-ai)]',
  ),
  link: cn(
    'min-w-0 bg-transparent px-0 text-text-link underline-offset-4',
    'hover:underline active:text-text-primary',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
}

const iconButtonVariantStyles: Record<IconButtonVariant, string> = {
  ghost: cn(
    'bg-transparent text-icon-default',
    'hover:bg-action-subtle-hover hover:text-text-primary active:bg-surface-muted',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
  secondary: cn(
    'border border-border-default bg-action-secondary text-icon-default',
    'hover:bg-surface-hover hover:text-text-primary active:bg-surface-muted',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
  danger: cn(
    'bg-transparent text-status-danger-fg',
    'hover:bg-status-danger-surface active:bg-status-danger-surface',
    'focus-visible:outline-[var(--focus-ring)]',
  ),
  ai: cn(
    'bg-transparent text-text-ai',
    'hover:bg-surface-ai active:bg-surface-ai',
    'focus-visible:outline-[var(--focus-ring-ai)]',
  ),
}

const disabledStyles =
  'pointer-events-none bg-action-disabled-bg text-text-disabled border-transparent shadow-none'

const errorStyles = 'ring-2 ring-status-danger-border ring-offset-2 ring-offset-surface-default'

export function buttonBaseClass() {
  return cn(
    'focus-ring inline-flex items-center justify-center rounded-md',
    'transition-[background-color,border-color,color,transform,box-shadow]',
    'duration-[var(--duration-instant)]',
    'disabled:pointer-events-none',
  )
}

export function getButtonClassNames({
  variant,
  size,
  disabled,
  loading,
  error,
  className,
}: {
  variant: ButtonVariant
  size: ButtonSize
  disabled?: boolean
  loading?: boolean
  error?: boolean
  className?: string
}) {
  const isDisabled = disabled || loading

  return cn(
    buttonBaseClass(),
    variant !== 'link' && sizeStyles[size],
    variantStyles[variant],
    isDisabled && variant !== 'link' && disabledStyles,
    isDisabled && variant === 'link' && 'pointer-events-none text-text-disabled no-underline',
    error && !isDisabled && errorStyles,
    className,
  )
}

export function getIconButtonClassNames({
  variant,
  size,
  disabled,
  error,
  className,
}: {
  variant: IconButtonVariant
  size: IconButtonSize
  disabled?: boolean
  error?: boolean
  className?: string
}) {
  return cn(
    buttonBaseClass(),
    iconButtonSizeStyles[size],
    iconButtonVariantStyles[variant],
    disabled && disabledStyles,
    error && !disabled && errorStyles,
    className,
  )
}

export function iconSizeForButton(size: ButtonSize): number {
  return size === 'lg' ? 20 : 16
}

export function iconSizeForIconButton(size: IconButtonSize): number {
  return size === 'lg' ? 20 : 16
}
