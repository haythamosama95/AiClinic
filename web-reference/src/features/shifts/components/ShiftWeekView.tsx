import { useState } from 'react'
import { cn } from '@/lib/cn'
import type { ShiftInstance } from '../types'
import {
  getShiftBandLayout,
  SHIFT_GRID_HOUR_COUNT,
  SHIFT_GRID_START_HOUR,
  SHIFT_HOUR_HEIGHT_PX,
  toDateString,
} from '../utils'
import { ShiftTimeBand } from './ShiftTimeBand'
import { ShiftCalendarMenu } from './ShiftCalendarMenu'

const HOURS = Array.from({ length: SHIFT_GRID_HOUR_COUNT }, (_, i) => i + SHIFT_GRID_START_HOUR)

type ShiftWeekViewProps = {
  weekDays: Date[]
  shifts: ShiftInstance[]
  selectedShiftId: string | null
  onSelectShift: (id: string) => void
  onAssignDrop: (shiftId: string, staffId: string) => void
  onDuplicateShift: (shiftId: string) => void
  onDeleteShift: (shiftId: string) => void
}

export function ShiftWeekView({
  weekDays,
  shifts,
  selectedShiftId,
  onSelectShift,
  onAssignDrop,
  onDuplicateShift,
  onDeleteShift,
}: ShiftWeekViewProps) {
  const [dropTargetId, setDropTargetId] = useState<string | null>(null)

  const shiftsForDay = (day: Date) =>
    shifts.filter((s) => s.date === toDateString(day))

  const handleDragOver = (e: React.DragEvent, shiftId: string) => {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'copy'
    setDropTargetId(shiftId)
  }

  const handleDrop = (e: React.DragEvent, shiftId: string) => {
    e.preventDefault()
    const staffId = e.dataTransfer.getData('text/staff-id')
    if (staffId) onAssignDrop(shiftId, staffId)
    setDropTargetId(null)
  }

  return (
    <div className="overflow-x-auto rounded-lg border border-border-default bg-surface-default">
      <div
        className="grid min-w-[720px]"
        style={{
          gridTemplateColumns: '48px repeat(7, 1fr)',
          gridTemplateRows: `auto repeat(${HOURS.length}, ${SHIFT_HOUR_HEIGHT_PX}px)`,
        }}
      >
        {/* Header row */}
        <div className="border-b border-e border-border-subtle" />
        {weekDays.map((day) => {
          const isToday = toDateString(day) === toDateString(new Date())
          return (
            <div
              key={day.toISOString()}
              className={cn(
                'border-b border-e border-border-subtle px-2 py-2.5 text-center last:border-e-0',
                isToday && 'bg-surface-selected',
              )}
            >
              <p className="text-caption text-text-tertiary">
                {day.toLocaleDateString('en-US', { weekday: 'short' })}
              </p>
              <p className="shift-mono text-body-strong tabular-nums text-text-primary">
                {day.getDate()}
              </p>
            </div>
          )
        })}

        {/* Time labels */}
        {HOURS.map((hour) => (
          <div
            key={hour}
            className="border-e border-t border-border-subtle px-1.5 py-2 text-end"
            style={{ gridColumn: 1, gridRow: hour - SHIFT_GRID_START_HOUR + 2 }}
          >
            <span className="shift-mono text-caption text-text-tertiary">
              {formatHour(hour)}
            </span>
          </div>
        ))}

        {/* Day columns with hour grid lines and shift bands */}
        {weekDays.map((day, dayIndex) => {
          const isToday = toDateString(day) === toDateString(new Date())

          return (
            <div
              key={`column-${day.toISOString()}`}
              className={cn(
                'relative border-e border-t border-border-subtle last:border-e-0',
                isToday && 'bg-surface-selected/40',
              )}
              style={{
                gridColumn: dayIndex + 2,
                gridRow: `2 / span ${HOURS.length}`,
              }}
            >
              <div className="pointer-events-none absolute inset-0 flex flex-col" aria-hidden>
                {HOURS.map((hour, hourIndex) => (
                  <div
                    key={hour}
                    className={cn(
                      'shrink-0',
                      hourIndex > 0 && 'border-t border-border-subtle',
                    )}
                    style={{ height: SHIFT_HOUR_HEIGHT_PX }}
                  />
                ))}
              </div>

              {shiftsForDay(day).map((shift) => {
                const layout = getShiftBandLayout(shift.startTime, shift.endTime)
                if (!layout) return null

                return (
                  <ShiftCalendarMenu
                    key={shift.id}
                    shift={shift}
                    className="pointer-events-auto absolute inset-x-0.5 z-[1]"
                    style={{ top: layout.top, height: layout.height }}
                    onDuplicate={onDuplicateShift}
                    onDelete={onDeleteShift}
                  >
                    <ShiftTimeBand
                      shift={shift}
                      compact={layout.height < 72}
                      selected={selectedShiftId === shift.id}
                      dropActive={dropTargetId === shift.id}
                      className="h-full overflow-hidden"
                      onClick={() => onSelectShift(shift.id)}
                      onDragOver={(e) => handleDragOver(e, shift.id)}
                      onDragLeave={() => setDropTargetId(null)}
                      onDrop={(e) => handleDrop(e, shift.id)}
                    />
                  </ShiftCalendarMenu>
                )
              })}
            </div>
          )
        })}
      </div>
    </div>
  )
}

function formatHour(h: number): string {
  const period = h >= 12 ? 'PM' : 'AM'
  const hour = h > 12 ? h - 12 : h === 0 ? 12 : h
  return `${hour}${period === 'AM' ? 'a' : 'p'}`
}
