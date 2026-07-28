import { Plus } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Dialog } from '@/components/dialog/Dialog'
import { FormField } from '@/components/ui/form-field/FormField'
import { MoneyField } from '@/components/ui/money-field/MoneyField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import type { CatalogService } from '@/data/services'

export type AddServiceDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  onAdd: (service: CatalogService) => void
}

type FormState = {
  name: string
  price: number | null
}

type FormErrors = {
  name?: string
  price?: string
}

const EMPTY_FORM: FormState = { name: '', price: null }

export function AddServiceDialog({ open, onOpenChange, onAdd }: AddServiceDialogProps) {
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [errors, setErrors] = useState<FormErrors>({})

  useEffect(() => {
    if (open) {
      setForm(EMPTY_FORM)
      setErrors({})
    }
  }, [open])

  const handleSubmit = () => {
    const nextErrors: FormErrors = {}
    if (!form.name.trim()) nextErrors.name = 'Enter a service name.'
    if (form.price === null || form.price <= 0) nextErrors.price = 'Enter a valid price.'

    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }

    const service: CatalogService = {
      id: `svc-new-${Date.now()}`,
      name: form.name.trim(),
      price: form.price!,
    }
    onAdd(service)
    onOpenChange(false)
  }

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title="Add to service catalog"
      description="Create a new billable service. It will be available for this visit and future invoices."
      size="md"
      footer={
        <>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button leadingIcon={<Plus size={16} />} onClick={handleSubmit}>
            Add service
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <FormField id="new-service-name" label="Service name" required error={errors.name}>
          <TextInput
            id="new-service-name"
            value={form.name}
            onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))}
            placeholder="e.g. Specialist consultation"
            invalid={!!errors.name}
            autoFocus
          />
        </FormField>

        <FormField id="new-service-price" label="Default price" required error={errors.price}>
          <MoneyField
            id="new-service-price"
            value={form.price ?? undefined}
            onValueChange={(price) => setForm((prev) => ({ ...prev, price: price ?? null }))}
            invalid={!!errors.price}
          />
        </FormField>
      </div>
    </Dialog>
  )
}
