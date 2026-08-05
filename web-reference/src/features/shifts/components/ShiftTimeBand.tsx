import { AlertTriangle, Check, Users } from 'lucide-react'
import { cn } from '@/lib/cn'
import { SHIFT_TYPES } from '../mock-data'
import type { ShiftInstance } from '../types'
import { formatTimeRange, isOverstaffed, isUnderstaffed, shiftFillRatio } from '../utils'

type ShiftTimeBandProps = {
  shift: ShiftInstance
  label?: string
  compact?: boolean
  selected?: boolean
  dropActive?: boolean
  className?: string
  style?: React.CSSProperties
  onClick?: () => void
  onDragOver?: (e: React.DragEvent) => void
  onDragLeave?: () => void
  onDrop?: (e: React.DragEvent) => void
}

export function ShiftTimeBand({
  shift,
  label,
  compact,
  selected,
  dropActive,
  className,
  style,
  onClick,
  onDragOver,
  onDragLeave,
  onDrop,
}: ShiftTimeBandProps) {
  const shiftType = SHIFT_TYPES.find((t) => t.id === shift.shiftTypeId)
  const fillRatio = shiftFillRatio(shift)
  const fillPercent = Math.round(fillRatio * 100)
  const understaffed = isUnderstaffed(shift)
  const overstaffed = isOverstaffed(shift)
  const full = shift.assignments.length === shift.headcount && shift.headcount > 0

  return (
    <button
      type="button"
      className={cn(
        'shift-time-band shift-drop-target w-full text-start',
        shiftType?.accentClass,
        understaffed && 'shift-time-band--understaffed',
        full && 'shift-time-band--full',
        overstaffed && 'shift-time-band--overstaffed',
        selected && 'ring-2 ring-action-primary ring-offset-1',
        dropActive && 'shift-drop-target--active',
        compact ? 'p-1.5' : 'p-2.5',
        className,
      )}
      style={style}
      onClick={onClick}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
      aria-label={`${label ?? shiftType?.label ?? 'Shift'}, ${formatTimeRange(shift.startTime, shift.endTime)}, ${shift.assignments.length} of ${shift.headcount} assigned`}
    >
      <div
        className="shift-fill-bar"
        style={{ height: `${fillPercent}%`, width: '100%' }}
        aria-hidden
      />

      <div className="relative z-[1] space-y-0.5">
        <div className="flex items-start justify-between gap-1">
          <p className={cn('font-medium text-text-primary', compact ? 'text-caption' : 'text-body-sm')}>
            {label ?? shiftType?.label ?? 'Shift'}
          </p>
          {understaffed ? (
            <AlertTriangle size={12} className="shrink-0 text-status-warning-fg" aria-hidden />
          ) : full ? (
            <Check size={12} className="shrink-0 text-status-success-fg" aria-hidden />
          ) : null}
        </div>

        <p className="shift-mono text-caption text-text-secondary">
          {formatTimeRange(shift.startTime, shift.endTime)}
        </p>

        {!compact ? (
          <div className="flex items-center gap-1 text-caption text-text-tertiary">
            <Users size={11} aria-hidden />
            <span className="shift-mono">
              {shift.assignments.length}/{shift.headcount}
            </span>
          </div>
        ) : null}
      </div>
    </button>
  )
}
