import { useId } from 'react'
import { FormField, PasswordInput } from '@/components/ui'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function PasswordInputShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="password-input"
      title="Password input"
      componentName="PasswordInput"
      description="Masked with reveal toggle and caps-lock hint."
    >
      <ShowcaseDemoGrid>
        <FormField id={id} label="Password" helperText="At least 8 characters.">
          <PasswordInput id={id} placeholder="Enter password" />
        </FormField>
        <ShowcaseDemo label="Invalid">
          <PasswordInput invalid defaultValue="short" className="max-w-xs" />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
