import { Pill } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { Combobox } from '@/components/ui/combobox/Combobox'
import { FormField } from '@/components/ui/form-field/FormField'
import { Select } from '@/components/ui/select/Select'
import { TextInput } from '@/components/ui/text-input/TextInput'
import {
  DURATION_OPTIONS,
  FREQUENCY_OPTIONS,
  TREATMENT_MEDICATION_OPTIONS,
} from '../mock-data'
import type { TreatmentPlanEntry } from '../types'

export type TreatmentPlanFormDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  editingEntry?: TreatmentPlanEntry | null
  onSubmit: (entry: Omit<TreatmentPlanEntry, 'id'>) => void
}

type FormState = {
  medicationId: string
  dosage: string
  frequency: string
  duration: string
}

type FormErrors = {
  medicationId?: string
  dosage?: string
  frequency?: string
  duration?: string
}

const EMPTY_FORM: FormState = {
  medicationId: '',
  dosage: '',
  frequency: '',
  duration: '',
}

export function TreatmentPlanFormDialog({
  open,
  onOpenChange,
  editingEntry,
  onSubmit,
}: TreatmentPlanFormDialogProps) {
  const isEdit = editingEntry != null

  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [errors, setErrors] = useState<FormErrors>({})

  useEffect(() => {
    if (open) {
      setForm(
        editingEntry
          ? {
            medicationId: editingEntry.medicationId,
            dosage: editingEntry.dosage,
            frequency: editingEntry.frequency,
            duration: editingEntry.duration,
          }
          : EMPTY_FORM,
      )
      setErrors({})
    }
  }, [open, editingEntry])

  const selectedMedication =
    TREATMENT_MEDICATION_OPTIONS.find((item) => item.id === form.medicationId) ?? null

  const handleSubmit = () => {
    const nextErrors: FormErrors = {}
    if (!form.medicationId) {
      nextErrors.medicationId = 'Select a medication.'
    }
    if (!form.dosage.trim()) {
      nextErrors.dosage = 'Enter the dosage.'
    }
    if (!form.frequency) {
      nextErrors.frequency = 'Select a frequency.'
    }
    if (!form.duration) {
      nextErrors.duration = 'Select a duration.'
    }
    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }
    onSubmit({
      medicationId: form.medicationId,
      dosage: form.dosage.trim(),
      frequency: form.frequency,
      duration: form.duration,
    })
    onOpenChange(false)
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={isEdit ? 'Edit prescription' : 'Add prescription'}
      description={
        isEdit
          ? 'Update medication, dosage, frequency, or duration.'
          : 'Prescribe a medication with dosage, frequency, and duration.'
      }
      size="md"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button leadingIcon={<Pill size={16} />} onClick={handleSubmit}>
            {isEdit ? 'Save changes' : 'Add prescription'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <FormField
          id="treatment-medication"
          label="Medication"
          required
          error={errors.medicationId}
        >
          <Combobox
            id="treatment-medication"
            placeholder="Search medications…"
            items={TREATMENT_MEDICATION_OPTIONS}
            value={selectedMedication}
            onValueChange={(item) => {
              setForm((prev) => ({ ...prev, medicationId: item?.id ?? '' }))
              setErrors((prev) => ({ ...prev, medicationId: undefined }))
            }}
            aria-label="Medication"
          />
        </FormField>

        <div className="grid gap-4 sm:grid-cols-2">
          <FormField id="treatment-dosage" label="Dosage" required error={errors.dosage}>
            <TextInput
              id="treatment-dosage"
              value={form.dosage}
              onChange={(e) => {
                setForm((prev) => ({ ...prev, dosage: e.target.value }))
                setErrors((prev) => ({ ...prev, dosage: undefined }))
              }}
              placeholder="e.g. 500 mg"
              aria-label="Dosage"
            />
          </FormField>

          <FormField id="treatment-frequency" label="Frequency" required error={errors.frequency}>
            <Select
              value={form.frequency}
              options={FREQUENCY_OPTIONS}
              placeholder="Select frequency"
              onValueChange={(frequency) => {
                setForm((prev) => ({ ...prev, frequency }))
                setErrors((prev) => ({ ...prev, frequency: undefined }))
              }}
              aria-label="Frequency"
            />
          </FormField>

          <FormField
            id="treatment-duration"
            label="Duration"
            required
            error={errors.duration}
            className="sm:col-span-2"
          >
            <Select
              value={form.duration}
              options={DURATION_OPTIONS}
              placeholder="Select duration"
              onValueChange={(duration) => {
                setForm((prev) => ({ ...prev, duration }))
                setErrors((prev) => ({ ...prev, duration: undefined }))
              }}
              aria-label="Duration"
            />
          </FormField>
        </div>
      </div>
    </Dialog>
  )
}
