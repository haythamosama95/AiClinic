import { Building2, Stethoscope, UserRound } from 'lucide-react'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { Combobox } from '@/components/ui/combobox/Combobox'
import { FormField } from '@/components/ui/form-field/FormField'
import { Select } from '@/components/ui/select/Select'
import type { BookAppointmentDraft } from './types'

export type BookAppointmentStep1Props = {
  draft: BookAppointmentDraft
  errors: Partial<Record<'patient' | 'branch', string>>
  patientItems: ComboboxItem[]
  selectedPatient: ComboboxItem | null
  branchOptions: { value: string; label: string }[]
  doctorOptions: { value: string; label: string }[]
  doctorCount: number
  onFieldChange: (patch: Partial<BookAppointmentDraft>) => void
}

export function BookAppointmentStep1({
  draft,
  errors,
  patientItems,
  selectedPatient,
  branchOptions,
  doctorOptions,
  doctorCount,
  onFieldChange,
}: BookAppointmentStep1Props) {
  return (
    <div className="space-y-6">
      <div className="rounded-xl border border-border-subtle bg-surface-sunken/60 p-4">
        <p className="text-body-sm text-text-secondary">
          Choose who is visiting and where. A preferred doctor is optional — leave it open to see
          every slot any doctor can take.
        </p>
      </div>

      <FormField
        id="book-patient"
        label="Patient"
        required
        error={errors.patient}
        helperText="Search by name or MRN."
      >
        <Combobox
          id="book-patient"
          placeholder="Search patients…"
          items={patientItems}
          value={selectedPatient}
          onValueChange={(item) => onFieldChange({ patientId: item?.id ?? null })}
          invalid={Boolean(errors.patient)}
        />
      </FormField>

      <FormField
        id="book-branch"
        label="Branch"
        required
        error={errors.branch}
        hint="Only active branches with scheduling are listed."
      >
        <Select
          id="book-branch"
          placeholder="Select branch"
          options={branchOptions}
          value={draft.branchId ?? ''}
          onValueChange={(value) => onFieldChange({ branchId: value || null })}
          invalid={Boolean(errors.branch)}
        />
      </FormField>

      <FormField
        id="book-doctor"
        label="Preferred doctor"
        helperText={
          draft.branchId
            ? `${doctorCount} doctor${doctorCount !== 1 ? 's' : ''} schedule at this branch.`
            : 'Select a branch first.'
        }
      >
        <Select
          id="book-doctor"
          placeholder="Any available doctor"
          options={doctorOptions}
          value={draft.preferredDoctorId ?? ''}
          onValueChange={(value) =>
            onFieldChange({ preferredDoctorId: value || null })
          }
          disabled={!draft.branchId}
        />
      </FormField>

      {draft.branchId && selectedPatient ? (
        <dl className="grid gap-3 rounded-xl border border-border-default bg-surface-default p-4 sm:grid-cols-3">
          <SummaryItem icon={<UserRound size={16} />} label="Patient" value={selectedPatient.label} />
          <SummaryItem
            icon={<Building2 size={16} />}
            label="Branch"
            value={branchOptions.find((b) => b.value === draft.branchId)?.label ?? '—'}
          />
          <SummaryItem
            icon={<Stethoscope size={16} />}
            label="Preference"
            value={
              draft.preferredDoctorId
                ? (doctorOptions.find((d) => d.value === draft.preferredDoctorId)?.label ?? '—')
                : 'Any doctor'
            }
          />
        </dl>
      ) : null}
    </div>
  )
}

function SummaryItem({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode
  label: string
  value: string
}) {
  return (
    <div className="flex gap-3">
      <span className="mt-0.5 text-icon-muted" aria-hidden>
        {icon}
      </span>
      <div className="min-w-0">
        <dt className="text-overline text-text-tertiary">{label}</dt>
        <dd className="truncate text-body-sm font-medium text-text-primary">{value}</dd>
      </div>
    </div>
  )
}
