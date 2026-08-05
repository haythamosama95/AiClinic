import { useEffect, useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { Checkbox } from '@/components/ui/checkbox/Checkbox'
import { FormField } from '@/components/ui/form-field/FormField'
import { ROLES, SHIFT_TYPES, STAFF } from '../mock-data'
import { releaseOverlayLocks } from '../overlay-cleanup'
import type { DuplicateShiftInput, ShiftInstance } from '../types'
import { addDays, datesInRange, formatTimeRange, parseDate, toDateString, WEEKDAY_FULL } from '../utils'

type DuplicateShiftDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  shift: ShiftInstance | null
  onDuplicate: (input: DuplicateShiftInput) => boolean
}

const inputClassName =
  'focus-ring w-full rounded-md border border-border-default bg-surface-default px-3 py-2 text-body'

const readOnlyClassName =
  'w-full rounded-md border border-border-subtle bg-surface-sunken px-3 py-2 text-body text-text-secondary'

function defaultRangeStart(sourceDate: string): string {
  return toDateString(addDays(parseDate(sourceDate), 1))
}

function defaultRangeEnd(sourceDate: string): string {
  return toDateString(addDays(parseDate(sourceDate), 7))
}

export function DuplicateShiftDialog({
  open,
  onOpenChange,
  shift,
  onDuplicate,
}: DuplicateShiftDialogProps) {
  const [rangeStart, setRangeStart] = useState('')
  const [rangeEnd, setRangeEnd] = useState('')
  const [weekdays, setWeekdays] = useState<number[]>([1, 2, 3, 4, 5])
  const [useWeekdays, setUseWeekdays] = useState(true)

  useEffect(() => {
    if (!open || !shift) {
      if (!open) releaseOverlayLocks()
      return
    }

    setRangeStart(defaultRangeStart(shift.date))
    setRangeEnd(defaultRangeEnd(shift.date))
    setWeekdays([1, 2, 3, 4, 5])
    setUseWeekdays(true)
  }, [open, shift])

  const shiftType = shift ? SHIFT_TYPES.find((t) => t.id === shift.shiftTypeId) : null
  const role = shift ? ROLES.find((r) => r.id === shift.roleId) : null
  const assignedStaff = shift
    ? shift.assignments
      .map((id) => STAFF.find((member) => member.id === id))
      .filter(Boolean)
    : []

  const previewDates = useMemo(() => {
    if (!shift || !rangeStart || !rangeEnd) return []
    return datesInRange(rangeStart, rangeEnd, useWeekdays ? weekdays : undefined, [shift.date])
  }, [shift, rangeStart, rangeEnd, useWeekdays, weekdays])

  const rangeOnlyIncludesSourceDate =
    shift !== null &&
    rangeStart !== '' &&
    rangeEnd !== '' &&
    rangeStart <= shift.date &&
    rangeEnd >= shift.date &&
    previewDates.length === 0

  const sourceDateLabel = shift
    ? parseDate(shift.date).toLocaleDateString('en-US', {
      weekday: 'long',
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    })
    : ''

  const toggleWeekday = (day: number) => {
    setWeekdays((prev) =>
      prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day].sort(),
    )
  }

  const handleClose = () => {
    onOpenChange(false)
    releaseOverlayLocks()
  }

  const handleSubmit = () => {
    if (!shift || previewDates.length === 0) return

    if (
      onDuplicate({
        sourceShiftId: shift.id,
        dates: previewDates,
      })
    ) {
      handleClose()
    }
  }

  if (!shift) return null

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) releaseOverlayLocks()
        onOpenChange(next)
      }}
      title="Duplicate shift"
      description="Copy this shift and its staff assignments to other dates."
      size="lg"
      footer={
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={handleClose}>
            Cancel
          </Button>
          <Button
            type="button"
            variant="primary"
            onClick={handleSubmit}
            disabled={previewDates.length === 0}
          >
            Duplicate to {previewDates.length} date{previewDates.length === 1 ? '' : 's'}
          </Button>
        </div>
      }
    >
      <div className="grid gap-5 sm:grid-cols-2">
        <div className="sm:col-span-2 rounded-lg border border-border-subtle bg-surface-sunken p-4">
          <p className="text-overline text-text-tertiary">Shift configuration</p>
          <div className="mt-3 grid gap-4 sm:grid-cols-2">
            <FormField id="dup-role" label="Role">
              <div className={readOnlyClassName}>{role?.label ?? shift.roleId}</div>
            </FormField>

            <FormField id="dup-type" label="Shift type">
              <div className={readOnlyClassName}>{shiftType?.label ?? 'Custom shift'}</div>
            </FormField>

            <FormField id="dup-time" label="Time">
              <div className={`shift-mono ${readOnlyClassName}`}>
                {formatTimeRange(shift.startTime, shift.endTime)}
              </div>
            </FormField>

            <FormField id="dup-headcount" label="Staff needed">
              <div className={`shift-mono ${readOnlyClassName}`}>{shift.headcount}</div>
            </FormField>

            <FormField id="dup-source-date" label="Source date (excluded)" className="sm:col-span-2">
              <div className={readOnlyClassName}>{sourceDateLabel}</div>
            </FormField>

            <FormField id="dup-assignments" label="Assigned staff" className="sm:col-span-2">
              <div className={readOnlyClassName}>
                {assignedStaff.length > 0
                  ? assignedStaff.map((member) => member!.name).join(', ')
                  : 'No staff assigned'}
              </div>
            </FormField>
          </div>
        </div>

        <div className="sm:col-span-2">
          <FormField
            id="dup-dates"
            label="Duplicate to dates"
            required
            helperText={`Choose a date range. ${sourceDateLabel} cannot be selected as a target.`}
          >
            <div className="mt-2 grid gap-3 sm:grid-cols-2">
              <div>
                <label htmlFor="dup-range-start" className="text-caption text-text-tertiary">
                  From
                </label>
                <input
                  id="dup-range-start"
                  type="date"
                  value={rangeStart}
                  onChange={(e) => setRangeStart(e.target.value)}
                  className={`${inputClassName} mt-1`}
                />
              </div>
              <div>
                <label htmlFor="dup-range-end" className="text-caption text-text-tertiary">
                  To
                </label>
                <input
                  id="dup-range-end"
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
            id="dup-use-weekdays"
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
              Will duplicate to{' '}
              <strong className="text-text-primary">{previewDates.length}</strong> date
              {previewDates.length === 1 ? '' : 's'} with{' '}
              <strong className="text-text-primary">{assignedStaff.length}</strong> assigned staff
              member{assignedStaff.length === 1 ? '' : 's'}:
            </p>
            <p className="shift-mono mt-1 text-caption text-text-secondary">
              {previewDates.slice(0, 5).join(', ')}
              {previewDates.length > 5 ? ` … +${previewDates.length - 5} more` : ''}
            </p>
            {shift && rangeStart <= shift.date && rangeEnd >= shift.date ? (
              <p className="mt-2 text-caption text-text-tertiary">
                Excluded from targets:{' '}
                <span className="shift-mono text-text-secondary">{shift.date}</span>
              </p>
            ) : null}
          </div>
        ) : (
          <div className="sm:col-span-2 rounded-lg border border-dashed border-border-default px-3 py-4 text-center text-caption text-text-tertiary">
            {rangeOnlyIncludesSourceDate
              ? 'The source shift date cannot be selected. Choose a different date range.'
              : 'No target dates in this range. Adjust the range or weekday filter.'}
          </div>
        )}
      </div>
    </Dialog>
  )
}
