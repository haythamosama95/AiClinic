import { Calendar, ChevronLeft, ChevronRight } from 'lucide-react'
import { useId, useMemo, useState } from 'react'
import { cn } from '@/lib/cn'
import { useDirection } from '@/providers/DirectionProvider'
import { inputFieldClasses, type InputSize } from '../input-base/input-styles'
import { Popover } from '../popover/Popover'

export type DatePickerProps = {
  id?: string
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  readOnly?: boolean
  value?: Date | null
  defaultValue?: Date
  onValueChange?: (date: Date | null) => void
  min?: Date
  max?: Date
  placeholder?: string
  className?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
}

const WEEKDAYS_EN = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
const WEEKDAYS_AR = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س']
const MONTHS_EN = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

function isSameDay(a: Date, b: Date) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  )
}

function formatDisplay(date: Date, locale: string): string {
  return new Intl.DateTimeFormat(locale === 'ar' ? 'ar-EG' : 'en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(date)
}

function parseInput(raw: string): Date | null {
  const parts = raw.split(/[/.-]/).map(Number)
  if (parts.length !== 3) return null
  const [d, m, y] = parts
  const date = new Date(y, m - 1, d)
  return Number.isNaN(date.getTime()) ? null : date
}

export function DatePicker({
  id: idProp,
  size = 'md',
  invalid,
  disabled,
  readOnly,
  value: controlled,
  defaultValue,
  onValueChange,
  min,
  max,
  placeholder = 'dd/mm/yyyy',
  className,
  ...aria
}: DatePickerProps) {
  const autoId = useId()
  const id = idProp ?? autoId
  const { locale, direction } = useDirection()
  const [open, setOpen] = useState(false)
  const [internal, setInternal] = useState<Date | null>(defaultValue ?? null)
  const [view, setView] = useState(() => controlled ?? defaultValue ?? new Date())
  const [text, setText] = useState('')

  const value = controlled !== undefined ? controlled : internal
  const weekdays = locale === 'ar' ? WEEKDAYS_AR : WEEKDAYS_EN

  const days = useMemo(() => {
    const year = view.getFullYear()
    const month = view.getMonth()
    const first = new Date(year, month, 1)
    const startPad = first.getDay()
    const daysInMonth = new Date(year, month + 1, 0).getDate()
    const cells: (Date | null)[] = []
    for (let i = 0; i < startPad; i++) cells.push(null)
    for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(year, month, d))
    return cells
  }, [view])

  const select = (date: Date) => {
    if (min && date < min) return
    if (max && date > max) return
    if (controlled === undefined) setInternal(date)
    onValueChange?.(date)
    setText(formatDisplay(date, locale))
    setOpen(false)
  }

  const PrevIcon = direction === 'rtl' ? ChevronRight : ChevronLeft
  const NextIcon = direction === 'rtl' ? ChevronLeft : ChevronRight

  return (
    <Popover
      open={open && !disabled && !readOnly}
      onOpenChange={setOpen}
      contentClassName="w-72 p-3"
      trigger={
        <div className={cn('relative', className)}>
          <input
            id={id}
            type="text"
            disabled={disabled}
            readOnly={readOnly}
            placeholder={placeholder}
            value={text || (value ? formatDisplay(value, locale) : '')}
            onChange={(e) => {
              setText(e.target.value)
              const parsed = parseInput(e.target.value)
              if (parsed) select(parsed)
            }}
            onFocus={() => setOpen(true)}
            className={cn(inputFieldClasses({ size, invalid, disabled, readOnly }), 'pe-10')}
            {...aria}
          />
          <Calendar
            className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-icon-muted"
            aria-hidden
          />
        </div>
      }
    >
      <div className="flex items-center justify-between gap-2 pb-3">
        <button
          type="button"
          className="focus-ring rounded-md p-1 hover:bg-surface-hover"
          aria-label="Previous month"
          onClick={() => setView((v) => new Date(v.getFullYear(), v.getMonth() - 1, 1))}
        >
          <PrevIcon className="size-4" />
        </button>
        <span className="text-body-strong text-text-primary">
          {MONTHS_EN[view.getMonth()]} {view.getFullYear()}
        </span>
        <button
          type="button"
          className="focus-ring rounded-md p-1 hover:bg-surface-hover"
          aria-label="Next month"
          onClick={() => setView((v) => new Date(v.getFullYear(), v.getMonth() + 1, 1))}
        >
          <NextIcon className="size-4" />
        </button>
      </div>
      <div className="grid grid-cols-7 gap-1 text-center text-caption text-text-tertiary">
        {weekdays.map((d) => (
          <span key={d} className="py-1">
            {d}
          </span>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1" role="grid">
        {days.map((day, i) =>
          day ? (
            <button
              key={i}
              type="button"
              role="gridcell"
              disabled={
                (min && day < min) || (max && day > max) ||
                false
              }
              onClick={() => select(day)}
              className={cn(
                'focus-ring rounded-md py-1.5 text-body-sm tabular-nums hover:bg-surface-hover',
                value && isSameDay(day, value) && 'bg-action-primary text-action-primary-fg',
                isSameDay(day, new Date()) && !(value && isSameDay(day, value)) && 'border border-border-focus',
              )}
            >
              {day.getDate()}
            </button>
          ) : (
            <span key={i} />
          ),
        )}
      </div>
    </Popover>
  )
}
