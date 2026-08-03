import { Check, ChevronDown } from 'lucide-react'
import { useCallback, useId, useRef, useState } from 'react'
import { cn } from '@/lib/cn'
import { inputFieldClasses, type InputSize } from '../input-base/input-styles'
import { Popover } from '../popover/Popover'

export type SelectOption = {
  value: string
  label: string
  disabled?: boolean
  disabledReason?: string
}

export type SelectProps = {
  id?: string
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  readOnly?: boolean
  placeholder?: string
  value?: string
  defaultValue?: string
  options: SelectOption[]
  onValueChange?: (value: string) => void
  className?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
}

export function Select({
  id: idProp,
  size = 'md',
  invalid,
  disabled,
  readOnly,
  placeholder = 'Select an option',
  value: controlled,
  defaultValue,
  options,
  onValueChange,
  className,
  ...aria
}: SelectProps) {
  const autoId = useId()
  const id = idProp ?? autoId
  const [open, setOpen] = useState(false)
  const [internal, setInternal] = useState(defaultValue ?? '')
  const [highlight, setHighlight] = useState(0)
  const typeaheadRef = useRef('')
  const typeaheadTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const value = controlled ?? internal
  const selected = options.find((o) => o.value === value)

  const select = (next: string) => {
    if (controlled === undefined) setInternal(next)
    onValueChange?.(next)
    setOpen(false)
  }

  const handleTypeahead = useCallback(
    (key: string) => {
      typeaheadRef.current += key.toLowerCase()
      if (typeaheadTimer.current) clearTimeout(typeaheadTimer.current)
      typeaheadTimer.current = setTimeout(() => {
        typeaheadRef.current = ''
      }, 500)
      const idx = options.findIndex((o) =>
        o.label.toLowerCase().startsWith(typeaheadRef.current),
      )
      if (idx >= 0) setHighlight(idx)
    },
    [options],
  )

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (disabled || readOnly) return
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      if (!open) setOpen(true)
      setHighlight((h) => {
        const delta = e.key === 'ArrowDown' ? 1 : -1
        let next = h + delta
        if (next < 0) next = options.length - 1
        if (next >= options.length) next = 0
        return next
      })
    } else if (e.key === 'Enter' && open) {
      e.preventDefault()
      const opt = options[highlight]
      if (opt && !opt.disabled) select(opt.value)
    } else if (e.key === 'Escape') {
      setOpen(false)
    } else if (e.key.length === 1) {
      handleTypeahead(e.key)
    }
  }

  return (
    <Popover
      open={open && !disabled && !readOnly}
      onOpenChange={setOpen}
      contentClassName="min-w-[var(--radix-popover-trigger-width)] p-1"
      trigger={
        <button
          id={id}
          type="button"
          role="combobox"
          aria-expanded={open}
          aria-haspopup="listbox"
          disabled={disabled || readOnly}
          onKeyDown={onKeyDown}
          className={cn(
            inputFieldClasses({ size, invalid, disabled, readOnly }),
            'inline-flex items-center justify-between gap-2 text-start',
            !selected && 'text-text-placeholder',
            className,
          )}
          {...aria}
        >
          <span className="truncate">{selected?.label ?? placeholder}</span>
          <ChevronDown
            className={cn('size-4 shrink-0 text-icon-muted transition-transform', open && 'rotate-180')}
            aria-hidden
          />
        </button>
      }
    >
      <ul role="listbox" aria-labelledby={aria['aria-labelledby']} className="max-h-60 overflow-auto py-1">
        {options.map((opt, i) => (
          <li key={opt.value} role="presentation">
            <button
              type="button"
              role="option"
              aria-selected={opt.value === value}
              aria-disabled={opt.disabled}
              disabled={opt.disabled}
              title={opt.disabled ? opt.disabledReason : undefined}
              onMouseEnter={() => setHighlight(i)}
              onClick={() => !opt.disabled && select(opt.value)}
              className={cn(
                'focus-ring flex w-full items-center gap-2 rounded-md px-3 py-2 text-start text-body',
                i === highlight && 'bg-surface-hover',
                opt.value === value && 'bg-surface-selected text-text-primary',
                opt.disabled && 'cursor-not-allowed text-text-disabled',
              )}
            >
              <span className="flex-1 truncate">{opt.label}</span>
              {opt.value === value ? <Check className="size-4 shrink-0 text-action-primary" /> : null}
            </button>
          </li>
        ))}
      </ul>
    </Popover>
  )
}
