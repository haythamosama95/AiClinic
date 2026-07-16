import { useEffect } from 'react'
import { ArrowLeft, ArrowRight, Save } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { Card } from '@/components/card/Card'
import { PageHeader } from '@/components/layout/PageHeader'
import { StepPanel } from '@/pages/app/settings/components/AnimatedPanels'
import { patientFullName } from '@/data/patients'
import { resolveTransition } from '@/lib/motion'
import { FindingsSection } from './sections/FindingsSection'
import { IntakeSection } from './sections/IntakeSection'
import { TreatmentSection } from './sections/TreatmentSection'
import { useVisitForm } from './useVisitForm'
import { VisitCompleted } from './VisitCompleted'
import { VisitPatientBanner } from './VisitPatientBanner'
import { VisitSummary } from './VisitSummary'
import { VisitSummaryChronicle } from './VisitSummaryChronicle'

export type VisitPageProps = {
  patientId?: string
  summaryView?: 'card' | 'chronicle'
  onNavigate?: (route: string) => void
}

export function VisitPage({ patientId, summaryView = 'card', onNavigate }: VisitPageProps) {
  const visit = useVisitForm({ patientId })
  const { ensureSummary, isSummary, isCompleted, resetVisit } = visit
  const isChronicle = summaryView === 'chronicle'
  const encounterRoute = patientId ? `encounters/${patientId}` : 'encounters'
  const patientRoute = patientId ? `patients/${patientId}` : undefined

  useEffect(() => {
    if (isChronicle && !isSummary && !isCompleted) {
      ensureSummary()
    }
  }, [isChronicle, isSummary, isCompleted, ensureSummary])

  const handleBackToCard = () => {
    onNavigate?.(encounterRoute)
  }

  const handleStartNewVisit = () => {
    resetVisit()
    onNavigate?.(encounterRoute)
  }

  const handleFinalize = () => {
    visit.finalizeVisit()
  }

  const pageTitle = isCompleted
    ? 'Visit completed'
    : isSummary
      ? isChronicle
        ? 'Encounter chronicle'
        : 'Review visit'
      : 'Document visit'

  const pageDescription = isCompleted
    ? `Encounter for ${patientFullName(visit.patient)} has been finalized`
    : isSummary
      ? isChronicle
        ? `Continuous record for ${patientFullName(visit.patient)}`
        : `Check documentation for ${patientFullName(visit.patient)} before finalizing`
      : `Record clinical information for ${patientFullName(visit.patient)}`

  return (
    <>
      <PageHeader
        title={pageTitle}
        description={pageDescription}
        actions={
          !isSummary && !isCompleted ? (
            <Button variant="secondary" size="sm" leadingIcon={<Save size={14} />}>
              Save draft
            </Button>
          ) : undefined
        }
      />

      <div className="mt-6 space-y-6">
        {!visit.isSummary && !visit.isCompleted ? (
          <VisitPatientBanner
            patient={visit.patient}
            currentPhase={visit.phase}
            onPhaseSelect={visit.goToPhase}
          />
        ) : null}

        <AnimatePresence mode="wait">
          {visit.isCompleted && visit.finalizedAt ? (
            <motion.div
              key="completed"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={resolveTransition({ duration: 'base', ease: 'out' })}
            >
              <VisitCompleted
                patient={visit.patient}
                finalizedAt={visit.finalizedAt}
                onStartNewVisit={handleStartNewVisit}
                onViewPatient={
                  patientRoute && onNavigate ? () => onNavigate(patientRoute) : undefined
                }
              />
            </motion.div>
          ) : visit.isSummary ? (
            <motion.div
              key={isChronicle ? 'chronicle' : 'summary'}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={resolveTransition({ duration: 'base', ease: 'out' })}
            >
              {isChronicle ? (
                <VisitSummaryChronicle
                  patient={visit.patient}
                  form={visit.form}
                  finalizedAt={visit.finalizedAt ?? new Date()}
                  onBack={handleBackToCard}
                  onEdit={visit.goBack}
                  onNewVisit={handleStartNewVisit}
                />
              ) : (
                <VisitSummary
                  form={visit.form}
                  onEdit={visit.goBack}
                  onFinalize={handleFinalize}
                />
              )}
            </motion.div>
          ) : (
            <motion.div
              key="form"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={resolveTransition({ duration: 'base', ease: 'out' })}
            >
              <Card
                variant="raised"
                padding="lg"
                className="relative min-w-0 overflow-hidden rounded-2xl"
              >
                <div
                  className="pointer-events-none absolute inset-0 opacity-[0.25]"
                  aria-hidden
                  style={{
                    backgroundImage: `
                      linear-gradient(var(--border-subtle) 1px, transparent 1px),
                      linear-gradient(90deg, var(--border-subtle) 1px, transparent 1px)
                    `,
                    backgroundSize: '20px 20px',
                    maskImage:
                      'radial-gradient(ellipse 90% 70% at 30% 0%, black 15%, transparent 65%)',
                  }}
                />
                <div className="relative">
                  <StepPanel stepKey={visit.phase} direction={visit.direction}>
                    {visit.phase === 'intake' ? (
                      <IntakeSection form={visit.form} onChange={visit.updateForm} />
                    ) : visit.phase === 'findings' ? (
                      <FindingsSection form={visit.form} onChange={visit.updateForm} />
                    ) : (
                      <TreatmentSection form={visit.form} onChange={visit.updateForm} />
                    )}
                  </StepPanel>

                  <div className="mt-10 flex items-center justify-between gap-4 border-t border-border-subtle pt-6">
                    <Button
                      variant="secondary"
                      leadingIcon={<ArrowLeft size={16} />}
                      onClick={visit.goBack}
                      disabled={!visit.canGoBack}
                    >
                      Back
                    </Button>
                    <Button
                      variant="primary"
                      trailingIcon={<ArrowRight size={16} />}
                      onClick={visit.goNext}
                    >
                      {visit.isLastFormPhase ? 'Review visit' : 'Continue'}
                    </Button>
                  </div>
                </div>
              </Card>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </>
  )
}
