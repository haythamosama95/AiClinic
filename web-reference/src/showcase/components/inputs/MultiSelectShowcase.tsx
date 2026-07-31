import { useId, useState } from 'react'
import { FormField, MultiSelect, type ComboboxItem } from '@/components/ui'
import { ShowcaseSection } from '../../ShowcasePrimitives'

const OPTIONS: ComboboxItem[] = [
  { id: 'main', label: 'Main branch', meta: 'Cairo' },
  { id: 'downtown', label: 'Downtown', meta: 'Giza' },
  { id: 'north', label: 'North clinic', meta: 'Alexandria' },
]

export function MultiSelectShowcase() {
  const id = useId()
  const [value, setValue] = useState<ComboboxItem[]>([])

  return (
    <ShowcaseSection
      id="multi-select"
      title="Multi-select / token"
      componentName="MultiSelect"
      description="Removable chips inside the field with combobox popover and All branches option."
    >
      <FormField
        id={id}
        label="Selected branches"
        helperText='Use "All branches" for org-wide access.'
      >
        <MultiSelect
          id={id}
          className="max-w-md"
          options={OPTIONS}
          value={value}
          onValueChange={setValue}
        />
      </FormField>
    </ShowcaseSection>
  )
}
