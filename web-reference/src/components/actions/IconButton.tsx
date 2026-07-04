import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { forwardRef } from 'react'
import { Tooltip } from '@/components/tooltip/Tooltip'
import { cn } from '@/lib/cn'
import {
  getIconButtonClassNames,
  iconSizeForIconButton,
  type IconButtonSize,
  type IconButtonVariant,
} from './button-variants'

export type IconButtonProps = Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> & {
  /** Accessible name — required */
  label: string
  variant?: IconButtonVariant
  size?: IconButtonSize
  error?: boolean
  icon: ReactNode
  tooltip?: string
  tooltipDisabled?: boolean
}

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  {
    label,
    variant = 'ghost',
    size = 'md',
    disabled,
    error,
    icon,
    tooltip,
    tooltipDisabled,
    className,
    type = 'button',
    ...props
  },
  ref,
) {
  const iconSize = iconSizeForIconButton(size)
  const tooltipContent = tooltip ?? label

  const button = (
    <button
      ref={ref}
      type={type}
      disabled={disabled}
      aria-label={label}
      aria-invalid={error || undefined}
      className={getIconButtonClassNames({
        variant,
        size,
        disabled,
        error,
        className: cn(
          !disabled && 'active:scale-[0.98] motion-reduce:active:scale-100',
          className,
        ),
      })}
      {...props}
    >
      <span
        className="inline-flex [&>svg]:size-[var(--icon-btn-size)]"
        style={{ '--icon-btn-size': `${iconSize}px` } as React.CSSProperties}
        aria-hidden
      >
        {icon}
      </span>
    </button>
  )

  if (tooltipDisabled || disabled) return button

  return <Tooltip content={tooltipContent}>{button}</Tooltip>
})
