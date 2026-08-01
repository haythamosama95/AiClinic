import { Calendar } from 'lucide-react'
import { useId, useMemo, useState } from 'react'
import { cn } from '@/lib/cn'
import { useDirection } from '@/providers/DirectionProvider'
import { inputFieldClasses, type InputSize } from '../input-base/input-styles'
import { Popover } from '../popover/Popover'

export type DateRange = { start: Date | null; end: Date | null }

export type DateRangePickerProps = {
  id?: string
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  value?: DateRange
  defaultValue?: DateRange
  onValueChange?: (range: DateRange) => void
  presets?: { label: string; range: DateRange }[]
  placeholder?: string
  className?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
}

function startOfDay(d: Date) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function formatRange(range: DateRange, locale: string): string {
  const fmt = new Intl.DateTimeFormat(locale === 'ar' ? 'ar-EG' : 'en-GB', {
    day: 'numeric',
    month: 'short',
  })
  if (!range.start && !range.end) return ''
  if (range.start && !range.end) return fmt.format(range.start)
  if (range.start && range.end) {
    return `${fmt.format(range.start)} – ${fmt.format(range.end)}`
  }
  return ''
}

function defaultPresets(): { label: string; range: DateRange }[] {
  const today = startOfDay(new Date())
  const weekStart = new Date(today)
  weekStart.setDate(today.getDate() - today.getDay())
  const weekEnd = new Date(weekStart)
  weekEnd.setDate(weekStart.getDate() + 6)
  const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
  const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0)
  return [
    { label: 'Today', range: { start: today, end: today } },
    { label: 'This week', range: { start: weekStart, end: weekEnd } },
    { label: 'This month', range: { start: monthStart, end: monthEnd } },
  ]
}

function MonthGrid({
  month,
  range,
  onSelect,
}: {
  month: Date
  range: DateRange
  onSelect: (d: Date) => void
}) {
  const days = useMemo(() => {
    const year = month.getFullYear()
    const m = month.getMonth()
    const first = new Date(year, m, 1)
    const startPad = first.getDay()
    const daysInMonth = new Date(year, m + 1, 0).getDate()
    const cells: (Date | null)[] = []
    for (let i = 0; i < startPad; i++) cells.push(null)
    for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(year, m, d))
    return cells
  }, [month])

  const inRange = (d: Date) => {
    if (!range.start || !range.end) return false
    return d >= range.start && d <= range.end
  }

  return (
    <div className="grid grid-cols-7 gap-1">
      {days.map((day, i) =>
        day ? (
          <button
            key={i}
            type="button"
            onClick={() => onSelect(day)}
            className={cn(
              'rounded-md py-1 text-caption tabular-nums hover:bg-surface-hover',
              inRange(day) && 'bg-surface-selected',
              range.start && day.getTime() === range.start.getTime() && 'bg-action-primary text-action-primary-fg',
              range.end && day.getTime() === range.end.getTime() && 'bg-action-primary text-action-primary-fg',
            )}
          >
            {day.getDate()}
          </button>
        ) : (
          <span key={i} />
        ),
      )}
    </div>
  )
}

export function DateRangePicker({
  id: idProp,
  size = 'md',
  invalid,
  disabled,
  value: controlled,
  defaultValue,
  onValueChange,
  presets = defaultPresets(),
  placeholder = 'Select date range',
  className,
  ...aria
}: DateRangePickerProps) {
  const autoId = useId()
  const id = idProp ?? autoId
  const { locale } = useDirection()
  const [open, setOpen] = useState(false)
  const [internal, setInternal] = useState<DateRange>(defaultValue ?? { start: null, end: null })
  const [leftMonth, setLeftMonth] = useState(new Date())
  const rightMonth = useMemo(
    () => new Date(leftMonth.getFullYear(), leftMonth.getMonth() + 1, 1),
    [leftMonth],
  )

  const range = controlled ?? internal

  const handleSelect = (d: Date) => {
    let next: DateRange
    if (!range.start || (range.start && range.end)) {
      next = { start: d, end: null }
    } else if (d < range.start) {
      next = { start: d, end: range.start }
    } else {
      next = { start: range.start, end: d }
    }
    if (controlled === undefined) setInternal(next)
    onValueChange?.(next)
    if (next.start && next.end) setOpen(false)
  }

  const applyPreset = (preset: DateRange) => {
    if (controlled === undefined) setInternal(preset)
    onValueChange?.(preset)
    setOpen(false)
  }

  const display = formatRange(range, locale)
  const inclusiveMsg =
    range.start && range.end
      ? `Inclusive range: ${display}`
      : range.start
        ? 'Select end date'
        : undefined

  return (
    <div className="flex flex-col gap-1">
      <Popover
        open={open && !disabled}
        onOpenChange={setOpen}
        contentClassName="w-auto max-w-lg p-4"
        trigger={
          <div className={cn('relative', className)}>
            <input
              id={id}
              type="text"
              readOnly
              disabled={disabled}
              placeholder={placeholder}
              value={display}
              onClick={() => !disabled && setOpen(true)}
              className={cn(inputFieldClasses({ size, invalid, disabled }), 'cursor-pointer pe-10')}
              {...aria}
            />
            <Calendar
              className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-icon-muted"
              aria-hidden
            />
          </div>
        }
      >
        <div className="mb-3 flex flex-wrap gap-2">
          {presets.map((p) => (
            <button
              key={p.label}
              type="button"
              onClick={() => applyPreset(p.range)}
              className="focus-ring rounded-md border border-border-default px-3 py-1.5 text-body-sm hover:bg-surface-hover"
            >
              {p.label}
            </button>
          ))}
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <MonthGrid month={leftMonth} range={range} onSelect={handleSelect} />
          <MonthGrid month={rightMonth} range={range} onSelect={handleSelect} />
        </div>
        <div className="mt-3 flex justify-between">
          <button
            type="button"
            className="focus-ring text-caption text-text-link"
            onClick={() => setLeftMonth((m) => new Date(m.getFullYear(), m.getMonth() - 1, 1))}
          >
            Previous
          </button>
          <button
            type="button"
            className="focus-ring text-caption text-text-link"
            onClick={() => setLeftMonth((m) => new Date(m.getFullYear(), m.getMonth() + 1, 1))}
          >
            Next
          </button>
        </div>
      </Popover>
      {inclusiveMsg ? (
        <p className="text-caption text-text-tertiary" aria-live="polite">
          {inclusiveMsg}
        </p>
      ) : null}
    </div>
  )
}
