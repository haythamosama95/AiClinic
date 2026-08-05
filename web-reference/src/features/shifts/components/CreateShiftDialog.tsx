import { useEffect, useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Drawer } from '@/components/drawer/Drawer'
import { Checkbox } from '@/components/ui/checkbox/Checkbox'
import { FormField } from '@/components/ui/form-field/FormField'
import { NumberInput } from '@/components/ui/number-input/NumberInput'
import { ROLES, SHIFT_TYPES } from '../mock-data'
import { releaseOverlayLocks } from '../overlay-cleanup'
import type { CreateShiftInput, RoleId } from '../types'
import { datesInRange, toDateString, WEEKDAY_FULL } from '../utils'

type CreateShiftDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  defaultRoleId: RoleId
  onCreate: (input: CreateShiftInput) => void
}

function defaultRangeStart(): string {
  return toDateString(new Date())
}

function defaultRangeEnd(): string {
  const end = new Date()
  end.setDate(end.getDate() + 4)
  return toDateString(end)
}

const inputClassName =
  'focus-ring w-full rounded-md border border-border-default bg-surface-default px-3 py-2 text-body'

export function CreateShiftDialog({
  open,
  onOpenChange,
  defaultRoleId,
  onCreate,
}: CreateShiftDialogProps) {
  const [roleId, setRoleId] = useState<RoleId>(defaultRoleId)
  const [shiftTypeId, setShiftTypeId] = useState('')
  const [startTime, setStartTime] = useState('08:00')
  const [endTime, setEndTime] = useState('12:00')
  const [headcount, setHeadcount] = useState(2)
  const [rangeStart, setRangeStart] = useState(defaultRangeStart)
  const [rangeEnd, setRangeEnd] = useState(defaultRangeEnd)
  const [weekdays, setWeekdays] = useState<number[]>([1, 2, 3, 4, 5])
  const [useWeekdays, setUseWeekdays] = useState(true)

  const roleShiftTypes = useMemo(
    () => SHIFT_TYPES.filter((t) => t.roleId === roleId),
    [roleId],
  )

  const resolvedShiftTypeId = shiftTypeId || roleShiftTypes[0]?.id || ''

  useEffect(() => {
    if (!open) {
      releaseOverlayLocks()
      return
    }

    setRoleId(defaultRoleId)
    setShiftTypeId('')
    setRangeStart(defaultRangeStart())
    setRangeEnd(defaultRangeEnd())
    const firstType = SHIFT_TYPES.find((t) => t.roleId === defaultRoleId)
    if (firstType) {
      setShiftTypeId(firstType.id)
      setStartTime(firstType.startTime)
      setEndTime(firstType.endTime)
      setHeadcount(firstType.defaultHeadcount)
    }
  }, [open, defaultRoleId])

  const handleShiftTypeChange = (id: string) => {
    setShiftTypeId(id)
    const type = SHIFT_TYPES.find((t) => t.id === id)
    if (type) {
      setStartTime(type.startTime)
      setEndTime(type.endTime)
      setHeadcount(type.defaultHeadcount)
    }
  }

  const handleRoleChange = (nextRoleId: RoleId) => {
    setRoleId(nextRoleId)
    const firstType = SHIFT_TYPES.find((t) => t.roleId === nextRoleId)
    setShiftTypeId(firstType?.id ?? '')
    if (firstType) {
      setStartTime(firstType.startTime)
      setEndTime(firstType.endTime)
      setHeadcount(firstType.defaultHeadcount)
    }
  }

  const toggleWeekday = (day: number) => {
    setWeekdays((prev) =>
      prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day].sort(),
    )
  }

  const previewDates = datesInRange(rangeStart, rangeEnd, useWeekdays ? weekdays : undefined)

  const handleClose = () => {
    onOpenChange(false)
    releaseOverlayLocks()
  }

  const handleSubmit = (e?: React.FormEvent) => {
    e?.preventDefault()
    if (previewDates.length === 0 || !resolvedShiftTypeId) return

    onCreate({
      roleId,
      shiftTypeId: resolvedShiftTypeId,
      startTime,
      endTime,
      headcount,
      dates: previewDates,
    })
    handleClose()
  }

  return (
    <Drawer
      open={open}
      onOpenChange={(next) => {
        if (!next) releaseOverlayLocks()
        onOpenChange(next)
      }}
      title="Create shift"
      description="Configure a shift and assign it to specific days."
      size="lg"
      footer={
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={handleClose}>
            Cancel
          </Button>
          <Button
            type="button"
            variant="primary"
            onClick={() => handleSubmit()}
            disabled={previewDates.length === 0 || !resolvedShiftTypeId}
          >
            Create {previewDates.length} shift{previewDates.length === 1 ? '' : 's'}
          </Button>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="grid gap-5 sm:grid-cols-2">
        <FormField id="shift-role" label="Role" required>
          <select
            id="shift-role"
            value={roleId}
            onChange={(e) => handleRoleChange(e.target.value as RoleId)}
            className={inputClassName}
          >
            {ROLES.map((r) => (
              <option key={r.id} value={r.id}>
                {r.label}
              </option>
            ))}
          </select>
        </FormField>

        <FormField
          id="shift-type"
          label="Shift type"
          required
          hint="Each role has its own shift configurations."
        >
          <select
            id="shift-type"
            value={resolvedShiftTypeId}
            onChange={(e) => handleShiftTypeChange(e.target.value)}
            className={inputClassName}
          >
            {roleShiftTypes.map((t) => (
              <option key={t.id} value={t.id}>
                {t.label}
              </option>
            ))}
          </select>
        </FormField>

        <FormField id="shift-start" label="Start time" required>
          <input
            id="shift-start"
            type="time"
            value={startTime}
            onChange={(e) => setStartTime(e.target.value)}
            className={inputClassName}
          />
        </FormField>

        <FormField id="shift-end" label="End time" required>
          <input
            id="shift-end"
            type="time"
            value={endTime}
            onChange={(e) => setEndTime(e.target.value)}
            className={inputClassName}
          />
        </FormField>

        <FormField id="shift-headcount" label="Staff needed" required>
          <NumberInput
            id="shift-headcount"
            value={headcount}
            min={1}
            max={20}
            onValueChange={(v) => setHeadcount(v ?? 1)}
          />
        </FormField>

        <div className="sm:col-span-2">
          <FormField
            id="shift-dates"
            label="Assign to days"
            required
            helperText="Choose a date range and which days of the week to include."
          >
            <div className="mt-2 grid gap-3 sm:grid-cols-2">
              <div>
                <label htmlFor="range-start" className="text-caption text-text-tertiary">
                  From
                </label>
                <input
                  id="range-start"
                  type="date"
                  value={rangeStart}
                  onChange={(e) => setRangeStart(e.target.value)}
                  className={`${inputClassName} mt-1`}
                />
              </div>
              <div>
                <label htmlFor="range-end" className="text-caption text-text-tertiary">
                  To
                </label>
                <input
                  id="range-end"
                  type="date"
                  value={rangeEnd}
                  onChange={(e) => setRangeEnd(e.target.value)}
                  className={`${inputClassName} mt-1`}
                />
              </div>
            </div>
          </FormField>
        </div>

        <div className="sm:col-span-2">
          <Checkbox
            id="use-weekdays"
            checked={useWeekdays}
            onCheckedChange={(c) => setUseWeekdays(c === true)}
            label="Repeat on selected weekdays only"
          />
          {useWeekdays ? (
            <div className="mt-3 flex flex-wrap gap-2">
              {WEEKDAY_FULL.map((label, i) => (
                <button
                  key={label}
                  type="button"
                  onClick={() => toggleWeekday(i)}
                  className={`focus-ring rounded-md border px-2.5 py-1 text-caption transition-colors ${weekdays.includes(i)
                      ? 'border-action-primary bg-surface-selected text-text-primary'
                      : 'border-border-default text-text-secondary hover:bg-surface-hover'
                    }`}
                >
                  {label.slice(0, 3)}
                </button>
              ))}
            </div>
          ) : null}
        </div>

        {previewDates.length > 0 ? (
          <div className="sm:col-span-2 rounded-lg border border-border-subtle bg-surface-sunken p-3">
            <p className="text-caption text-text-tertiary">
              Will create shifts on{' '}
              <strong className="text-text-primary">{previewDates.length}</strong> day
              {previewDates.length === 1 ? '' : 's'}:
            </p>
            <p className="shift-mono mt-1 text-caption text-text-secondary">
              {previewDates.slice(0, 5).join(', ')}
              {previewDates.length > 5 ? ` … +${previewDates.length - 5} more` : ''}
            </p>
          </div>
        ) : null}
      </form>
    </Drawer>
  )
}
