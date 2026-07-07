import { Plus, Stethoscope, Trash2 } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { Card } from '@/components/card/Card'
import { FormField } from '@/components/ui/form-field/FormField'
import { MoneyField } from '@/components/ui/money-field/MoneyField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { createEmptyService, type ServiceDraft } from '@/data/settings'
import { useSetup } from '../../SetupContext'
import type { StepErrors } from '../validation'

export type ServicesStepProps = {
  errors: StepErrors
}

export function ServicesStep({ errors }: ServicesStepProps) {
  const { draft, setServices } = useSetup()

  const updateService = (id: string, patch: Partial<ServiceDraft>) => {
    setServices(draft.services.map((s) => (s.id === id ? { ...s, ...patch } : s)))
  }

  const addService = () => setServices([...draft.services, createEmptyService()])

  const removeService = (id: string) => {
    setServices(draft.services.filter((s) => s.id !== id))
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start gap-4">
        <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-[var(--color-violet-50)] text-[var(--color-violet-600)]">
          <Stethoscope size={22} strokeWidth={1.5} aria-hidden />
        </div>
        <div>
          <h2 className="font-display text-h2 text-text-primary">Service catalog</h2>
          <p className="mt-1 max-w-lg text-body text-text-secondary">
            Define the procedures and treatments you bill for. You can add more services and
            branch-specific pricing later.
          </p>
        </div>
      </div>

      {errors._form ? (
        <p className="text-body-sm text-status-danger-fg" role="alert">
          {errors._form}
        </p>
      ) : null}

      <Card variant="flat" padding="lg">
        <div className="mb-4 hidden gap-3 text-caption font-medium text-text-tertiary sm:grid sm:grid-cols-[1fr_10rem_2.5rem]">
          <span>Service name</span>
          <span>Price</span>
          <span className="sr-only">Actions</span>
        </div>

        <ul className="space-y-3">
          {draft.services.map((service, index) => {
            const prefix = `service-${index}`
            const isLast = index === draft.services.length - 1

            return (
              <li
                key={service.id}
                className={
                  isLast
                    ? 'grid gap-3 sm:grid-cols-[1fr_10rem_2.5rem] sm:items-start'
                    : 'grid gap-3 border-b border-border-subtle pb-3 sm:grid-cols-[1fr_10rem_2.5rem] sm:items-start'
                }
              >
                <FormField
                  id={`${service.id}-name`}
                  label="Service name"
                  required
                  error={errors[`${prefix}-name`]}
                  className="sm:[&_label]:sr-only"
                >
                  <TextInput
                    id={`${service.id}-name`}
                    value={service.name}
                    onChange={(e) => updateService(service.id, { name: e.target.value })}
                    placeholder="e.g. Dental cleaning"
                    invalid={!!errors[`${prefix}-name`]}
                  />
                </FormField>

                <FormField
                  id={`${service.id}-price`}
                  label="Price"
                  required
                  error={errors[`${prefix}-price`]}
                  className="sm:[&_label]:sr-only"
                >
                  <MoneyField
                    id={`${service.id}-price`}
                    currency={draft.organization.currency}
                    value={service.price ?? undefined}
                    onValueChange={(price) => updateService(service.id, { price: price ?? null })}
                    invalid={!!errors[`${prefix}-price`]}
                  />
                </FormField>

                <div className="flex items-end justify-end sm:pt-0">
                  {draft.services.length > 1 ? (
                    <IconButton
                      icon={<Trash2 size={16} />}
                      label="Remove service"
                      variant="ghost"
                      size="sm"
                      onClick={() => removeService(service.id)}
                    />
                  ) : (
                    <span className="size-9" aria-hidden />
                  )}
                </div>
              </li>
            )
          })}
        </ul>

        <Button
          variant="ghost"
          leadingIcon={<Plus size={16} />}
          onClick={addService}
          className="mt-4 w-full sm:w-auto"
        >
          Add another service
        </Button>
      </Card>
    </div>
  )
}
