import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type ListItemProps = {
  leading?: ReactNode
  primary: ReactNode
  secondary?: ReactNode
  trailing?: ReactNode
  selected?: boolean
  onClick?: () => void
  className?: string
}

export function ListItem({
  leading,
  primary,
  secondary,
  trailing,
  selected,
  onClick,
  className,
}: ListItemProps) {
  const interactive = Boolean(onClick)

  return (
    <div
      role={interactive ? 'button' : undefined}
      tabIndex={interactive ? 0 : undefined}
      onClick={onClick}
      onKeyDown={
        interactive
          ? (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault()
              onClick?.()
            }
          }
          : undefined
      }
      className={cn(
        'flex items-center gap-3 px-4 py-3',
        interactive && 'focus-ring cursor-pointer hover:bg-surface-hover',
        selected && 'bg-surface-selected',
        className,
      )}
      aria-selected={selected}
    >
      {leading ? <div className="shrink-0">{leading}</div> : null}
      <div className="min-w-0 flex-1">
        <p className="truncate text-body text-text-primary">{primary}</p>
        {secondary ? (
          <p className="truncate text-body-sm text-text-secondary">{secondary}</p>
        ) : null}
      </div>
      {trailing ? <div className="shrink-0">{trailing}</div> : null}
    </div>
  )
}

export type ListProps = {
  children: ReactNode
  divided?: boolean
  className?: string
  'aria-label'?: string
}

export function List({
  children,
  divided = true,
  className,
  'aria-label': ariaLabel,
}: ListProps) {
  return (
    <div
      role="list"
      aria-label={ariaLabel}
      className={cn(
        'rounded-lg border border-border-default bg-surface-default',
        divided && '[&>*+*]:border-t [&>*+*]:border-border-subtle',
        className,
      )}
    >
      {children}
    </div>
  )
}
