import {
  useCallback,
  useId,
  useRef,
  type KeyboardEvent,
  type ReactNode,
} from 'react'
import { cn } from '@/lib/cn'

export type SegmentedOption<T extends string = string> = {
  value: T
  label: ReactNode
  disabled?: boolean
}

export type SegmentedControlProps<T extends string = string> = {
  options: SegmentedOption<T>[]
  value: T
  onChange: (value: T) => void
  /** Accessible label for the group */
  'aria-label': string
  size?: 'sm' | 'md'
  className?: string
}

const sizeStyles = {
  sm: 'h-7 text-body-sm',
  md: 'h-9 text-body-strong',
} as const

export function SegmentedControl<T extends string = string>({
  options,
  value,
  onChange,
  'aria-label': ariaLabel,
  size = 'md',
  className,
}: SegmentedControlProps<T>) {
  const groupId = useId()
  const itemRefs = useRef<(HTMLButtonElement | null)[]>([])

  const enabledIndices = options
    .map((opt, i) => (!opt.disabled ? i : -1))
    .filter((i) => i >= 0)

  const focusItem = useCallback((index: number) => {
    itemRefs.current[index]?.focus()
  }, [])

  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const currentIndex = options.findIndex((opt) => opt.value === value)
    const currentEnabledPos = enabledIndices.indexOf(currentIndex)
    if (currentEnabledPos < 0) return

    let nextEnabledPos = currentEnabledPos

    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
      event.preventDefault()
      nextEnabledPos = (currentEnabledPos + 1) % enabledIndices.length
    } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
      event.preventDefault()
      nextEnabledPos =
        (currentEnabledPos - 1 + enabledIndices.length) % enabledIndices.length
    } else if (event.key === 'Home') {
      event.preventDefault()
      nextEnabledPos = 0
    } else if (event.key === 'End') {
      event.preventDefault()
      nextEnabledPos = enabledIndices.length - 1
    } else {
      return
    }

    const nextIndex = enabledIndices[nextEnabledPos]
    const nextValue = options[nextIndex]?.value
    if (nextValue !== undefined) {
      onChange(nextValue)
      focusItem(nextIndex)
    }
  }

  return (
    <div
      role="radiogroup"
      aria-label={ariaLabel}
      id={groupId}
      onKeyDown={handleKeyDown}
      className={cn(
        'relative inline-flex items-stretch overflow-hidden rounded-md bg-surface-default',
        className,
      )}
    >
      {options.map((option, index) => {
        const selected = option.value === value
        const isFirst = index === 0
        const isLast = index === options.length - 1

        return (
          <button
            key={option.value}
            ref={(el) => {
              itemRefs.current[index] = el
            }}
            type="button"
            role="radio"
            aria-checked={selected}
            tabIndex={selected ? 0 : -1}
            disabled={option.disabled}
            onClick={() => onChange(option.value)}
            className={cn(
              'focus-ring relative inline-flex min-w-[3rem] items-center justify-center px-3 transition-colors duration-[var(--duration-instant)]',
              sizeStyles[size],
              !isFirst && 'border-s border-border-default',
              selected
                ? 'bg-surface-selected text-text-primary'
                : 'bg-transparent text-text-secondary hover:bg-surface-hover hover:text-text-primary',
              option.disabled && 'pointer-events-none text-text-disabled',
              isFirst && 'rounded-s-md',
              isLast && 'rounded-e-md',
            )}
          >
            {option.label}
          </button>
        )
      })}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 rounded-md border border-border-default"
      />
    </div>
  )
}
