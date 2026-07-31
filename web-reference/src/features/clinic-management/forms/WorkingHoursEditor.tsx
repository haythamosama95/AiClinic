import { Switch } from '@/components/ui/switch/Switch'
import { TimePicker } from '@/components/ui/time-picker/TimePicker'
import { WEEKDAYS } from '../constants'
import type { WorkingSchedule } from '../types'

export type WorkingHoursEditorProps = {
  schedule: WorkingSchedule
  onChange: (schedule: WorkingSchedule) => void
  disabled?: boolean
}

export function WorkingHoursEditor({ schedule, onChange, disabled }: WorkingHoursEditorProps) {
  const updateDay = (dayId: (typeof WEEKDAYS)[number]['id'], patch: Partial<WorkingSchedule['days'][number]>) => {
    onChange({
      days: schedule.days.map((d) => (d.day === dayId ? { ...d, ...patch } : d)),
    })
  }

  return (
    <div className="space-y-2">
      {WEEKDAYS.map(({ id, label }) => {
        const day = schedule.days.find((d) => d.day === id)
        if (!day) return null
        const open = day.isWorkingDay

        return (
          <div
            key={id}
            className="flex flex-wrap items-center gap-3 rounded-lg border border-border-subtle bg-surface-default px-4 py-3"
          >
            <div className="flex min-w-[8rem] flex-1 items-center gap-3">
              <Switch
                id={`hours-${id}`}
                checked={open}
                onCheckedChange={(checked) =>
                  updateDay(id, {
                    isWorkingDay: checked,
                    openTime: checked ? day.openTime ?? '09:00' : null,
                    closeTime: checked ? day.closeTime ?? '17:00' : null,
                  })
                }
                disabled={disabled}
                aria-label={`${label} open`}
              />
              <label htmlFor={`hours-${id}`} className="text-body-sm font-medium text-text-primary">
                {label}
              </label>
            </div>

            {open ? (
              <div className="flex items-center gap-2">
                <TimePicker
                  value={day.openTime ?? ''}
                  onValueChange={(openTime) => updateDay(id, { openTime })}
                  disabled={disabled}
                  use24Hour
                  placeholder="Open"
                  className="w-[7rem]"
                />
                <span className="text-text-tertiary">–</span>
                <TimePicker
                  value={day.closeTime ?? ''}
                  onValueChange={(closeTime) => updateDay(id, { closeTime })}
                  disabled={disabled}
                  use24Hour
                  placeholder="Close"
                  className="w-[7rem]"
                />
              </div>
            ) : (
              <span className="text-body-sm text-text-tertiary">Closed</span>
            )}
          </div>
        )
      })}
    </div>
  )
}
