import { useId } from 'react'
import { FormField, NumberInput } from '@/components/ui'
import { ShowcaseSection } from '../../ShowcasePrimitives'

export function NumberInputShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="number-input"
      title="Number / stepper"
      componentName="NumberInput"
      description="Tabular figures with optional +/− steppers and min/max."
    >
      <FormField id={id} label="Quantity" helperText="Defaults to 1 for invoice items.">
        <NumberInput id={id} defaultValue={1} min={1} max={99} className="max-w-xs" />
      </FormField>
    </ShowcaseSection>
  )
}
