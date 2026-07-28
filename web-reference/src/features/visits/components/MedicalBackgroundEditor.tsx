import { FormField } from '@/components/ui/form-field/FormField'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { MultiSelect } from '@/components/ui/multi-select/MultiSelect'
import { cn } from '@/lib/cn'

export type MedicalBackgroundEditorProps = {
  chronicConditions: ComboboxItem[]
  allergies: ComboboxItem[]
  currentMedications: ComboboxItem[]
  chronicConditionOptions: ComboboxItem[]
  allergyOptions: ComboboxItem[]
  medicationOptions: ComboboxItem[]
  onChronicConditionsChange: (items: ComboboxItem[]) => void
  onAllergiesChange: (items: ComboboxItem[]) => void
  onCurrentMedicationsChange: (items: ComboboxItem[]) => void
  className?: string
}

export function MedicalBackgroundEditor({
  chronicConditions,
  allergies,
  currentMedications,
  chronicConditionOptions,
  allergyOptions,
  medicationOptions,
  onChronicConditionsChange,
  onAllergiesChange,
  onCurrentMedicationsChange,
  className,
}: MedicalBackgroundEditorProps) {
  return (
    <div className={cn('space-y-5 rounded-xl border border-border-subtle bg-surface-default p-4', className)}>
      <div>
        <h3 className="text-body-strong text-text-primary">Medical background</h3>
        <p className="mt-0.5 text-body-sm text-text-secondary">
          Chronic conditions, allergies, and current medications relevant to this visit.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <FormField
          id="chronic-conditions"
          label="Chronic conditions"
          helperText="Active diagnoses and long-term conditions."
        >
          <MultiSelect
            id="chronic-conditions"
            placeholder="Add chronic conditions…"
            options={chronicConditionOptions}
            value={chronicConditions}
            onValueChange={onChronicConditionsChange}
            allLabel="Select all conditions"
          />
        </FormField>

        <FormField
          id="allergies"
          label="Allergies"
          helperText="Drug, food, and environmental allergies."
        >
          <MultiSelect
            id="allergies"
            placeholder="Add allergies…"
            options={allergyOptions}
            value={allergies}
            onValueChange={onAllergiesChange}
            allLabel="Select all allergies"
          />
        </FormField>

        <FormField
          id="current-medications"
          label="Current medications"
          helperText="Medications the patient is taking at the time of visit."
        >
          <MultiSelect
            id="current-medications"
            placeholder="Add medications…"
            options={medicationOptions}
            value={currentMedications}
            onValueChange={onCurrentMedicationsChange}
            allLabel="Select all medications"
          />
        </FormField>
      </div>
    </div>
  )
}
