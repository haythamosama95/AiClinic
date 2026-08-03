import { FlaskConical } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { Combobox } from '@/components/ui/combobox/Combobox'
import { FormField } from '@/components/ui/form-field/FormField'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { INVESTIGATION_OPTIONS } from '../mock-data'
import type { InvestigationEntry } from '../types'

export type InvestigationFormDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  usedInvestigationIds: Set<string>
  editingEntry?: InvestigationEntry | null
  onSubmit: (entry: Omit<InvestigationEntry, 'id'>) => void
}

type FormState = {
  investigationId: string
  note: string
}

type FormErrors = {
  investigationId?: string
}

function getInitialInvestigationId(usedIds: Set<string>): string {
  return INVESTIGATION_OPTIONS.find((item) => !usedIds.has(item.id))?.id ?? ''
}

export function InvestigationFormDialog({
  open,
  onOpenChange,
  usedInvestigationIds,
  editingEntry,
  onSubmit,
}: InvestigationFormDialogProps) {
  const isEdit = editingEntry != null

  const [form, setForm] = useState<FormState>({
    investigationId: getInitialInvestigationId(usedInvestigationIds),
    note: '',
  })
  const [errors, setErrors] = useState<FormErrors>({})

  useEffect(() => {
    if (open) {
      setForm(
        editingEntry
          ? { investigationId: editingEntry.investigationId, note: editingEntry.note }
          : {
            investigationId: getInitialInvestigationId(usedInvestigationIds),
            note: '',
          },
      )
      setErrors({})
    }
  }, [open, usedInvestigationIds, editingEntry])

  const selectedInvestigation =
    INVESTIGATION_OPTIONS.find((item) => item.id === form.investigationId) ?? null
  const availableItems = INVESTIGATION_OPTIONS.map((item) => ({
    ...item,
    disabled:
      usedInvestigationIds.has(item.id) && item.id !== editingEntry?.investigationId,
    disabledReason: 'Already added',
  }))

  const handleSubmit = () => {
    const nextErrors: FormErrors = {}
    if (!form.investigationId) {
      nextErrors.investigationId = 'Select an investigation.'
    }
    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }
    onSubmit({
      investigationId: form.investigationId,
      note: form.note.trim(),
    })
    onOpenChange(false)
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={isEdit ? 'Edit investigation' : 'Add investigation'}
      description={
        isEdit
          ? 'Update the test or add clinical context for this order.'
          : 'Choose a diagnostic test and add any relevant clinical notes.'
      }
      size="md"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button leadingIcon={<FlaskConical size={16} />} onClick={handleSubmit}>
            {isEdit ? 'Save changes' : 'Add investigation'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <FormField
          id="investigation-type"
          label="Investigation"
          required
          error={errors.investigationId}
        >
          <Combobox
            id="investigation-type"
            placeholder="Search labs, imaging, and tests…"
            items={availableItems}
            value={selectedInvestigation}
            onValueChange={(item) => {
              setForm((prev) => ({
                ...prev,
                investigationId: item?.id ?? '',
              }))
              setErrors((prev) => ({ ...prev, investigationId: undefined }))
            }}
            aria-label="Investigation type"
          />
        </FormField>

        <FormField
          id="investigation-note"
          label="Clinical note"
          hint="Urgency, indication, or instructions for the lab or imaging team."
        >
          <Textarea
            id="investigation-note"
            rows={3}
            autoGrow
            value={form.note}
            onChange={(e) => setForm((prev) => ({ ...prev, note: e.target.value }))}
            placeholder="e.g. Fasting sample · rule out infection…"
          />
        </FormField>
      </div>
    </Dialog>
  )
}
