import { useState } from 'react'
import { Chip } from '@/components/chip'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function ChipShowcase() {
  const [selected, setSelected] = useState<string[]>(['Today'])
  const [filters, setFilters] = useState(['Branch A', 'Active'])

  const toggle = (value: string) => {
    setSelected((prev) =>
      prev.includes(value) ? prev.filter((v) => v !== value) : [...prev, value],
    )
  }

  const removeFilter = (value: string) => {
    setFilters((prev) => prev.filter((v) => v !== value))
  }

  return (
    <ShowcaseSection
      id="chip"
      title="Chip / Tag"
      description="Compact descriptors for filters and multi-select values."
      componentName="Chip"
    >
      <ShowcaseDemoGrid>
        <ShowcaseDemo label="Default" propsHint="neutral descriptor">
          <Chip>Insurance</Chip>
          <Chip>Walk-in</Chip>
        </ShowcaseDemo>

        <ShowcaseDemo label="Removable" propsHint='removable onRemove'>
          {filters.map((filter) => (
            <Chip key={filter} removable onRemove={() => removeFilter(filter)}>
              {filter}
            </Chip>
          ))}
        </ShowcaseDemo>

        <ShowcaseDemo label="Selectable filters" propsHint='selectable selected onSelect'>
          {['Today', 'This week', 'This month'].map((option) => (
            <Chip
              key={option}
              selectable
              selected={selected.includes(option)}
              onSelect={() => toggle(option)}
            >
              {option}
            </Chip>
          ))}
        </ShowcaseDemo>

        <ShowcaseDemo label="Disabled" propsHint="disabled">
          <Chip disabled>Inactive service</Chip>
          <Chip selectable selected disabled>
            Locked
          </Chip>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
