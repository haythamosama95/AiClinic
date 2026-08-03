import { type ButtonHTMLAttributes, type ReactNode } from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/cn'

export type ChipProps = Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onSelect'> & {
  children: ReactNode
  /** Shows a remove control */
  removable?: boolean
  onRemove?: () => void
  /** Toggle-style filter chip */
  selectable?: boolean
  selected?: boolean
  onSelect?: () => void
}

export function Chip({
  children,
  removable = false,
  onRemove,
  selectable = false,
  selected = false,
  onSelect,
  disabled,
  className,
  onClick,
  ...props
}: ChipProps) {
  const handleClick = (event: React.MouseEvent<HTMLButtonElement>) => {
    if (selectable) onSelect?.()
    onClick?.(event)
  }

  const handleRemove = (event: React.MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation()
    onRemove?.()
  }

  return (
    <span
      className={cn(
        'inline-flex max-w-full items-center rounded-sm border text-body-sm',
        selected
          ? 'border-border-focus bg-surface-selected text-text-primary'
          : 'border-border-default bg-surface-default text-text-secondary',
        disabled && 'opacity-60',
        className,
      )}
    >
      {selectable ? (
        <button
          type="button"
          disabled={disabled}
          aria-pressed={selected}
          onClick={handleClick}
          className={cn(
            'focus-ring inline-flex min-h-6 items-center gap-1 px-2 py-0.5',
            'transition-colors duration-[var(--duration-instant)]',
            !selected && 'hover:bg-surface-hover',
            disabled && 'pointer-events-none',
          )}
          {...props}
        >
          {children}
        </button>
      ) : (
        <span className="inline-flex items-center gap-1 px-2 py-0.5 text-text-secondary">
          {children}
        </span>
      )}

      {removable ? (
        <button
          type="button"
          disabled={disabled}
          onClick={handleRemove}
          aria-label={`Remove ${typeof children === 'string' ? children : 'filter'}`}
          className={cn(
            'focus-ring inline-flex size-6 shrink-0 items-center justify-center rounded-sm',
            'text-icon-muted transition-colors duration-[var(--duration-instant)]',
            'hover:bg-surface-hover hover:text-icon-default',
            disabled && 'pointer-events-none',
          )}
        >
          <X size={14} strokeWidth={1.5} aria-hidden />
        </button>
      ) : null}
    </span>
  )
}
