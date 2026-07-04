import { useCallback, useEffect, useId, useRef, useState } from 'react'
import { cn } from '@/lib/cn'
import { bareInputClasses, inputWrapperClasses, type InputSize } from '../input-base/input-styles'
import { Popover } from '../popover/Popover'
import { Spinner } from '../spinner/Spinner'

export type ComboboxItem = {
  id: string
  label: string
  meta?: string
  avatar?: string
  initials?: string
  disabled?: boolean
  disabledReason?: string
}

export type ComboboxProps = {
  id?: string
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  placeholder?: string
  value?: ComboboxItem | null
  onValueChange?: (item: ComboboxItem | null) => void
  onSearch?: (query: string) => Promise<ComboboxItem[]>
  items?: ComboboxItem[]
  debounceMs?: number
  allowCreate?: boolean
  createLabel?: (query: string) => string
  onCreate?: (query: string) => void
  className?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
}

function highlightMatch(text: string, query: string) {
  if (!query) return text
  const idx = text.toLowerCase().indexOf(query.toLowerCase())
  if (idx < 0) return text
  return (
    <>
      {text.slice(0, idx)}
      <mark className="bg-surface-selected text-text-primary">{text.slice(idx, idx + query.length)}</mark>
      {text.slice(idx + query.length)}
    </>
  )
}

export function Combobox({
  id: idProp,
  size = 'md',
  invalid,
  disabled,
  placeholder = 'Search…',
  value,
  onValueChange,
  onSearch,
  items: staticItems,
  debounceMs = 300,
  allowCreate,
  createLabel = (q) => `Create "${q}"`,
  onCreate,
  className,
  ...aria
}: ComboboxProps) {
  const autoId = useId()
  const id = idProp ?? autoId
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [items, setItems] = useState<ComboboxItem[]>(staticItems ?? [])
  const [loading, setLoading] = useState(false)
  const [highlight, setHighlight] = useState(0)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const listId = `${id}-listbox`

  const runSearch = useCallback(
    async (q: string) => {
      if (onSearch) {
        setLoading(true)
        try {
          const results = await onSearch(q)
          setItems(results)
        } finally {
          setLoading(false)
        }
      } else if (staticItems) {
        const lower = q.toLowerCase()
        setItems(
          staticItems.filter(
            (item) =>
              item.label.toLowerCase().includes(lower) ||
              item.meta?.toLowerCase().includes(lower),
          ),
        )
      }
    },
    [onSearch, staticItems],
  )

  useEffect(() => {
    if (!open) return
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => runSearch(query), debounceMs)
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [query, open, debounceMs, runSearch])

  const select = (item: ComboboxItem) => {
    if (item.disabled) return
    onValueChange?.(item)
    setQuery('')
    setOpen(false)
  }

  const displayValue = value ? value.label : query

  const onKeyDown = (e: React.KeyboardEvent) => {
    const selectable = items.filter((i) => !i.disabled)
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setOpen(true)
      setHighlight((h) => Math.min(h + 1, Math.max(selectable.length - 1, 0)))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setHighlight((h) => Math.max(h - 1, 0))
    } else if (e.key === 'Enter' && open) {
      e.preventDefault()
      const item = selectable[highlight]
      if (item) select(item)
      else if (allowCreate && query && onCreate) {
        onCreate(query)
        setOpen(false)
      }
    } else if (e.key === 'Escape') {
      setOpen(false)
      setQuery('')
    }
  }

  const showEmpty = !loading && items.length === 0 && query.length > 0
  const showCreate = allowCreate && query.length > 0 && !items.some((i) => i.label.toLowerCase() === query.toLowerCase())

  return (
    <Popover
      open={open && !disabled}
      onOpenChange={setOpen}
      contentClassName="min-w-[var(--radix-popover-trigger-width)] w-80 p-0"
      trigger={
        <div
          className={inputWrapperClasses({ size, invalid, disabled, className })}
          onFocus={() => setOpen(true)}
        >
          <input
            id={id}
            role="combobox"
            aria-expanded={open}
            aria-controls={listId}
            aria-autocomplete="list"
            disabled={disabled}
            value={displayValue}
            placeholder={value ? undefined : placeholder}
            onChange={(e) => {
              setQuery(e.target.value)
              if (value) onValueChange?.(null)
              setOpen(true)
            }}
            onKeyDown={onKeyDown}
            className={bareInputClasses()}
            {...aria}
          />
          {loading ? <Spinner size="sm" /> : null}
          {value ? (
            <button
              type="button"
              onClick={() => onValueChange?.(null)}
              className="focus-ring shrink-0 text-caption text-text-link"
              aria-label="Clear selection"
            >
              Clear
            </button>
          ) : null}
        </div>
      }
    >
      <div
        id={listId}
        role="listbox"
        aria-label="Suggestions"
        className="max-h-72 overflow-auto py-1"
        aria-busy={loading}
      >
        {loading && items.length === 0 ? (
          <p className="px-3 py-6 text-center text-body-sm text-text-tertiary" role="status">
            Searching…
          </p>
        ) : null}

        {showEmpty ? (
          <p className="px-3 py-6 text-center text-body-sm text-text-secondary" role="status">
            No matches for &ldquo;{query}&rdquo;
          </p>
        ) : null}

        {items.map((item) => {
          const selectableIdx = items.filter((x) => !x.disabled).indexOf(item)
          const isHighlighted = selectableIdx === highlight
          return (
            <button
              key={item.id}
              type="button"
              role="option"
              aria-selected={value?.id === item.id}
              aria-disabled={item.disabled}
              disabled={item.disabled}
              title={item.disabled ? item.disabledReason : undefined}
              onMouseEnter={() => !item.disabled && setHighlight(selectableIdx)}
              onClick={() => select(item)}
              className={cn(
                'focus-ring flex w-full items-center gap-3 px-3 py-2 text-start',
                isHighlighted && !item.disabled && 'bg-surface-hover',
                item.disabled && 'cursor-not-allowed opacity-60',
              )}
            >
              {item.avatar || item.initials ? (
                <span
                  className="flex size-8 shrink-0 items-center justify-center rounded-full bg-surface-muted text-caption text-text-secondary"
                  aria-hidden
                >
                  {item.avatar ? (
                    <img src={item.avatar} alt="" className="size-8 rounded-full object-cover" />
                  ) : (
                    item.initials
                  )}
                </span>
              ) : null}
              <span className="min-w-0 flex-1">
                <span className="block truncate text-body-strong text-text-primary">
                  {highlightMatch(item.label, query)}
                </span>
                {item.meta ? (
                  <span className="block truncate text-caption text-text-tertiary">{item.meta}</span>
                ) : null}
                {item.disabled && item.disabledReason ? (
                  <span className="block truncate text-caption text-status-warning-fg">
                    {item.disabledReason}
                  </span>
                ) : null}
              </span>
            </button>
          )
        })}

        {showCreate ? (
          <button
            type="button"
            className="focus-ring w-full border-t border-border-subtle px-3 py-2 text-start text-body text-text-link hover:bg-surface-hover"
            onClick={() => {
              onCreate?.(query)
              setOpen(false)
            }}
          >
            {createLabel(query)}
          </button>
        ) : null}
      </div>
    </Popover>
  )
}
