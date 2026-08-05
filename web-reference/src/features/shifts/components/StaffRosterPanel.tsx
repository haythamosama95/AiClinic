import { Calendar, GripVertical, UserPlus } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import { cn } from '@/lib/cn'
import type { ShiftInstance, StaffMember } from '../types'
import { formatTimeRange, getStaffShiftsForWeek } from '../utils'

type StaffRosterPanelProps = {
  staff: StaffMember[]
  shifts: ShiftInstance[]
  weekDays: Date[]
  search: string
  onSearchChange: (value: string) => void
  onAssignToShift: (staffId: string) => void
}

const STATUS_BADGE: Record<StaffMember['status'], { color: 'success' | 'warning' | 'neutral' | 'danger'; label: string }> = {
  available: { color: 'success', label: 'Available' },
  'partially-assigned': { color: 'warning', label: 'Partial' },
  'fully-assigned': { color: 'neutral', label: 'Full' },
  'on-leave': { color: 'danger', label: 'On leave' },
}

export function StaffRosterPanel({
  staff,
  shifts,
  weekDays,
  search,
  onSearchChange,
  onAssignToShift,
}: StaffRosterPanelProps) {
  const availableCount = staff.filter((s) => s.status !== 'on-leave').length

  return (
    <aside className="shifts-roster-panel flex flex-col gap-4">
      <div>
        <div className="flex items-center justify-between gap-2">
          <h2 className="shift-heading text-body-strong text-text-primary">Team roster</h2>
          <Badge color="neutral" variant="soft" size="sm">
            {availableCount} members
          </Badge>
        </div>
        <p className="mt-0.5 text-caption text-text-tertiary">
          Drag a member onto a shift, or use Assign.
        </p>
      </div>

      <SearchInput
        placeholder="Search team…"
        value={search}
        onValueChange={onSearchChange}
        showShortcutHint={false}
        size="sm"
      />

      <div className="flex flex-col gap-2">
        {staff.length === 0 ? (
          <p className="py-6 text-center text-body-sm text-text-tertiary">
            No team members match your search.
          </p>
        ) : (
          staff.map((member) => (
            <StaffCard
              key={member.id}
              member={member}
              weekShifts={getStaffShiftsForWeek(member.id, shifts, weekDays)}
              onAssign={() => onAssignToShift(member.id)}
            />
          ))
        )}
      </div>
    </aside>
  )
}

function StaffCard({
  member,
  weekShifts,
  onAssign,
}: {
  member: StaffMember
  weekShifts: ShiftInstance[]
  onAssign: () => void
}) {
  const statusInfo = STATUS_BADGE[member.status]
  const hoursPercent = Math.round((member.weeklyHours / member.maxWeeklyHours) * 100)
  const draggable = member.status !== 'on-leave'

  const handleDragStart = (e: React.DragEvent) => {
    if (!draggable) {
      e.preventDefault()
      return
    }
    e.dataTransfer.setData('text/staff-id', member.id)
    e.dataTransfer.effectAllowed = 'copy'
  }

  return (
    <div
      className={cn(
        'shift-roster-card p-3',
        draggable && 'shift-roster-card--draggable',
        member.status === 'on-leave' && 'opacity-60',
      )}
      draggable={draggable}
      onDragStart={handleDragStart}
    >
      <div className="flex items-start gap-2.5">
        {draggable ? (
          <GripVertical size={14} className="mt-1 shrink-0 text-icon-muted" aria-hidden />
        ) : (
          <span className="w-3.5" />
        )}
        <Avatar name={member.name} size="sm" />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <p className="truncate text-body-sm font-medium text-text-primary">{member.name}</p>
            <Badge color={statusInfo.color} variant="soft" size="sm">
              {statusInfo.label}
            </Badge>
          </div>

          <div className="mt-1.5 flex items-center gap-2">
            <div className="h-1 flex-1 overflow-hidden rounded-full bg-surface-sunken">
              <div
                className="h-full rounded-full bg-action-primary transition-all"
                style={{ width: `${hoursPercent}%` }}
              />
            </div>
            <span className="shift-mono shrink-0 text-caption text-text-tertiary">
              {member.weeklyHours}h
            </span>
          </div>

          {weekShifts.length > 0 ? (
            <div className="mt-2 space-y-1">
              {weekShifts.slice(0, 2).map((shift) => (
                <div
                  key={shift.id}
                  className="flex items-center gap-1.5 text-caption text-text-secondary"
                >
                  <Calendar size={10} aria-hidden />
                  <span>
                    {new Date(shift.date + 'T00:00:00').toLocaleDateString('en-US', {
                      weekday: 'short',
                      month: 'short',
                      day: 'numeric',
                    })}
                  </span>
                  <span className="shift-mono text-text-tertiary">
                    {formatTimeRange(shift.startTime, shift.endTime)}
                  </span>
                </div>
              ))}
              {weekShifts.length > 2 ? (
                <p className="text-caption text-text-tertiary">
                  +{weekShifts.length - 2} more this week
                </p>
              ) : null}
            </div>
          ) : (
            <p className="mt-2 text-caption text-text-tertiary">No shifts this week</p>
          )}

          {draggable ? (
            <Button
              variant="ghost"
              size="sm"
              className="mt-2"
              leadingIcon={<UserPlus size={12} />}
              onClick={onAssign}
            >
              Assign to shift
            </Button>
          ) : null}
        </div>
      </div>
    </div>
  )
}
