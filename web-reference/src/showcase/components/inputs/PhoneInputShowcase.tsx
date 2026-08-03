import { useId } from 'react'
import { FormField, PhoneInput } from '@/components/ui'
import { ShowcaseSection } from '../../ShowcasePrimitives'

export function PhoneInputShowcase() {
  const id = useId()
  return (
    <ShowcaseSection
      id="phone-input"
      title="Phone input"
      componentName="PhoneInput"
      description="Egypt (+20) default, formats as typed, Latin digits."
    >
      <FormField id={id} label="Mobile number" helperText="Validates shape, not carrier.">
        <PhoneInput id={id} className="max-w-xs" />
      </FormField>
    </ShowcaseSection>
  )
}
