import { ArrowLeft, ArrowRight, CheckCircle2, Sparkles } from 'lucide-react'
import { motion } from 'motion/react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import type { Step } from '@/components/navigation/Stepper'
import { Progress } from '@/components/progress/Progress'
import { resolveTransition } from '@/lib/motion'
import { StepPanel } from '../components/AnimatedPanels'
import { useSetup } from '../SetupContext'
import { BranchStep } from './steps/BranchStep'
import { OrganizationStep } from './steps/OrganizationStep'
import { ServicesStep } from './steps/ServicesStep'
import { StaffStep } from './steps/StaffStep'
import {
  hasErrors,
  validateBranches,
  validateOrganization,
  validateServices,
  validateStaff,
  type StepErrors,
} from './validation'

const SETUP_STEPS: Step[] = [
  { id: 'organization', label: 'Organization', description: 'Name & region' },
  { id: 'branch', label: 'Branch', description: 'Locations & hours' },
  { id: 'staff', label: 'Staff', description: 'Team & access' },
  { id: 'services', label: 'Services', description: 'Catalog & pricing' },
]

function validateStep(step: number, draft: ReturnType<typeof useSetup>['draft']): StepErrors {
  switch (step) {
    case 0:
      return validateOrganization(draft.organization)
    case 1:
      return validateBranches(draft.branches)
    case 2:
      return validateStaff(draft.staff, draft.branches.length)
    case 3:
      return validateServices(draft.services)
    default:
      return {}
  }
}

function SetupComplete() {
  const { draft, resetSetup } = useSetup()

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.96 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={resolveTransition({ duration: 'slow', ease: 'out' })}
      className="flex flex-col items-center px-6 py-16 text-center"
    >
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ ...resolveTransition({ duration: 'deliberate', ease: 'out' }), delay: 0.1 }}
        className="mb-6 flex size-16 items-center justify-center rounded-full bg-[var(--color-teal-50)] text-[var(--color-teal-600)]"
      >
        <CheckCircle2 size={32} strokeWidth={1.5} aria-hidden />
      </motion.div>

      <h2 className="font-display text-h1 text-text-primary">Clinic is ready</h2>
      <p className="mt-2 max-w-md text-body text-text-secondary">
        <span className="font-medium text-text-primary">{draft.organization.name}</span> is
        configured with {draft.branches.length} branch
        {draft.branches.length !== 1 ? 'es' : ''}, {draft.staff.length} staff member
        {draft.staff.length !== 1 ? 's' : ''}, and {draft.services.length} service
        {draft.services.length !== 1 ? 's' : ''}.
      </p>

      <dl className="mt-8 grid w-full max-w-sm gap-3 text-start text-body-sm">
        <div className="flex justify-between rounded-lg bg-surface-muted px-4 py-3">
          <dt className="text-text-tertiary">Timezone</dt>
          <dd className="text-text-primary">{draft.organization.timezone}</dd>
        </div>
        <div className="flex justify-between rounded-lg bg-surface-muted px-4 py-3">
          <dt className="text-text-tertiary">Currency</dt>
          <dd className="text-text-primary">{draft.organization.currency}</dd>
        </div>
      </dl>

      <Button variant="secondary" className="mt-8" onClick={resetSetup}>
        Run setup again
      </Button>
    </motion.div>
  )
}

function VerticalStepRail({
  steps,
  currentStep,
}: {
  steps: Step[]
  currentStep: number
}) {
  return (
    <ol className="relative space-y-0" aria-label="Setup progress">
      {steps.map((step, index) => {
        const state =
          index < currentStep ? 'complete' : index === currentStep ? 'current' : 'upcoming'
        const isLast = index === steps.length - 1

        return (
          <li key={step.id} className="relative flex gap-4 pb-8 last:pb-0" aria-current={state === 'current' ? 'step' : undefined}>
            {!isLast ? (
              <span
                className="absolute start-[15px] top-8 h-[calc(100%-1rem)] w-px bg-border-default"
                aria-hidden
              >
                <motion.span
                  className="block w-full bg-action-primary"
                  initial={{ height: '0%' }}
                  animate={{ height: index < currentStep ? '100%' : '0%' }}
                  transition={resolveTransition({ duration: 'base', ease: 'standard' })}
                />
              </span>
            ) : null}

            <motion.span
              className="relative z-[1] flex size-8 shrink-0 items-center justify-center rounded-full border text-body-sm font-medium tabular-nums"
              animate={{
                borderColor:
                  state === 'complete' || state === 'current'
                    ? 'var(--action-primary)'
                    : 'var(--border-default)',
                backgroundColor:
                  state === 'complete' ? 'var(--action-primary)' : 'var(--surface-default)',
                color:
                  state === 'complete'
                    ? 'var(--action-primary-fg)'
                    : state === 'current'
                      ? 'var(--text-primary)'
                      : 'var(--text-tertiary)',
                boxShadow:
                  state === 'current' ? '0 0 0 3px var(--surface-canvas), 0 0 0 5px var(--border-focus)' : 'none',
              }}
              transition={resolveTransition({ duration: 'quick', ease: 'out' })}
            >
              {state === 'complete' ? (
                <CheckCircle2 size={16} strokeWidth={2} aria-hidden />
              ) : (
                index + 1
              )}
            </motion.span>

            <div className="min-w-0 pt-0.5">
              <p
                className={
                  state === 'upcoming' ? 'text-body text-text-tertiary' : 'text-body-strong text-text-primary'
                }
              >
                {step.label}
              </p>
              {step.description ? (
                <p className="mt-0.5 text-caption text-text-secondary">{step.description}</p>
              ) : null}
            </div>
          </li>
        )
      })}
    </ol>
  )
}

export function SetupWizard() {
  const { draft, step, setStep, completeSetup, completed } = useSetup()
  const [direction, setDirection] = useState(1)
  const [errors, setErrors] = useState<StepErrors>({})

  if (completed) {
    return <SetupComplete />
  }

  const progress = ((step + 1) / SETUP_STEPS.length) * 100
  const isLastStep = step === SETUP_STEPS.length - 1

  const goNext = () => {
    const stepErrors = validateStep(step, draft)
    if (hasErrors(stepErrors)) {
      setErrors(stepErrors)
      return
    }
    setErrors({})
    if (isLastStep) {
      completeSetup()
      return
    }
    setDirection(1)
    setStep(step + 1)
  }

  const goBack = () => {
    setErrors({})
    setDirection(-1)
    setStep(step - 1)
  }

  const stepContent = () => {
    switch (step) {
      case 0:
        return <OrganizationStep errors={errors} />
      case 1:
        return <BranchStep errors={errors} />
      case 2:
        return <StaffStep errors={errors} />
      case 3:
        return <ServicesStep errors={errors} />
      default:
        return null
    }
  }

  return (
    <div className="relative overflow-hidden rounded-2xl border border-border-subtle bg-surface-default shadow-elevation-1">
      {/* Blueprint grid — signature atmosphere */}
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.35]"
        aria-hidden
        style={{
          backgroundImage: `
            linear-gradient(var(--border-subtle) 1px, transparent 1px),
            linear-gradient(90deg, var(--border-subtle) 1px, transparent 1px)
          `,
          backgroundSize: '24px 24px',
          maskImage: 'radial-gradient(ellipse 80% 60% at 50% 0%, black 20%, transparent 70%)',
        }}
      />

      <div className="relative border-b border-border-subtle px-6 py-5 sm:px-8">
        <div className="flex items-center gap-2 text-caption font-medium uppercase tracking-wider text-[var(--color-teal-600)]">
          <Sparkles size={14} aria-hidden />
          Clinic setup
        </div>
        <p className="mt-1 text-body-sm text-text-secondary">
          Step {step + 1} of {SETUP_STEPS.length}
        </p>
        <Progress value={progress} showLabel className="mt-4 max-w-xs" />
      </div>

      <div className="relative grid gap-8 p-6 sm:grid-cols-[minmax(0,13rem)_1fr] sm:p-8 lg:gap-12">
        <aside className="hidden sm:block">
          <VerticalStepRail steps={SETUP_STEPS} currentStep={step} />
        </aside>

        <div className="min-w-0">
          <StepPanel stepKey={String(step)} direction={direction}>
            {stepContent()}
          </StepPanel>

          <div className="mt-10 flex items-center justify-between gap-4 border-t border-border-subtle pt-6">
            <Button
              variant="secondary"
              leadingIcon={<ArrowLeft size={16} />}
              onClick={goBack}
              disabled={step === 0}
            >
              Back
            </Button>
            <Button
              variant="primary"
              trailingIcon={isLastStep ? undefined : <ArrowRight size={16} />}
              onClick={goNext}
            >
              {isLastStep ? 'Finish setup' : 'Continue'}
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
