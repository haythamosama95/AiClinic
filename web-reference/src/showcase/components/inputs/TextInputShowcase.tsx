import { Mail, Percent } from 'lucide-react'
import { TextInput } from '@/components/ui'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
  ShowcaseVariantMatrix,
} from '../../ShowcasePrimitives'

export function TextInputShowcase() {
  return (
    <ShowcaseSection
      id="text-input"
      title="Text input"
      componentName="TextInput"
      description="Default, affix, icon, clear, sizes, and universal states."
    >
      <ShowcaseDemoGrid columns={3}>
        <ShowcaseDemo label="Sizes" propsHint="sm · md · lg">
          <div className="flex w-full flex-col gap-3">
            <TextInput size="sm" placeholder="Small" />
            <TextInput size="md" placeholder="Medium" />
            <TextInput size="lg" placeholder="Large" />
          </div>
        </ShowcaseDemo>
        <ShowcaseDemo label="Variants">
          <div className="flex w-full flex-col gap-3">
            <TextInput leadingIcon={<Mail className="size-4" />} placeholder="Email address" />
            <TextInput prefix="EGP" placeholder="0.00" />
            <TextInput suffix="%" trailingIcon={<Percent className="size-4" />} placeholder="0" />
          </div>
        </ShowcaseDemo>
        <ShowcaseDemo label="States">
          <div className="flex w-full flex-col gap-3">
            <TextInput placeholder="e.g. Consultation" />
            <TextInput defaultValue="General checkup" showClear onClear={() => {}} />
            <TextInput disabled defaultValue="Disabled" />
            <TextInput readOnly defaultValue="Read only" />
            <TextInput invalid defaultValue="Invalid value" />
          </div>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
      <ShowcaseVariantMatrix title="With value + clear">
        <TextInput defaultValue="Filter term" showClear onClear={() => {}} className="max-w-xs" />
      </ShowcaseVariantMatrix>
    </ShowcaseSection>
  )
}
