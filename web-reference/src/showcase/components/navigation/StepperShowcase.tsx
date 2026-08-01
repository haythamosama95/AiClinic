import { useState } from 'react'
import { Stepper } from '@/components/navigation/Stepper'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

const STEPS = [
  { id: 'patient', label: 'Patient details', description: 'Demographics and contact' },
  { id: 'visit', label: 'Visit info', description: 'Reason and provider' },
  { id: 'billing', label: 'Billing', description: 'Services and payment' },
  { id: 'review', label: 'Review', description: 'Confirm and submit' },
]

export function StepperShowcase() {
  const [horizontal, setHorizontal] = useState(1)
  const [vertical, setVertical] = useState(0)

  return (
    <ShowcaseSection
      id="stepper"
      title="Stepper"
      description="Multi-step flows with current, complete, and upcoming states."
      componentName="Stepper"
    >
      <ShowcaseDemoGrid columns={1}>
        <ShowcaseDemo label="Horizontal" propsHint='orientation="horizontal"'>
          <Stepper
            steps={STEPS}
            currentStep={horizontal}
            onBack={() => setHorizontal((s) => Math.max(0, s - 1))}
            onNext={() => setHorizontal((s) => Math.min(STEPS.length - 1, s + 1))}
            className="w-full"
          />
        </ShowcaseDemo>
        <ShowcaseDemo label="Vertical" propsHint='orientation="vertical"'>
          <Stepper
            steps={STEPS.slice(0, 3)}
            currentStep={vertical}
            orientation="vertical"
            onBack={() => setVertical((s) => Math.max(0, s - 1))}
            onNext={() => setVertical((s) => Math.min(2, s + 1))}
            className="max-w-sm"
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
