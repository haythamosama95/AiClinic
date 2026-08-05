import { Calendar, Trash2, UserMinus, UserPlus } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { Drawer } from '@/components/drawer/Drawer'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { NumberInput } from '@/components/ui/number-input/NumberInput'
import { FormField } from '@/components/ui/form-field/FormField'
import { ROLES, SHIFT_TYPES, STAFF } from '../mock-data'
import type { ShiftInstance } from '../types'
import { formatTimeRange, isShiftFull, isUnderstaffed } from '../utils'
import { ShiftTimeBand } from './ShiftTimeBand'

type ShiftDetailDrawerProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  shift: ShiftInstance | null
  onAssign: () => void
  onUnassign: (staffId: string) => void
  onDelete: () => void
  onHeadcountChange: (headcount: number) => void
}

export function ShiftDetailDrawer({
  open,
  onOpenChange,
  shift,
  onAssign,
  onUnassign,
  onDelete,
  onHeadcountChange,
}: ShiftDetailDrawerProps) {
  if (!shift) return null

  const shiftType = SHIFT_TYPES.find((t) => t.id === shift.shiftTypeId)
  const role = ROLES.find((r) => r.id === shift.roleId)
  const assignedStaff = shift.assignments
    .map((id) => STAFF.find((s) => s.id === id))
    .filter(Boolean)

  const dateLabel = new Date(shift.date + 'T00:00:00').toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  })

  return (
    <Drawer
      open={open}
      onOpenChange={onOpenChange}
      title={shiftType?.label ?? 'Shift details'}
      description={`${role?.label} · ${dateLabel}`}
      size="md"
      footer={
        <div className="flex justify-between gap-2">
          <Button
            variant="danger"
            size="sm"
            leadingIcon={<Trash2 size={14} />}
            onClick={onDelete}
          >
            Delete shift
          </Button>
          <Button variant="secondary" size="sm" onClick={() => onOpenChange(false)}>
            Close
          </Button>
        </div>
      }
    >
      <div className="space-y-6">
        <ShiftTimeBand shift={shift} label={shiftType?.label} />

        <div className="grid grid-cols-2 gap-4">
          <div>
            <p className="text-caption text-text-tertiary">Time</p>
            <p className="shift-mono mt-0.5 text-body-sm text-text-primary">
              {formatTimeRange(shift.startTime, shift.endTime)}
            </p>
          </div>
          <div>
            <p className="text-caption text-text-tertiary">Date</p>
            <p className="mt-0.5 flex items-center gap-1.5 text-body-sm text-text-primary">
              <Calendar size={14} aria-hidden />
              {dateLabel}
            </p>
          </div>
        </div>

        <FormField id="drawer-headcount" label="Staff needed">
          <NumberInput
            id="drawer-headcount"
            value={shift.headcount}
            min={1}
            max={20}
            onValueChange={(v) => onHeadcountChange(v ?? 1)}
          />
        </FormField>

        <div>
          <div className="flex items-center justify-between gap-2">
            <h3 className="shift-heading text-body-strong text-text-primary">
              Assigned staff
            </h3>
            <div className="flex items-center gap-2">
              {isUnderstaffed(shift) ? (
                <Badge color="warning" variant="soft" size="sm">
                  {shift.headcount - shift.assignments.length} open
                </Badge>
              ) : (
                <Badge color="success" variant="soft" size="sm">
                  Full
                </Badge>
              )}
              <Button
                variant="primary"
                size="sm"
                leadingIcon={<UserPlus size={14} />}
                onClick={onAssign}
                disabled={isShiftFull(shift)}
              >
                Assign
              </Button>
            </div>
          </div>

          <div className="mt-3 space-y-2">
            {assignedStaff.length === 0 ? (
              <p className="rounded-lg border border-dashed border-border-default py-6 text-center text-body-sm text-text-tertiary">
                No one assigned yet. Add staff to fill this shift.
              </p>
            ) : (
              assignedStaff.map((member) =>
                member ? (
                  <div
                    key={member.id}
                    className="flex items-center justify-between gap-3 rounded-lg border border-border-subtle p-3"
                  >
                    <div className="flex items-center gap-3">
                      <Avatar name={member.name} size="sm" />
                      <div>
                        <p className="text-body-sm font-medium text-text-primary">
                          {member.name}
                        </p>
                        <p className="text-caption text-text-tertiary">
                          {member.weeklyHours}h this week
                        </p>
                      </div>
                    </div>
                    <IconButton
                      icon={<UserMinus size={14} />}
                      label={`Remove ${member.name}`}
                      size="sm"
                      onClick={() => onUnassign(member.id)}
                    />
                  </div>
                ) : null,
              )
            )}
          </div>
        </div>
      </div>
    </Drawer>
  )
}
