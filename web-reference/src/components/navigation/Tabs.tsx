import { useCallback, useId, useRef, type KeyboardEvent, type ReactNode } from 'react'
import { motion } from 'motion/react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition } from '@/lib/motion'
import { Signal } from '@/primitives/Signal'

export type TabItem = {
  id: string
  label: ReactNode
  disabled?: boolean
}

export type TabsProps = {
  items: TabItem[]
  value: string
  onChange: (id: string) => void
  variant?: 'underline' | 'segmented' | 'vertical'
  equalWidth?: boolean
  'aria-label'?: string
  className?: string
}

const UNDERLINE_LAYOUT_ID = 'tabs-underline-signal'

export function Tabs({
  items,
  value,
  onChange,
  variant = 'underline',
  equalWidth = false,
  'aria-label': ariaLabel = 'Tabs',
  className,
}: TabsProps) {
  const tablistId = useId()
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([])

  const enabledIndices = items
    .map((item, i) => (!item.disabled ? i : -1))
    .filter((i) => i >= 0)

  const focusTab = useCallback((index: number) => {
    tabRefs.current[index]?.focus()
  }, [])

  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const currentIndex = items.findIndex((item) => item.id === value)
    const currentEnabledPos = enabledIndices.indexOf(currentIndex)
    if (currentEnabledPos < 0) return

    let nextEnabledPos = currentEnabledPos
    const isVertical = variant === 'vertical'

    if (
      (isVertical && event.key === 'ArrowDown') ||
      (!isVertical && event.key === 'ArrowRight')
    ) {
      event.preventDefault()
      nextEnabledPos = (currentEnabledPos + 1) % enabledIndices.length
    } else if (
      (isVertical && event.key === 'ArrowUp') ||
      (!isVertical && event.key === 'ArrowLeft')
    ) {
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
    const nextId = items[nextIndex]?.id
    if (nextId) {
      onChange(nextId)
      focusTab(nextIndex)
    }
  }

  if (variant === 'segmented') {
    return (
      <SegmentedControl
        aria-label={ariaLabel}
        value={value}
        onChange={onChange}
        options={items.map((item) => ({
          value: item.id,
          label: item.label,
          disabled: item.disabled,
        }))}
        className={className}
      />
    )
  }

  if (variant === 'vertical') {
    return (
      <div
        role="tablist"
        aria-label={ariaLabel}
        id={tablistId}
        onKeyDown={handleKeyDown}
        className={cn('flex flex-col gap-0.5', className)}
      >
        {items.map((item, index) => {
          const selected = item.id === value
          return (
            <button
              key={item.id}
              ref={(el) => {
                tabRefs.current[index] = el
              }}
              type="button"
              role="tab"
              aria-selected={selected}
              aria-disabled={item.disabled || undefined}
              tabIndex={selected ? 0 : -1}
              disabled={item.disabled}
              onClick={() => onChange(item.id)}
              className={cn(
                'focus-ring relative rounded-md px-3 py-2 text-start text-body transition-colors',
                'data-[density=compact]:py-1.5 data-[density=comfortable]:py-2.5',
                selected
                  ? 'bg-surface-selected text-text-primary font-medium'
                  : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary',
                item.disabled && 'pointer-events-none text-text-disabled',
              )}
            >
              {item.label}
            </button>
          )
        })}
      </div>
    )
  }

  return (
    <div
      role="tablist"
      aria-label={ariaLabel}
      id={tablistId}
      onKeyDown={handleKeyDown}
      className={cn(
        'flex border-b border-border-subtle',
        equalWidth ? 'w-full gap-0' : 'gap-1',
        className,
      )}
    >
      {items.map((item, index) => {
        const selected = item.id === value
        return (
          <button
            key={item.id}
            ref={(el) => {
              tabRefs.current[index] = el
            }}
            type="button"
            role="tab"
            aria-selected={selected}
            aria-disabled={item.disabled || undefined}
            tabIndex={selected ? 0 : -1}
            disabled={item.disabled}
            onClick={() => onChange(item.id)}
            className={cn(
              'focus-ring relative px-4 pb-3 pt-2 text-body transition-colors',
              'data-[density=compact]:px-3 data-[density=compact]:pb-2',
              equalWidth && 'min-w-0 flex-1 text-center',
              selected
                ? 'text-text-primary font-medium'
                : 'text-text-secondary hover:text-text-primary',
              item.disabled && 'pointer-events-none text-text-disabled',
            )}
          >
            {item.label}
            {selected ? (
              <motion.span
                layoutId={UNDERLINE_LAYOUT_ID}
                className="absolute inset-x-0 bottom-0 flex justify-center"
                transition={resolveTransition(motionPresets.tab)}
              >
                <Signal orientation="horizontal" className="w-full max-w-[calc(100%-8px)]" />
              </motion.span>
            ) : null}
          </button>
        )
      })}
    </div>
  )
}
