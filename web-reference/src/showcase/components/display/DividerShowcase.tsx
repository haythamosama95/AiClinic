import { Divider } from '@/components/divider'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function DividerShowcase() {
  return (
    <ShowcaseSection
      id="divider"
      title="Divider"
      description="Hairline separators with optional centered label."
      componentName="Divider"
    >
      <ShowcaseDemoGrid>
        <ShowcaseDemo label="Horizontal" propsHint='orientation="horizontal"'>
          <div className="w-full space-y-4">
            <p className="text-body text-text-secondary">Section above</p>
            <Divider />
            <p className="text-body text-text-secondary">Section below</p>
          </div>
        </ShowcaseDemo>

        <ShowcaseDemo label="With label" propsHint="label">
          <div className="w-full">
            <Divider label="Or continue with" />
          </div>
        </ShowcaseDemo>

        <ShowcaseDemo label="Vertical" propsHint='orientation="vertical"'>
          <div className="flex h-12 items-center gap-4">
            <span className="text-body-sm text-text-secondary">Patients</span>
            <Divider orientation="vertical" />
            <span className="text-body-sm text-text-secondary">Appointments</span>
          </div>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
