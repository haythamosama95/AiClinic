import { Avatar } from '@/components/avatar/Avatar'
import { Card } from '@/components/card/Card'
import type { Patient } from '@/data/patients'
import { patientFullName } from '@/data/patients'
import { cn } from '@/lib/cn'
import { VisitStepRail } from './VisitStepRail'
import type { VisitPhase } from './types'

function patientAge(dateOfBirth: string): number {
  const today = new Date()
  const dob = new Date(`${dateOfBirth}T00:00:00`)
  let age = today.getFullYear() - dob.getFullYear()
  const hadBirthday =
    today.getMonth() > dob.getMonth() ||
    (today.getMonth() === dob.getMonth() && today.getDate() >= dob.getDate())
  if (!hadBirthday) age -= 1
  return age
}

export type VisitPatientBannerProps = {
  patient: Patient
  currentPhase?: VisitPhase
  onPhaseSelect?: (phase: Exclude<VisitPhase, 'summary' | 'completed'>) => void
  className?: string
}

export function VisitPatientBanner({
  patient,
  currentPhase,
  onPhaseSelect,
  className,
}: VisitPatientBannerProps) {
  const showSteps = currentPhase !== undefined
  const name = patientFullName(patient)
  const age = patientAge(patient.dateOfBirth)

  return (
    <Card
      variant="raised"
      className={cn('overflow-hidden rounded-2xl border-border-subtle', className)}
      role="region"
      aria-label="Visit context"
    >
      <div
        className={cn(
          'flex flex-col gap-3 px-4 py-3 sm:flex-row sm:items-center sm:gap-5 sm:px-5',
          showSteps && 'lg:gap-8',
        )}
      >
        <div className="flex min-w-0 shrink-0 items-center gap-3">
          <Avatar name={name} size="md" />
          <div className="min-w-0">
            <h2 className="truncate font-display text-body-strong leading-tight text-text-primary">
              {name}
            </h2>
            <p className="text-caption tabular-nums text-text-secondary">{age} years old</p>
          </div>
        </div>

        {showSteps && currentPhase ? (
          <>
            <span
              className="hidden h-7 w-px shrink-0 bg-border-subtle sm:block"
              aria-hidden
            />
            <div className="min-w-0 flex-1">
              <p className="sr-only">Visit progress</p>
              <VisitStepRail
                currentPhase={currentPhase}
                onPhaseSelect={onPhaseSelect}
              />
            </div>
          </>
        ) : null}
      </div>
    </Card>
  )
}
