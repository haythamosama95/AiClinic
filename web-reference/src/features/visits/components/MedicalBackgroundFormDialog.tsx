import { ClipboardList } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { Combobox } from '@/components/ui/combobox/Combobox'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { FormField } from '@/components/ui/form-field/FormField'
import { Textarea } from '@/components/ui/textarea/Textarea'
import type { MedicalBackgroundEntry } from '../types'

export type MedicalBackgroundFormDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description: string
  itemLabel: string
  noteLabel: string
  noteHint: string
  notePlaceholder: string
  searchPlaceholder: string
  options: ComboboxItem[]
  usedItemIds: Set<string>
  editingEntry?: MedicalBackgroundEntry | null
  onSubmit: (entry: Omit<MedicalBackgroundEntry, 'id'>) => void
}

type FormState = {
  itemId: string
  note: string
}

type FormErrors = {
  itemId?: string
}

function getInitialItemId(options: ComboboxItem[], usedIds: Set<string>): string {
  return options.find((item) => !usedIds.has(item.id))?.id ?? ''
}

export function MedicalBackgroundFormDialog({
  open,
  onOpenChange,
  title,
  description,
  itemLabel,
  noteLabel,
  noteHint,
  notePlaceholder,
  searchPlaceholder,
  options,
  usedItemIds,
  editingEntry,
  onSubmit,
}: MedicalBackgroundFormDialogProps) {
  const isEdit = editingEntry != null

  const [form, setForm] = useState<FormState>({
    itemId: getInitialItemId(options, usedItemIds),
    note: '',
  })
  const [errors, setErrors] = useState<FormErrors>({})

  useEffect(() => {
    if (open) {
      setForm(
        editingEntry
          ? { itemId: editingEntry.itemId, note: editingEntry.note }
          : {
            itemId: getInitialItemId(options, usedItemIds),
            note: '',
          },
      )
      setErrors({})
    }
  }, [open, usedItemIds, editingEntry, options])

  const selectedItem = options.find((item) => item.id === form.itemId) ?? null
  const availableItems = options.map((item) => ({
    ...item,
    disabled: usedItemIds.has(item.id) && item.id !== editingEntry?.itemId,
    disabledReason: 'Already added',
  }))

  const handleSubmit = () => {
    const nextErrors: FormErrors = {}
    if (!form.itemId) {
      nextErrors.itemId = `Select ${itemLabel.toLowerCase()}.`
    }
    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }
    onSubmit({
      itemId: form.itemId,
      note: form.note.trim(),
    })
    onOpenChange(false)
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={title}
      description={description}
      size="md"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button leadingIcon={<ClipboardList size={16} />} onClick={handleSubmit}>
            {isEdit ? 'Save changes' : 'Add to record'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <FormField
          id="background-item"
          label={itemLabel}
          required
          error={errors.itemId}
        >
          <Combobox
            id="background-item"
            placeholder={searchPlaceholder}
            items={availableItems}
            value={selectedItem}
            onValueChange={(item) => {
              setForm((prev) => ({
                ...prev,
                itemId: item?.id ?? '',
              }))
              setErrors((prev) => ({ ...prev, itemId: undefined }))
            }}
            aria-label={itemLabel}
          />
        </FormField>

        <FormField id="background-note" label={noteLabel} hint={noteHint}>
          <Textarea
            id="background-note"
            rows={3}
            autoGrow
            value={form.note}
            onChange={(e) => setForm((prev) => ({ ...prev, note: e.target.value }))}
            placeholder={notePlaceholder}
          />
        </FormField>
      </div>
    </Dialog>
  )
}
