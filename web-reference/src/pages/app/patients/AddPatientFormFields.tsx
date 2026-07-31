import { MapPin } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import { Avatar } from '@/components/avatar/Avatar'
import { Divider } from '@/components/divider/Divider'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { DatePicker } from '@/components/ui/date-picker/DatePicker'
import { FormField } from '@/components/ui/form-field/FormField'
import { PhoneInput } from '@/components/ui/phone-input/PhoneInput'
import { Select } from '@/components/ui/select/Select'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { motionPresets, resolveTransition } from '@/lib/motion'
import { MOCK_BRANCH_NAME } from './useAddPatientRegistration'
import type { AddPatientFormErrors, AddPatientFormValues } from './add-patient-form'

const GENDER_OPTIONS = [
  { value: 'male', label: 'Male' },
  { value: 'female', label: 'Female' },
  { value: 'other', label: 'Other' },
]

const MARITAL_STATUS_OPTIONS = [
  { value: 'single', label: 'Single' },
  { value: 'married', label: 'Married' },
  { value: 'divorced', label: 'Divorced' },
  { value: 'widowed', label: 'Widowed' },
]

export type AddPatientFormFieldsProps = {
  formId: string
  values: AddPatientFormValues
  errors: AddPatientFormErrors
  trimmedName: string
  showPreview: boolean
  reducedMotion: boolean
  autoFocus?: boolean
  onSubmit: (e: React.FormEvent) => void
  onFieldChange: <K extends keyof AddPatientFormValues>(
    key: K,
    value: AddPatientFormValues[K],
  ) => void
}

export function AddPatientFormFields({
  formId,
  values,
  errors,
  trimmedName,
  showPreview,
  reducedMotion,
  autoFocus = false,
  onSubmit,
  onFieldChange,
}: AddPatientFormFieldsProps) {
  return (
    <form id={formId} onSubmit={onSubmit} className="space-y-6">
      <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-surface-muted/60 px-3 py-2.5">
        <MapPin size={15} className="shrink-0 text-icon-muted" aria-hidden />
        <p className="text-body-sm text-text-secondary">
          Registering at{' '}
          <span className="font-medium text-text-primary">{MOCK_BRANCH_NAME}</span>
        </p>
      </div>

      <AnimatePresence initial={false}>
        {showPreview ? (
          <motion.div
            key="identity-preview"
            initial={reducedMotion ? false : { opacity: 0, y: -6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={reducedMotion ? undefined : { opacity: 0, y: -6 }}
            transition={resolveTransition(motionPresets.fade)}
            className="rounded-lg border border-border-subtle bg-gradient-to-br from-surface-muted/80 to-surface-default px-4 py-3.5"
          >
            <div className="flex items-center gap-3.5">
              <Avatar name={trimmedName} size="lg" />
              <div className="min-w-0">
                <p className="truncate text-body-strong text-text-primary">{trimmedName}</p>
                <p className="text-caption text-text-tertiary">
                  New record · MRN assigned on save
                </p>
              </div>
            </div>
          </motion.div>
        ) : null}
      </AnimatePresence>

      <section className="space-y-4" aria-labelledby={`${formId}-details`}>
        <SectionHeader
          title="Patient details"
          description="Core information used to identify the patient and reach them for care."
        />
        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            id={`${formId}-fullName`}
            label="Full name"
            required
            hint="Legal name as it appears on government ID."
            error={errors.fullName}
            className="sm:col-span-2"
          >
            <TextInput
              id={`${formId}-fullName`}
              value={values.fullName}
              onChange={(e) => onFieldChange('fullName', e.target.value)}
              placeholder="e.g. Sara Hassan Ibrahim"
              invalid={!!errors.fullName}
              autoFocus={autoFocus}
            />
          </FormField>

          <FormField
            id={`${formId}-dob`}
            label="Date of birth"
            hint="Used with name for duplicate detection."
            error={errors.dateOfBirth as string | undefined}
          >
            <DatePicker
              id={`${formId}-dob`}
              value={values.dateOfBirth}
              onValueChange={(date) => onFieldChange('dateOfBirth', date)}
              placeholder="Select date"
              max={new Date()}
            />
          </FormField>

          <FormField
            id={`${formId}-gender`}
            label="Gender"
            hint="Optional. Shown on the patient profile."
            error={errors.gender}
          >
            <Select
              id={`${formId}-gender`}
              value={values.gender}
              onValueChange={(gender) => onFieldChange('gender', gender)}
              options={GENDER_OPTIONS}
              placeholder="Select gender"
              invalid={!!errors.gender}
            />
          </FormField>

          <FormField
            id={`${formId}-phone`}
            label="Mobile number"
            hint="Used for reminders and duplicate checks."
            error={errors.phone}
          >
            <PhoneInput
              id={`${formId}-phone`}
              value={values.phone}
              onValueChange={(phone) => onFieldChange('phone', phone)}
              invalid={!!errors.phone}
            />
          </FormField>

          <FormField
            id={`${formId}-maritalStatus`}
            label="Marital state"
            hint="Optional. Shown on the patient profile."
            error={errors.maritalStatus}
          >
            <Select
              id={`${formId}-maritalStatus`}
              value={values.maritalStatus}
              onValueChange={(maritalStatus) => onFieldChange('maritalStatus', maritalStatus)}
              options={MARITAL_STATUS_OPTIONS}
              placeholder="Select marital state"
              invalid={!!errors.maritalStatus}
            />
          </FormField>
        </div>
      </section>

      <Divider />

      <section className="space-y-4" aria-labelledby={`${formId}-notes`}>
        <SectionHeader
          title="Clinical notes"
          description="Optional context visible to staff on the patient profile."
        />
        <FormField
          id={`${formId}-notes`}
          label="Notes"
          helperText="Allergies, referral source, or front-desk remarks."
          error={errors.notes}
        >
          <Textarea
            id={`${formId}-notes`}
            value={values.notes}
            onChange={(e) => onFieldChange('notes', e.target.value)}
            placeholder="e.g. Referred by Dr. Nabil. Penicillin allergy noted verbally."
            rows={3}
            autoGrow
            maxLength={500}
            showCounter
            invalid={!!errors.notes}
          />
        </FormField>
      </section>

      {errors._form ? (
        <p className="text-body-sm text-status-danger-fg" role="alert">
          {errors._form}
        </p>
      ) : null}
    </form>
  )
}
