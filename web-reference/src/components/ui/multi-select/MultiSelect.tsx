import { useId, useRef, useState } from 'react'
import { cn } from '@/lib/cn'
import { Chip } from '@/components/chip'
import { bareInputClasses, inputWrapperClasses, type InputSize } from '../input-base/input-styles'
import { Popover } from '../popover/Popover'
import type { ComboboxItem } from '../combobox/Combobox'

export type MultiSelectProps = {
  id?: string
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  placeholder?: string
  value?: ComboboxItem[]
  onValueChange?: (items: ComboboxItem[]) => void
  options: ComboboxItem[]
  allLabel?: string
  className?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
}

export function MultiSelect({
  id: idProp,
  size = 'md',
  invalid,
  disabled,
  placeholder = 'Select items',
  value = [],
  onValueChange,
  options,
  allLabel = 'All branches',
  className,
  ...aria
}: MultiSelectProps) {
  const autoId = useId()
  const id = idProp ?? autoId
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const inputRef = useRef<HTMLInputElement>(null)
  const listId = `${id}-listbox`

  const selectedIds = new Set(value.map((v) => v.id))
  const filtered = options.filter(
    (o) =>
      !selectedIds.has(o.id) &&
      (o.label.toLowerCase().includes(query.toLowerCase()) ||
        o.meta?.toLowerCase().includes(query.toLowerCase())),
  )

  const toggle = (item: ComboboxItem) => {
    if (item.disabled) return
    const exists = selectedIds.has(item.id)
    onValueChange?.(
      exists ? value.filter((v) => v.id !== item.id) : [...value, item],
    )
    setQuery('')
    inputRef.current?.focus()
  }

  const remove = (id: string) => {
    onValueChange?.(value.filter((v) => v.id !== id))
  }

  const selectAll = () => {
    const all = options.filter((o) => !o.disabled)
    onValueChange?.(all)
    setOpen(false)
  }

  return (
    <Popover
      open={open && !disabled}
      onOpenChange={setOpen}
      contentClassName="min-w-[var(--radix-popover-trigger-width)] w-80 p-0"
      trigger={
        <div
          className={cn(
            inputWrapperClasses({ size, invalid, disabled, className }),
            'h-auto min-h-9 flex-wrap py-1.5',
          )}
          onClick={() => inputRef.current?.focus()}
        >
          {value.map((item) => (
            <Chip
              key={item.id}
              removable
              disabled={disabled}
              onRemove={() => remove(item.id)}
            >
              {item.label}
            </Chip>
          ))}
          <input
            ref={inputRef}
            id={id}
            role="combobox"
            aria-expanded={open}
            aria-controls={listId}
            disabled={disabled}
            value={query}
            placeholder={value.length === 0 ? placeholder : undefined}
            onChange={(e) => {
              setQuery(e.target.value)
              setOpen(true)
            }}
            onFocus={() => setOpen(true)}
            className={cn(bareInputClasses(), 'min-w-[8ch] flex-1')}
            {...aria}
          />
        </div>
      }
    >
      <div id={listId} role="listbox" className="max-h-60 overflow-auto py-1">
        <button
          type="button"
          className="focus-ring w-full px-3 py-2 text-start text-body text-text-link hover:bg-surface-hover"
          onClick={selectAll}
        >
          {allLabel}
        </button>
        {filtered.length === 0 ? (
          <p className="px-3 py-4 text-center text-caption text-text-tertiary">No more options</p>
        ) : (
          filtered.map((item) => (
            <button
              key={item.id}
              type="button"
              role="option"
              aria-selected={selectedIds.has(item.id)}
              aria-disabled={item.disabled}
              disabled={item.disabled}
              title={item.disabled ? item.disabledReason : undefined}
              onClick={() => toggle(item)}
              className={cn(
                'focus-ring flex w-full items-center gap-2 px-3 py-2 text-start text-body hover:bg-surface-hover',
                item.disabled && 'cursor-not-allowed text-text-disabled',
              )}
            >
              <span className="flex-1 truncate">{item.label}</span>
              {item.meta ? (
                <span className="truncate text-caption text-text-tertiary">{item.meta}</span>
              ) : null}
            </button>
          ))
        )}
      </div>
    </Popover>
  )
}
