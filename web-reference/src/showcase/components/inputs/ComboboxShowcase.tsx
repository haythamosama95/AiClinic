import { useId, useState } from 'react'
import { Combobox, FormField, type ComboboxItem } from '@/components/ui'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

const MOCK_CATALOG: ComboboxItem[] = [
  { id: '1', label: 'Ahmed Hassan', meta: 'Patient · #1042', initials: 'AH' },
  { id: '2', label: 'Consultation', meta: 'Service · EGP 350', initials: 'CO' },
  {
    id: '3',
    label: 'Blood panel',
    meta: 'Service · inactive',
    initials: 'BP',
    disabled: true,
    disabledReason: 'Inactive service',
  },
  { id: '4', label: 'Dr. Nadia El-Sayed', meta: 'Doctor · Cardiology', initials: 'NE' },
]

async function mockAsyncSearch(query: string): Promise<ComboboxItem[]> {
  await new Promise((r) => setTimeout(r, 600))
  if (!query.trim()) return MOCK_CATALOG.slice(0, 3)
  const lower = query.toLowerCase()
  return MOCK_CATALOG.filter(
    (item) =>
      item.label.toLowerCase().includes(lower) ||
      item.meta?.toLowerCase().includes(lower),
  )
}

export function ComboboxShowcase() {
  const id = useId()
  const [asyncValue, setAsyncValue] = useState<ComboboxItem | null>(null)
  const [staticValue, setStaticValue] = useState<ComboboxItem | null>(null)

  return (
    <ShowcaseSection
      id="combobox"
      title="Combobox / autocomplete"
      componentName="Combobox"
      description="Async search, empty state, match highlight, and ineligible items with reason."
    >
      <ShowcaseDemoGrid>
        <FormField
          id={`${id}-async`}
          label="Search catalog (async)"
          helperText="Debounced async search with loading state."
        >
          <Combobox
            id={`${id}-async`}
            className="max-w-md"
            placeholder="Search patients or services"
            onSearch={mockAsyncSearch}
            value={asyncValue}
            onValueChange={setAsyncValue}
          />
        </FormField>
        <FormField id={`${id}-static`} label="Static list (ineligible item)">
          <Combobox
            id={`${id}-static`}
            className="max-w-md"
            items={MOCK_CATALOG}
            value={staticValue}
            onValueChange={setStaticValue}
            placeholder="Pick from catalog"
          />
        </FormField>
        <ShowcaseDemo label="Empty results" propsHint="onSearch → []">
          <Combobox
            className="max-w-md"
            items={[]}
            onSearch={async () => {
              await new Promise((r) => setTimeout(r, 400))
              return []
            }}
            placeholder="Type to see empty state"
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
