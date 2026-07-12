import { useState } from 'react'
import { CalendarClock } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { FormField } from '@/components/ui/form-field/FormField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { Dialog } from '@/components/dialog/Dialog'
import { WorkingHoursEditor } from './WorkingHoursEditor'
import { hasConfiguredWorkingHours } from '../working-schedule'
import type { BranchFormValues } from '../types'

export type BranchFormFieldsProps = {
  values: BranchFormValues
  onChange: (patch: Partial<BranchFormValues>) => void
  disabled?: boolean
  errors?: Partial<Record<keyof BranchFormValues, string>>
  showWorkingHours?: boolean
}

export function BranchFormFields({
  values,
  onChange,
  disabled,
  errors = {},
  showWorkingHours = true,
}: BranchFormFieldsProps) {
  const [hoursOpen, setHoursOpen] = useState(false)
  const hoursConfigured = hasConfiguredWorkingHours(values.workingSchedule)

  return (
    <>
      <div className="grid gap-5 sm:grid-cols-2">
        <FormField id="branch-name" label="Branch name" required error={errors.name}>
          <TextInput
            id="branch-name"
            value={values.name}
            onChange={(e) => onChange({ name: e.target.value })}
            placeholder="Enter branch name"
            disabled={disabled}
            invalid={Boolean(errors.name)}
          />
        </FormField>

        <FormField id="branch-code" label="Branch code" required error={errors.code}>
          <TextInput
            id="branch-code"
            value={values.code}
            onChange={(e) => onChange({ code: e.target.value })}
            placeholder="e.g. MAIN"
            disabled={disabled}
            invalid={Boolean(errors.code)}
          />
        </FormField>

        <FormField
          id="branch-address"
          label="Address"
          required
          error={errors.address}
          className="sm:col-span-2"
        >
          <TextInput
            id="branch-address"
            value={values.address}
            onChange={(e) => onChange({ address: e.target.value })}
            placeholder="Street address"
            disabled={disabled}
            invalid={Boolean(errors.address)}
          />
        </FormField>

        <FormField id="branch-phone" label="Phone" required error={errors.phone}>
          <TextInput
            id="branch-phone"
            type="tel"
            inputMode="numeric"
            value={values.phone}
            onChange={(e) => onChange({ phone: e.target.value.replace(/\D/g, '') })}
            placeholder="Numbers only"
            disabled={disabled}
            invalid={Boolean(errors.phone)}
          />
        </FormField>

        <FormField id="branch-maps" label="Maps URL" required error={errors.mapsUrl}>
          <TextInput
            id="branch-maps"
            type="url"
            value={values.mapsUrl}
            onChange={(e) => onChange({ mapsUrl: e.target.value })}
            placeholder="maps.google.com/... or www.example.com"
            disabled={disabled}
            invalid={Boolean(errors.mapsUrl)}
          />
        </FormField>

        {showWorkingHours ? (
          <FormField
            id="branch-hours"
            label="Working hours"
            required
            error={errors.workingSchedule as string | undefined}
            className="sm:col-span-2"
          >
            <Button
              type="button"
              variant="secondary"
              leadingIcon={<CalendarClock size={16} />}
              onClick={() => setHoursOpen(true)}
              disabled={disabled}
              className="w-full justify-start sm:w-auto"
            >
              {hoursConfigured ? 'Working hours configured' : 'Set working hours'}
            </Button>
          </FormField>
        ) : null}
      </div>

      {showWorkingHours ? (
        <Dialog
          open={hoursOpen}
          onOpenChange={setHoursOpen}
          title="Working hours"
          description="Set open and close times for each day of the week."
          size="lg"
          footer={
            <Button type="button" onClick={() => setHoursOpen(false)}>
              Done
            </Button>
          }
        >
          <WorkingHoursEditor
            schedule={values.workingSchedule}
            onChange={(workingSchedule) => onChange({ workingSchedule })}
            disabled={disabled}
          />
        </Dialog>
      ) : null}
    </>
  )
}

function validatePhone(phone: string): string | undefined {
  if (!phone.trim()) return 'Phone is required'
  if (!/^\d+$/.test(phone)) return 'Phone must contain numbers only'
  return undefined
}

function validateMapsUrl(url: string): string | undefined {
  if (!url.trim()) return 'Maps URL is required'
  try {
    const normalized = url.startsWith('http') ? url : `https://${url}`
    new URL(normalized)
    return undefined
  } catch {
    return 'Enter a valid URL'
  }
}

export function validateBranch(values: BranchFormValues, requireHours = true) {
  const errors: Partial<Record<keyof BranchFormValues, string>> = {}
  if (!values.name.trim()) errors.name = 'Branch name is required'
  if (!values.code.trim()) errors.code = 'Branch code is required'
  if (!values.address.trim()) errors.address = 'Address is required'
  const phoneError = validatePhone(values.phone)
  if (phoneError) errors.phone = phoneError
  const mapsError = validateMapsUrl(values.mapsUrl)
  if (mapsError) errors.mapsUrl = mapsError
  if (requireHours && !hasConfiguredWorkingHours(values.workingSchedule)) {
    errors.workingSchedule = 'Working hours are required' as never
  }
  return errors
}

export function branchToFormValues(branch: {
  name: string
  code: string
  address: string
  phone: string
  mapsUrl: string
  workingSchedule: BranchFormValues['workingSchedule']
}): BranchFormValues {
  return {
    name: branch.name,
    code: branch.code,
    address: branch.address,
    phone: branch.phone,
    mapsUrl: branch.mapsUrl,
    workingSchedule: branch.workingSchedule,
  }
}
