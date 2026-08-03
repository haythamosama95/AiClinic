import { Activity } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { FormField } from '@/components/ui/form-field/FormField'
import { Select } from '@/components/ui/select/Select'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { getVitalSignById, VITAL_SIGN_CATALOG } from '../mock-data'
import type { VitalSignEntry } from '../types'

export type VitalSignFormDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  usedVitalSignIds: Set<string>
  editingEntry?: VitalSignEntry | null
  onSubmit: (entry: Omit<VitalSignEntry, 'id'>) => void
}

type FormState = {
  vitalSignId: string
  value: string
}

type FormErrors = {
  vitalSignId?: string
  value?: string
}

function getInitialVitalSignId(usedIds: Set<string>): string {
  return VITAL_SIGN_CATALOG.find((v) => !usedIds.has(v.id))?.id ?? ''
}

export function VitalSignFormDialog({
  open,
  onOpenChange,
  usedVitalSignIds,
  editingEntry,
  onSubmit,
}: VitalSignFormDialogProps) {
  const isEdit = editingEntry != null

  const [form, setForm] = useState<FormState>({
    vitalSignId: getInitialVitalSignId(usedVitalSignIds),
    value: '',
  })
  const [errors, setErrors] = useState<FormErrors>({})

  useEffect(() => {
    if (open) {
      setForm(
        editingEntry
          ? { vitalSignId: editingEntry.vitalSignId, value: editingEntry.value }
          : {
            vitalSignId: getInitialVitalSignId(usedVitalSignIds),
            value: '',
          },
      )
      setErrors({})
    }
  }, [open, usedVitalSignIds, editingEntry])

  const selectedDef = getVitalSignById(form.vitalSignId)
  const vitalOptions = VITAL_SIGN_CATALOG.map((v) => ({
    value: v.id,
    label: v.label,
    disabled: usedVitalSignIds.has(v.id) && v.id !== editingEntry?.vitalSignId,
  }))

  const handleSubmit = () => {
    const nextErrors: FormErrors = {}
    if (!form.vitalSignId) {
      nextErrors.vitalSignId = 'Select a vital sign type.'
    }
    if (!form.value.trim()) {
      nextErrors.value = 'Enter the measured value.'
    }
    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }
    onSubmit({ vitalSignId: form.vitalSignId, value: form.value.trim() })
    onOpenChange(false)
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={isEdit ? 'Edit vital sign' : 'Record vital sign'}
      description={
        isEdit
          ? 'Update the measurement type or value for this entry.'
          : 'Choose the measurement type and enter the value taken during this encounter.'
      }
      size="sm"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button leadingIcon={<Activity size={16} />} onClick={handleSubmit}>
            {isEdit ? 'Save changes' : 'Add vital sign'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <FormField
          id="vital-sign-type"
          label="Vital sign"
          required
          error={errors.vitalSignId}
        >
          <Select
            value={form.vitalSignId}
            options={vitalOptions}
            placeholder="Select type…"
            onValueChange={(vitalSignId) => {
              setForm((prev) => ({
                ...prev,
                vitalSignId,
                value: vitalSignId === prev.vitalSignId ? prev.value : '',
              }))
              setErrors((prev) => ({ ...prev, vitalSignId: undefined }))
            }}
            aria-label="Vital sign type"
          />
        </FormField>

        <FormField
          id="vital-sign-value"
          label={selectedDef ? `Value (${selectedDef.unit})` : 'Value'}
          required
          error={errors.value}
        >
          <TextInput
            id="vital-sign-value"
            value={form.value}
            onChange={(e) => {
              setForm((prev) => ({ ...prev, value: e.target.value }))
              setErrors((prev) => ({ ...prev, value: undefined }))
            }}
            placeholder={selectedDef?.placeholder ?? '—'}
            aria-label={`Value in ${selectedDef?.unit ?? 'units'}`}
            autoFocus
          />
        </FormField>
      </div>
    </Dialog>
  )
}
