import { useId } from 'react'
import { FormField, Slider } from '@/components/ui'
import { ShowcaseSection } from '../../ShowcasePrimitives'

export function SliderShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="slider"
      title="Slider"
      componentName="Slider"
      description="Coverage percentage with tabular value label and keyboard arrows."
    >
      <FormField id={id} label="Insurance coverage" helperText="Rare — used for coverage percentage.">
        <Slider id={id} defaultValue={[75]} className="max-w-md" />
      </FormField>
    </ShowcaseSection>
  )
}
