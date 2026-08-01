import { useState } from 'react'
import { Stepper } from '@/components/navigation/Stepper'
import { FormField } from '@/components/ui/form-field/FormField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { Select } from '@/components/ui/select/Select'
import { Checkbox } from '@/components/ui/checkbox/Checkbox'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { PatternFrame } from './PatternFrame'

const STEPS = [
  { id: 'branch', label: 'Branch details', description: 'Name and location' },
  { id: 'services', label: 'Services', description: 'Copy from existing branch' },
  { id: 'staff', label: 'Staff', description: 'Assign team members' },
  { id: 'review', label: 'Review', description: 'Confirm setup' },
]

export function WizardPattern() {
  const [step, setStep] = useState(0)

  return (
    <ShowcaseSection
      id="pattern-wizard"
      title="Wizard"
      componentName="05 §2 Wizard"
      description="Multi-step new-branch setup with stepper navigation."
    >
      <PatternFrame>
        <div className="space-y-8 p-4 sm:p-6">
          <Stepper
            steps={STEPS}
            currentStep={step}
            onBack={() => setStep((s) => Math.max(0, s - 1))}
            onNext={() => setStep((s) => Math.min(STEPS.length - 1, s + 1))}
            backLabel="Back"
            nextLabel={step === STEPS.length - 1 ? 'Finish setup' : 'Next'}
          />

          <div className="max-w-md space-y-4">
            {step === 0 ? (
              <>
                <FormField id="wiz-name" label="Branch name" required>
                  <TextInput id="wiz-name" placeholder="e.g. Zamalek" />
                </FormField>
                <FormField id="wiz-city" label="City">
                  <TextInput id="wiz-city" defaultValue="Cairo" />
                </FormField>
              </>
            ) : null}

            {step === 1 ? (
              <>
                <FormField id="wiz-source" label="Copy services from">
                  <Select
                    id="wiz-source"
                    options={[
                      { value: 'downtown', label: 'Downtown' },
                      { value: 'maadi', label: 'Maadi' },
                      { value: 'heliopolis', label: 'Heliopolis' },
                    ]}
                    defaultValue="downtown"
                  />
                </FormField>
                <label className="flex items-center gap-2 text-body-sm text-text-secondary">
                  <Checkbox defaultChecked aria-label="Include promotions" />
                  Include active promotions
                </label>
              </>
            ) : null}

            {step === 2 ? (
              <p className="text-body text-text-secondary">
                Select staff to assign to this branch. In production this would be a searchable multi-select.
              </p>
            ) : null}

            {step === 3 ? (
              <dl className="space-y-2 text-body-sm">
                <div className="flex justify-between">
                  <dt className="text-text-tertiary">Branch</dt>
                  <dd className="text-text-primary">Zamalek</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-text-tertiary">Services copied</dt>
                  <dd className="tabular-nums text-text-primary">24</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-text-tertiary">Staff assigned</dt>
                  <dd className="tabular-nums text-text-primary">6</dd>
                </div>
              </dl>
            ) : null}
          </div>
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
