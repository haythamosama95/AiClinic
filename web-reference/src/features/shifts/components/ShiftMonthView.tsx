import { cn } from '@/lib/cn'
import { SHIFT_TYPES } from '../mock-data'
import type { ShiftInstance } from '../types'
import { getMonthDays, isUnderstaffed, toDateString } from '../utils'
import { ShiftCalendarMenu } from './ShiftCalendarMenu'

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

type ShiftMonthViewProps = {
  anchorDate: Date
  shifts: ShiftInstance[]
  selectedShiftId: string | null
  onSelectShift: (id: string) => void
  onDuplicateShift: (shiftId: string) => void
  onDeleteShift: (shiftId: string) => void
}

export function ShiftMonthView({
  anchorDate,
  shifts,
  selectedShiftId,
  onSelectShift,
  onDuplicateShift,
  onDeleteShift,
}: ShiftMonthViewProps) {
  const monthDays = getMonthDays(anchorDate.getFullYear(), anchorDate.getMonth())

  const shiftsForDay = (day: Date) =>
    shifts.filter((s) => s.date === toDateString(day))

  return (
    <div className="rounded-lg border border-border-default bg-surface-default p-4">
      <div className="grid grid-cols-7 gap-px">
        {WEEKDAYS.map((d) => (
          <div key={d} className="py-2 text-center text-overline text-text-tertiary">
            {d}
          </div>
        ))}
        {monthDays.map((day, i) => {
          if (!day) {
            return <div key={`empty-${i}`} className="min-h-24" />
          }

          const dayShifts = shiftsForDay(day)
          const isToday = toDateString(day) === toDateString(new Date())
          const hasGaps = dayShifts.some(isUnderstaffed)

          return (
            <div
              key={day.toISOString()}
              className={cn(
                'min-h-24 rounded-md border border-transparent p-1.5',
                isToday && 'border-action-primary bg-surface-selected',
                hasGaps && !isToday && 'bg-status-warning-surface/30',
              )}
            >
              <div className="flex items-center justify-between">
                <span className="shift-mono text-caption tabular-nums text-text-secondary">
                  {day.getDate()}
                </span>
                {dayShifts.length > 0 ? (
                  <span className="shift-mono text-[10px] text-text-tertiary">
                    {dayShifts.length}
                  </span>
                ) : null}
              </div>

              <div className="mt-1 space-y-0.5">
                {dayShifts.slice(0, 3).map((shift) => {
                  const type = SHIFT_TYPES.find((t) => t.id === shift.shiftTypeId)
                  const understaffed = isUnderstaffed(shift)
                  return (
                    <ShiftCalendarMenu
                      key={shift.id}
                      shift={shift}
                      onDuplicate={onDuplicateShift}
                      onDelete={onDeleteShift}
                    >
                      <button
                        type="button"
                        className={cn(
                          'w-full truncate rounded-sm px-1 py-0.5 text-start text-[10px] leading-tight',
                          type?.accentClass,
                          selectedShiftId === shift.id
                            ? 'ring-1 ring-action-primary'
                            : understaffed
                              ? 'bg-status-warning-surface text-status-warning-fg'
                              : 'bg-surface-selected text-text-link',
                        )}
                        onClick={() => onSelectShift(shift.id)}
                      >
                        <span className="shift-mono font-medium">
                          {shift.startTime}
                        </span>{' '}
                        {type?.label}
                        <span className="text-text-tertiary">
                          {' '}
                          ({shift.assignments.length}/{shift.headcount})
                        </span>
                      </button>
                    </ShiftCalendarMenu>
                  )
                })}
                {dayShifts.length > 3 ? (
                  <p className="px-1 text-[10px] text-text-tertiary">
                    +{dayShifts.length - 3} more
                  </p>
                ) : null}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
