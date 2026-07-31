import { useId } from 'react'
import { FormField, MoneyField } from '@/components/ui'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function MoneyFieldShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="money-field"
      title="Money field"
      componentName="MoneyField"
      description="EGP affix, tabular figures, 2-decimal scale, thousands grouping on blur."
    >
      <ShowcaseDemoGrid>
        <FormField id={id} label="Default price" required>
          <MoneyField id={id} defaultValue={350} className="max-w-xs" />
        </FormField>
        <ShowcaseDemo label="Invalid">
          <MoneyField invalid defaultValue={-10} className="max-w-xs" />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
