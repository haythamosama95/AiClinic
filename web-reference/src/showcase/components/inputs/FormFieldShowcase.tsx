import { useId } from 'react'
import { FormField, TextInput } from '@/components/ui'
import { ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function FormFieldShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="form-field"
      title="Form field"
      componentName="FormField"
      description="Label, required mark, hint tooltip, helper text, and error scaffold."
    >
      <ShowcaseDemoGrid>
        <FormField
          id={`${id}-default`}
          label="Default price"
          helperText="Used when a branch has no price override."
        >
          <TextInput id={`${id}-default`} placeholder="e.g. 350.00" />
        </FormField>
        <FormField
          id={`${id}-error`}
          label="Service name"
          required
          hint="Must be unique within your organization."
          error="A service with this name already exists in your organization."
        >
          <TextInput id={`${id}-error`} invalid defaultValue="Consultation" />
        </FormField>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
