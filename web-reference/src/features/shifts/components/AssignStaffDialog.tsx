import { useMemo } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { STAFF } from '../mock-data'
import type { ShiftInstance } from '../types'
import { formatTimeRange, isShiftFull, staffHasConflict } from '../utils'

type AssignStaffDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  shift: ShiftInstance | null
  allShifts: ShiftInstance[]
  preselectedStaffId?: string | null
  onAssign: (shiftId: string, staffId: string) => void
}

export function AssignStaffDialog({
  open,
  onOpenChange,
  shift,
  allShifts,
  preselectedStaffId,
  onAssign,
}: AssignStaffDialogProps) {
  const candidates = useMemo(() => {
    if (!shift) return []
    return STAFF.filter((s) => s.roleId === shift.roleId && s.status !== 'on-leave')
  }, [shift])

  if (!shift) return null

  const shiftFull = isShiftFull(shift)

  const handleAssign = (staffId: string) => {
    onAssign(shift.id, staffId)
    onOpenChange(false)
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title="Assign staff"
      description={`${formatTimeRange(shift.startTime, shift.endTime)} · ${shift.assignments.length}/${shift.headcount} filled`}
      size="md"
      footer={
        <Button variant="secondary" onClick={() => onOpenChange(false)}>
          Close
        </Button>
      }
    >
      <div className="space-y-2">
        {candidates.length === 0 ? (
          <p className="py-4 text-center text-body-sm text-text-tertiary">
            No available staff for this role.
          </p>
        ) : (
          candidates.map((member) => {
            const assigned = shift.assignments.includes(member.id)
            const conflict = !assigned && staffHasConflict(member.id, shift, allShifts)
            const blocked = !assigned && shiftFull
            const highlighted = member.id === preselectedStaffId

            return (
              <div
                key={member.id}
                className={`flex items-center justify-between gap-3 rounded-lg border p-3 ${highlighted ? 'border-action-primary bg-surface-selected' : 'border-border-subtle'
                  }`}
              >
                <div className="flex items-center gap-3">
                  <Avatar name={member.name} size="sm" />
                  <div>
                    <p className="text-body-sm font-medium text-text-primary">{member.name}</p>
                    <p className="text-caption text-text-tertiary">
                      {member.weeklyHours}h / {member.maxWeeklyHours}h this week
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  {assigned ? (
                    <Badge color="success" variant="soft" size="sm">
                      Assigned
                    </Badge>
                  ) : conflict ? (
                    <Badge color="danger" variant="soft" size="sm">
                      Conflict
                    </Badge>
                  ) : blocked ? (
                    <Badge color="danger" variant="soft" size="sm">
                      Shift full
                    </Badge>
                  ) : (
                    <Button variant="primary" size="sm" onClick={() => handleAssign(member.id)}>
                      Assign
                    </Button>
                  )}
                </div>
              </div>
            )
          })
        )}
      </div>
    </Dialog>
  )
}
