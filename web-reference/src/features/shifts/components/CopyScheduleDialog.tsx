import { useEffect, useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { Checkbox } from '@/components/ui/checkbox/Checkbox'
import { FormField } from '@/components/ui/form-field/FormField'
import { Select } from '@/components/ui/select/Select'
import { ROLES } from '../mock-data'
import type { CopyScheduleInput, CopyScope, RoleId } from '../types'
import {
  addDays,
  formatMonthLabel,
  formatWeekRangeLabel,
  monthValueToDate,
  parseDate,
  toDateString,
  toMonthValue,
} from '../utils'

type CopyScheduleDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  currentRoleId: RoleId
  anchorDate: Date
  onCopy: (input: CopyScheduleInput) => boolean
}

const SCOPE_OPTIONS: { value: CopyScope; label: string; description: string }[] = [
  { value: 'day', label: 'Day to day', description: 'Copy all shifts from one day to another' },
  { value: 'week', label: 'Week to week', description: 'Copy an entire week of shifts' },
  { value: 'month', label: 'Month to month', description: 'Copy all shifts from one month to another' },
  { value: 'role', label: 'Role to role', description: 'Duplicate shift patterns across roles' },
]

const inputClassName =
  'focus-ring w-full rounded-md border border-border-default bg-surface-default px-3 py-2 text-body'

export function CopyScheduleDialog({
  open,
  onOpenChange,
  currentRoleId,
  anchorDate,
  onCopy,
}: CopyScheduleDialogProps) {
  const [scope, setScope] = useState<CopyScope>('week')
  const [sourceDate, setSourceDate] = useState('')
  const [targetDate, setTargetDate] = useState('')
  const [sourceMonth, setSourceMonth] = useState('')
  const [targetMonth, setTargetMonth] = useState('')
  const [sourceRoleId, setSourceRoleId] = useState<RoleId>(currentRoleId)
  const [targetRoleId, setTargetRoleId] = useState<RoleId>(currentRoleId)
  const [includeAssignments, setIncludeAssignments] = useState(false)

  useEffect(() => {
    if (!open) return

    const anchor = toDateString(anchorDate)
    const anchorParsed = parseDate(anchor)
    const nextWeek = toDateString(addDays(anchorParsed, 7))
    const nextMonthDate = new Date(anchorParsed.getFullYear(), anchorParsed.getMonth() + 1, 1)

    setScope('week')
    setSourceDate(anchor)
    setTargetDate(nextWeek)
    setSourceMonth(toMonthValue(anchorParsed))
    setTargetMonth(toMonthValue(nextMonthDate))
    setSourceRoleId(currentRoleId)
    setTargetRoleId(currentRoleId)
    setIncludeAssignments(false)
  }, [open, anchorDate, currentRoleId])

  const sourceWeekLabel = useMemo(
    () => (sourceDate ? formatWeekRangeLabel(sourceDate) : ''),
    [sourceDate],
  )
  const targetWeekLabel = useMemo(
    () => (targetDate ? formatWeekRangeLabel(targetDate) : ''),
    [targetDate],
  )

  const handleCopy = () => {
    const resolvedSourceDate = scope === 'month' ? monthValueToDate(sourceMonth) : sourceDate
    const resolvedTargetDate = scope === 'month' ? monthValueToDate(targetMonth) : targetDate

    if (
      onCopy({
        scope,
        sourceDate: resolvedSourceDate,
        targetDate: resolvedTargetDate,
        sourceRoleId: scope === 'role' ? sourceRoleId : currentRoleId,
        targetRoleId: scope === 'role' ? targetRoleId : currentRoleId,
        includeAssignments,
      })
    ) {
      onOpenChange(false)
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title="Copy schedule"
      description="Duplicate shifts to avoid manual re-entry."
      size="md"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleCopy}>
            Copy schedule
          </Button>
        </>
      }
    >
      <div className="space-y-5">
        <FormField id="copy-scope" label="What to copy" required>
          <div className="mt-1 grid gap-2">
            {SCOPE_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                type="button"
                onClick={() => setScope(opt.value)}
                className={`focus-ring rounded-lg border p-3 text-start transition-colors ${scope === opt.value
                    ? 'border-action-primary bg-surface-selected'
                    : 'border-border-default hover:bg-surface-hover'
                  }`}
              >
                <p className="text-body-sm font-medium text-text-primary">{opt.label}</p>
                <p className="mt-0.5 text-caption text-text-tertiary">{opt.description}</p>
              </button>
            ))}
          </div>
        </FormField>

        {scope === 'role' ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField id="source-role" label="From role" required>
              <Select
                id="source-role"
                value={sourceRoleId}
                options={ROLES.map((r) => ({ value: r.id, label: r.label }))}
                onValueChange={(v) => setSourceRoleId(v as RoleId)}
              />
            </FormField>
            <FormField id="target-role" label="To role" required>
              <Select
                id="target-role"
                value={targetRoleId}
                options={ROLES.map((r) => ({ value: r.id, label: r.label }))}
                onValueChange={(v) => setTargetRoleId(v as RoleId)}
              />
            </FormField>
          </div>
        ) : scope === 'month' ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField
              id="source-month"
              label="Source month"
              required
              helperText={sourceMonth ? formatMonthLabel(sourceMonth) : undefined}
            >
              <input
                id="source-month"
                type="month"
                value={sourceMonth}
                onChange={(e) => setSourceMonth(e.target.value)}
                className={inputClassName}
              />
            </FormField>
            <FormField
              id="target-month"
              label="Target month"
              required
              helperText={targetMonth ? formatMonthLabel(targetMonth) : undefined}
            >
              <input
                id="target-month"
                type="month"
                value={targetMonth}
                onChange={(e) => setTargetMonth(e.target.value)}
                className={inputClassName}
              />
            </FormField>
          </div>
        ) : scope === 'week' ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField
              id="source-week"
              label="Source week"
              required
              helperText="Pick any day in the source week."
            >
              <input
                id="source-week"
                type="date"
                value={sourceDate}
                onChange={(e) => setSourceDate(e.target.value)}
                className={inputClassName}
              />
              {sourceWeekLabel ? (
                <p className="mt-2 rounded-md border border-border-subtle bg-surface-sunken px-3 py-2 text-caption text-text-secondary">
                  {sourceWeekLabel}
                </p>
              ) : null}
            </FormField>
            <FormField
              id="target-week"
              label="Target week"
              required
              helperText="Pick any day in the target week."
            >
              <input
                id="target-week"
                type="date"
                value={targetDate}
                onChange={(e) => setTargetDate(e.target.value)}
                className={inputClassName}
              />
              {targetWeekLabel ? (
                <p className="mt-2 rounded-md border border-border-subtle bg-surface-sunken px-3 py-2 text-caption text-text-secondary">
                  {targetWeekLabel}
                </p>
              ) : null}
            </FormField>
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField id="source-date" label="Source date" required>
              <input
                id="source-date"
                type="date"
                value={sourceDate}
                onChange={(e) => setSourceDate(e.target.value)}
                className={inputClassName}
              />
            </FormField>
            <FormField id="target-date" label="Target date" required>
              <input
                id="target-date"
                type="date"
                value={targetDate}
                onChange={(e) => setTargetDate(e.target.value)}
                className={inputClassName}
              />
            </FormField>
          </div>
        )}

        <Checkbox
          id="include-assignments"
          checked={includeAssignments}
          onCheckedChange={(c) => setIncludeAssignments(c === true)}
          label="Include staff assignments"
        />
      </div>
    </Dialog>
  )
}
