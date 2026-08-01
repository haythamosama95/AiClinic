import { useId } from 'react'
import { FormField, Select } from '@/components/ui'
import { ShowcaseSection } from '../../ShowcasePrimitives'

const OPTIONS = [
  { value: 'main', label: 'Main branch' },
  { value: 'downtown', label: 'Downtown' },
  {
    value: 'north',
    label: 'North clinic',
    disabled: true,
    disabledReason: 'Temporarily closed',
  },
]

export function SelectShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="select"
      title="Select"
      componentName="Select"
      description="Single choice dropdown with keyboard type-ahead and motion-fade-scale menu."
    >
      <FormField id={id} label="Branch">
        <Select id={id} options={OPTIONS} placeholder="Choose a branch" className="max-w-xs" />
      </FormField>
    </ShowcaseSection>
  )
}
