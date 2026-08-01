import { FormField } from '@/components/ui/form-field/FormField'
import { MoneyField } from '@/components/ui/money-field/MoneyField'
import { MultiSelect } from '@/components/ui/multi-select/MultiSelect'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { Switch } from '@/components/ui/switch/Switch'
import { TextInput } from '@/components/ui/text-input/TextInput'
import type { ServiceRecord } from '../types'

export type ServiceFormValues = {
  name: string
  price: number | null
  allBranches: boolean
  branchIds: string[]
}

export function emptyServiceFormValues(): ServiceFormValues {
  return {
    name: '',
    price: null,
    allBranches: true,
    branchIds: [],
  }
}

export function serviceToFormValues(service: ServiceRecord): ServiceFormValues {
  return {
    name: service.name,
    price: service.price,
    allBranches: service.allBranches,
    branchIds: service.branchIds,
  }
}

export function ServiceFormFields({
  idPrefix,
  values,
  onChange,
  branchOptions,
  currency,
}: {
  idPrefix: string
  values: ServiceFormValues
  onChange: (patch: Partial<ServiceFormValues>) => void
  branchOptions: ComboboxItem[]
  currency: string
}) {
  const selectedBranches = branchOptions.filter((b) => values.branchIds.includes(b.id))

  return (
    <div className="space-y-4">
      <FormField id={`${idPrefix}-name`} label="Service name" required>
        <TextInput
          id={`${idPrefix}-name`}
          value={values.name}
          onChange={(e) => onChange({ name: e.target.value })}
          placeholder="e.g. Dental cleaning"
        />
      </FormField>
      <FormField id={`${idPrefix}-price`} label="Default price" required>
        <MoneyField
          id={`${idPrefix}-price`}
          currency={currency}
          value={values.price ?? undefined}
          onValueChange={(price) => onChange({ price: price ?? null })}
        />
      </FormField>
      <div className="flex items-center gap-3">
        <Switch
          id={`${idPrefix}-all-branches`}
          checked={values.allBranches}
          onCheckedChange={(allBranches) =>
            onChange({ allBranches, branchIds: allBranches ? [] : values.branchIds })
          }
        />
        <label htmlFor={`${idPrefix}-all-branches`} className="text-body text-text-primary">
          Available at all branches
        </label>
      </div>
      {!values.allBranches ? (
        <FormField id={`${idPrefix}-branches`} label="Branch assignment" required>
          <MultiSelect
            id={`${idPrefix}-branches`}
            value={selectedBranches}
            onValueChange={(items) => onChange({ branchIds: items.map((i) => i.id) })}
            options={branchOptions}
            placeholder="Select branches"
          />
        </FormField>
      ) : null}
    </div>
  )
}
