import { useId } from 'react'
import { Checkbox, RadioGroup, Switch } from '@/components/ui'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function CheckboxShowcase() {
  const id = useId()
  return (
    <ShowcaseSection id="checkbox" title="Checkbox" componentName="Checkbox">
      <ShowcaseDemoGrid columns={3}>
        <Checkbox id={`${id}-1`} label="Send appointment reminders" defaultChecked />
        <Checkbox id={`${id}-2`} label="Select all rows" checked="indeterminate" />
        <Checkbox id={`${id}-3`} label="Disabled option" disabled />
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function RadioGroupShowcase() {
  return (
    <ShowcaseSection id="radio-group" title="Radio group" componentName="RadioGroup">
      <ShowcaseDemoGrid>
        <ShowcaseDemo label="Vertical">
          <RadioGroup
            defaultValue="card"
            options={[
              { value: 'cash', label: 'Cash' },
              { value: 'card', label: 'Card' },
              { value: 'insurance', label: 'Insurance' },
            ]}
          />
        </ShowcaseDemo>
        <ShowcaseDemo label="Horizontal" propsHint="orientation=horizontal">
          <RadioGroup
            orientation="horizontal"
            defaultValue="day"
            options={[
              { value: 'day', label: 'Day' },
              { value: 'week', label: 'Week' },
              { value: 'month', label: 'Month' },
            ]}
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function SwitchShowcase() {
  const id = useId()
  return (
    <ShowcaseSection id="switch" title="Switch" componentName="Switch">
      <ShowcaseDemoGrid>
        <Switch id={`${id}-on`} label="Service active on this branch" defaultChecked />
        <Switch id={`${id}-off`} label="Disabled toggle" disabled />
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
