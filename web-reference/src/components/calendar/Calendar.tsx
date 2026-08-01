import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { cn } from '@/lib/cn'

export type CalendarView = 'day' | 'week' | 'month'

export type CalendarEvent = {
  id: string
  title: string
  start: Date
  end: Date
  patient?: string
  doctor?: string
  conflict?: boolean
}

export type CalendarProps = {
  events?: CalendarEvent[]
  view?: CalendarView
  onViewChange?: (view: CalendarView) => void
  date?: Date
  onDateChange?: (date: Date) => void
  className?: string
}

const HOURS = Array.from({ length: 12 }, (_, i) => i + 8)
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

function startOfWeek(d: Date): Date {
  const date = new Date(d)
  const day = date.getDay()
  date.setDate(date.getDate() - day)
  date.setHours(0, 0, 0, 0)
  return date
}

function formatHour(h: number): string {
  const period = h >= 12 ? 'PM' : 'AM'
  const hour = h > 12 ? h - 12 : h === 0 ? 12 : h
  return `${hour}:00 ${period}`
}

function getMonthDays(year: number, month: number): (Date | null)[] {
  const first = new Date(year, month, 1)
  const last = new Date(year, month + 1, 0)
  const days: (Date | null)[] = []
  for (let i = 0; i < first.getDay(); i++) days.push(null)
  for (let d = 1; d <= last.getDate(); d++) days.push(new Date(year, month, d))
  return days
}

export function Calendar({
  events = [],
  view: viewProp,
  onViewChange,
  date: dateProp,
  onDateChange,
  className,
}: CalendarProps) {
  const [internalView, setInternalView] = useState<CalendarView>('week')
  const [internalDate, setInternalDate] = useState(() => new Date(2026, 6, 4))

  const view = viewProp ?? internalView
  const currentDate = dateProp ?? internalDate

  const setView = (v: CalendarView) => {
    onViewChange?.(v)
    if (!viewProp) setInternalView(v)
  }

  const setDate = (d: Date) => {
    onDateChange?.(d)
    if (!dateProp) setInternalDate(d)
  }

  const weekStart = useMemo(() => startOfWeek(currentDate), [currentDate])
  const weekDays = useMemo(
    () => Array.from({ length: 7 }, (_, i) => {
      const d = new Date(weekStart)
      d.setDate(d.getDate() + i)
      return d
    }),
    [weekStart],
  )

  const monthDays = useMemo(
    () => getMonthDays(currentDate.getFullYear(), currentDate.getMonth()),
    [currentDate],
  )

  const navigate = (delta: number) => {
    const next = new Date(currentDate)
    if (view === 'month') next.setMonth(next.getMonth() + delta)
    else if (view === 'week') next.setDate(next.getDate() + delta * 7)
    else next.setDate(next.getDate() + delta)
    setDate(next)
  }

  const eventsForDay = (day: Date) =>
    events.filter((e) => e.start.toDateString() === day.toDateString())

  const title =
    view === 'month'
      ? currentDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
      : view === 'week'
        ? `${weekDays[0].toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – ${weekDays[6].toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`
        : currentDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })

  return (
    <div className={cn('rounded-lg border border-border-default bg-surface-default', className)}>
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle px-4 py-3">
        <div className="flex items-center gap-2">
          <IconButton icon={<ChevronLeft size={16} />} label="Previous" size="sm" onClick={() => navigate(-1)} />
          <IconButton icon={<ChevronRight size={16} />} label="Next" size="sm" onClick={() => navigate(1)} />
          <h3 className="text-body-strong text-text-primary">{title}</h3>
        </div>
        <SegmentedControl
          value={view}
          onChange={(v) => setView(v as CalendarView)}
          options={[
            { value: 'day', label: 'Day' },
            { value: 'week', label: 'Week' },
            { value: 'month', label: 'Month' },
          ]}
          aria-label="Calendar view"
        />
        <Button variant="secondary" size="sm" onClick={() => setDate(new Date())}>
          Today
        </Button>
      </div>

      {view === 'month' ? (
        <div className="p-4">
          <div className="grid grid-cols-7 gap-px text-center">
            {WEEKDAYS.map((d) => (
              <div key={d} className="py-2 text-overline text-text-tertiary">
                {d}
              </div>
            ))}
            {monthDays.map((day, i) => (
              <div
                key={i}
                className={cn(
                  'min-h-20 rounded-md border border-transparent p-1 text-start',
                  day && 'hover:bg-surface-hover',
                  day?.toDateString() === new Date().toDateString() && 'bg-surface-selected',
                )}
              >
                {day ? (
                  <>
                    <span className="text-caption tabular-nums text-text-secondary">{day.getDate()}</span>
                    <div className="mt-1 space-y-0.5">
                      {eventsForDay(day).slice(0, 2).map((e) => (
                        <div
                          key={e.id}
                          className={cn(
                            'truncate rounded-sm px-1 py-0.5 text-caption',
                            e.conflict
                              ? 'bg-status-danger-surface text-status-danger-fg'
                              : 'bg-surface-selected text-text-link',
                          )}
                        >
                          {e.title}
                        </div>
                      ))}
                    </div>
                  </>
                ) : null}
              </div>
            ))}
          </div>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <div
            className="grid min-w-[640px]"
            style={{
              gridTemplateColumns: view === 'day' ? '56px 1fr' : `56px repeat(${weekDays.length}, 1fr)`,
            }}
          >
            <div className="border-e border-border-subtle" />
            {(view === 'day' ? [currentDate] : weekDays).map((day) => (
              <div
                key={day.toISOString()}
                className={cn(
                  'border-e border-border-subtle px-2 py-2 text-center last:border-e-0',
                  day.toDateString() === new Date().toDateString() && 'bg-surface-selected',
                )}
              >
                <p className="text-caption text-text-tertiary">
                  {day.toLocaleDateString('en-US', { weekday: 'short' })}
                </p>
                <p className="text-body-strong tabular-nums text-text-primary">{day.getDate()}</p>
              </div>
            ))}

            {HOURS.map((hour) => (
              <div key={hour} className="contents">
                <div className="border-e border-t border-border-subtle px-2 py-3 text-end text-caption tabular-nums text-text-tertiary">
                  {formatHour(hour)}
                </div>
                {(view === 'day' ? [currentDate] : weekDays).map((day) => {
                  const dayEvents = events.filter(
                    (e) =>
                      e.start.toDateString() === day.toDateString() &&
                      e.start.getHours() === hour,
                  )
                  const isNow =
                    day.toDateString() === new Date().toDateString() &&
                    new Date().getHours() === hour

                  return (
                    <div
                      key={`${day.toISOString()}-${hour}`}
                      className="relative border-e border-t border-border-subtle p-1 last:border-e-0"
                    >
                      {isNow ? (
                        <div
                          className="absolute inset-x-0 top-1/2 z-10 h-0.5 bg-action-primary"
                          aria-label="Current time"
                        />
                      ) : null}
                      {dayEvents.map((e) => (
                        <div
                          key={e.id}
                          className={cn(
                            'mb-1 rounded-md px-2 py-1 text-caption',
                            e.conflict
                              ? 'border border-status-danger-border bg-status-danger-surface text-status-danger-fg'
                              : 'bg-surface-selected text-text-primary',
                          )}
                        >
                          <p className="font-medium">{e.title}</p>
                          {e.patient ? <p className="text-text-secondary">{e.patient}</p> : null}
                        </div>
                      ))}
                    </div>
                  )
                })}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
