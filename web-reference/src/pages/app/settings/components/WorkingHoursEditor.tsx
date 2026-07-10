import { MapPin, CircleHelp } from 'lucide-react'
import { Checkbox } from '@/components/ui/checkbox/Checkbox'
import { FormField } from '@/components/ui/form-field/FormField'
import { TimePicker } from '@/components/ui/time-picker/TimePicker'
import { Tooltip } from '@/components/tooltip'
import { DAYS_OF_WEEK, type WorkingDay } from '@/data/settings'
import { SETUP_FIELD_HINTS } from '../setup/setupFieldHints'
import { cn } from '@/lib/cn'

export type WorkingHoursEditorProps = {
  value: WorkingDay[]
  onChange: (days: WorkingDay[]) => void
  errors?: Partial<Record<string, string>>
}

export function WorkingHoursEditor({ value, onChange, errors }: WorkingHoursEditorProps) {
  const updateDay = (dayId: string, patch: Partial<WorkingDay>) => {
    onChange(value.map((d) => (d.day === dayId ? { ...d, ...patch } : d)))
  }

  const enabledCount = value.filter((d) => d.enabled).length

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-1.5">
          <p className="text-body-strong text-text-primary">Working days & hours</p>
          <Tooltip content={SETUP_FIELD_HINTS.branchWorkingHours}>
            <button
              type="button"
              className="focus-ring inline-flex size-5 items-center justify-center rounded-sm text-icon-muted hover:text-icon-default"
              aria-label="More about Working days & hours"
            >
              <CircleHelp className="size-4" aria-hidden />
            </button>
          </Tooltip>
        </div>
        <span className="text-caption text-text-tertiary tabular-nums">
          {enabledCount} day{enabledCount !== 1 ? 's' : ''} open
        </span>
      </div>

      <div className="divide-y divide-border-subtle rounded-lg border border-border-default bg-surface-default">
        {DAYS_OF_WEEK.map((dayMeta) => {
          const day = value.find((d) => d.day === dayMeta.id)
          if (!day) return null
          const timeError = errors?.[`${dayMeta.id}-time`]

          return (
            <div
              key={dayMeta.id}
              className={cn(
                'flex flex-col gap-3 px-4 py-3 transition-colors sm:flex-row sm:items-center sm:justify-between',
                day.enabled ? 'bg-surface-default' : 'bg-surface-muted/40',
              )}
            >
              <label className="flex min-w-[7rem] cursor-pointer items-center gap-3">
                <Checkbox
                  checked={day.enabled}
                  onCheckedChange={(checked) =>
                    updateDay(dayMeta.id, { enabled: checked === true })
                  }
                  aria-label={`${dayMeta.label} open`}
                />
                <span
                  className={cn(
                    'text-body',
                    day.enabled ? 'text-text-primary font-medium' : 'text-text-tertiary',
                  )}
                >
                  {dayMeta.label}
                </span>
              </label>

              {day.enabled ? (
                <div className="flex flex-1 flex-wrap items-center gap-2 sm:justify-end">
                  <TimePicker
                    size="sm"
                    value={day.openTime}
                    onValueChange={(openTime) => updateDay(dayMeta.id, { openTime })}
                    use24Hour
                    aria-label={`${dayMeta.label} opening time`}
                    className="w-28"
                  />
                  <span className="text-caption text-text-tertiary">to</span>
                  <TimePicker
                    size="sm"
                    value={day.closeTime}
                    onValueChange={(closeTime) => updateDay(dayMeta.id, { closeTime })}
                    use24Hour
                    aria-label={`${dayMeta.label} closing time`}
                    className="w-28"
                  />
                </div>
              ) : (
                <span className="text-caption text-text-tertiary sm:text-end">Closed</span>
              )}

              {timeError ? (
                <p className="w-full text-caption text-status-danger-fg sm:text-end" role="alert">
                  {timeError}
                </p>
              ) : null}
            </div>
          )
        })}
      </div>
    </div>
  )
}

export type MapsLocationInputProps = {
  id: string
  value: string
  onChange: (value: string) => void
  invalid?: boolean
  'aria-labelledby'?: string
}

export function MapsLocationInput({
  id,
  value,
  onChange,
  invalid,
  ...aria
}: MapsLocationInputProps) {
  return (
    <FormField
      id={id}
      label="Google Maps location"
      required
      hint={SETUP_FIELD_HINTS.branchMapLocation}
    >
      <div className="relative">
        <MapPin
          className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-icon-muted"
          aria-hidden
        />
        <input
          id={id}
          type="url"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="https://maps.google.com/… or street address"
          aria-invalid={invalid || undefined}
          className={cn(
            'focus-ring w-full rounded-md border bg-surface-default py-2.5 ps-10 pe-3 text-body text-text-primary placeholder:text-text-tertiary',
            'border-border-default hover:border-border-strong',
            invalid && 'border-status-danger-fg',
          )}
          {...aria}
        />
      </div>
    </FormField>
  )
}
