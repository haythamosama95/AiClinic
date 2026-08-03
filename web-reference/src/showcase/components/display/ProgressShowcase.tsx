import { useState } from 'react'
import { Progress } from '@/components/progress'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function ProgressShowcase() {
  const [value, setValue] = useState(62)

  return (
    <ShowcaseSection
      id="progress"
      title="Progress"
      description="Bar, circular, and step indicators with tabular percent labels."
      componentName="Progress"
    >
      <div className="space-y-6">
        <ShowcaseDemo label="Bar · determinate" propsHint='variant="bar" showLabel'>
          <div className="w-full max-w-md space-y-3">
            <Progress variant="bar" value={value} showLabel />
            <input
              type="range"
              min={0}
              max={100}
              value={value}
              onChange={(e) => setValue(Number(e.target.value))}
              aria-label="Adjust progress value"
              className="focus-ring w-full accent-action-primary"
            />
          </div>
        </ShowcaseDemo>

        <ShowcaseDemoGrid>
          <ShowcaseDemo label="Bar · indeterminate" propsHint="indeterminate">
            <div className="w-full max-w-xs">
              <Progress variant="bar" indeterminate />
            </div>
          </ShowcaseDemo>

          <ShowcaseDemo label="Circular" propsHint='variant="circular"'>
            <Progress variant="circular" value={75} />
            <Progress variant="circular" value={30} size="sm" />
            <Progress variant="circular" indeterminate />
          </ShowcaseDemo>

          <ShowcaseDemo label="Steps" propsHint='variant="steps" steps currentStep'>
            <div className="w-full max-w-sm space-y-4">
              <Progress variant="steps" steps={5} currentStep={2} />
              <Progress variant="steps" steps={4} currentStep={4} />
            </div>
          </ShowcaseDemo>
        </ShowcaseDemoGrid>
      </div>
    </ShowcaseSection>
  )
}
