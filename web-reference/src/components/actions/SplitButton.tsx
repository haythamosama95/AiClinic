import { ChevronDown } from 'lucide-react'
import { useState } from 'react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { cn } from '@/lib/cn'
import { Button } from './Button'
import type { ButtonSize, ButtonVariant } from './button-variants'

export type SplitButtonMenuItem = {
  id: string
  label: string
  onSelect?: () => void
  disabled?: boolean
  destructive?: boolean
}

export type SplitButtonProps = {
  label: string
  onPrimaryAction?: () => void
  items: SplitButtonMenuItem[]
  variant?: ButtonVariant
  size?: ButtonSize
  disabled?: boolean
  loading?: boolean
  className?: string
}

export function SplitButton({
  label,
  onPrimaryAction,
  items,
  variant = 'primary',
  size = 'md',
  disabled,
  loading,
  className,
}: SplitButtonProps) {
  const [open, setOpen] = useState(false)
  const isDisabled = disabled || loading

  const chevronSizes = { sm: 14, md: 16, lg: 18 } as const

  return (
    <div
      className={cn(
        'inline-flex items-stretch rounded-md',
        isDisabled && 'pointer-events-none opacity-60',
        className,
      )}
    >
      <Button
        variant={variant}
        size={size}
        disabled={isDisabled}
        loading={loading}
        onClick={onPrimaryAction}
        className="rounded-e-none border-e-0"
      >
        {label}
      </Button>

      <DropdownMenu open={open} onOpenChange={setOpen}>
        <DropdownMenuTrigger asChild disabled={isDisabled}>
          <button
            type="button"
            disabled={isDisabled}
            aria-label={`${label} — more options`}
            aria-haspopup="menu"
            aria-expanded={open}
            className={cn(
              'focus-ring inline-flex items-center justify-center rounded-md rounded-s-none border border-border-default',
              'transition-[background-color,transform] duration-[var(--duration-instant)]',
              !isDisabled && 'active:scale-[0.98] motion-reduce:active:scale-100',
              variant === 'primary' &&
                'border-action-primary-hover bg-action-primary text-action-primary-fg hover:bg-action-primary-hover',
              variant === 'secondary' &&
                'bg-action-secondary text-text-primary hover:bg-surface-hover',
              variant === 'ghost' && 'bg-transparent text-text-primary hover:bg-action-subtle-hover',
              variant === 'danger' &&
                'border-action-danger-hover bg-action-danger text-action-danger-fg hover:bg-action-danger-hover',
              variant === 'ai' &&
                'border-action-ai-hover bg-action-ai text-action-ai-fg hover:bg-action-ai-hover',
              size === 'sm' && 'h-7 w-7 min-w-7 px-0',
              size === 'md' && 'h-9 w-9 min-w-9 px-0',
              size === 'lg' && 'h-11 w-11 min-w-11 px-0',
            )}
          >
            <ChevronDown size={chevronSizes[size]} aria-hidden />
          </button>
        </DropdownMenuTrigger>

        {open ? (
          <DropdownMenuContent align="end">
            {items.map((item, index) => (
              <div key={item.id}>
                {index > 0 && items[index - 1]?.destructive !== item.destructive ? (
                  <DropdownMenuSeparator />
                ) : null}
                <DropdownMenuItem
                  destructive={item.destructive}
                  disabled={item.disabled}
                  onSelect={() => {
                    item.onSelect?.()
                    setOpen(false)
                  }}
                >
                  {item.label}
                </DropdownMenuItem>
              </div>
            ))}
          </DropdownMenuContent>
        ) : null}
      </DropdownMenu>
    </div>
  )
}
