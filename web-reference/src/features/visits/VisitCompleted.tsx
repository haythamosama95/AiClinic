import {
  Activity,
  ArrowRight,
  Check,
  ClipboardList,
  Pill,
  Printer,
  UserRound,
} from 'lucide-react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { Card } from '@/components/card/Card'
import type { Patient } from '@/data/patients'
import { patientFullName } from '@/data/patients'
import { motionPresets, resolveTransition, staggerChildren } from '@/lib/motion'

export type VisitCompletedProps = {
  patient: Patient
  finalizedAt: Date
  onStartNewVisit: () => void
  onViewPatient?: () => void
}

const DOCUMENTED_PHASES = [
  { id: 'intake', label: 'Intake', icon: ClipboardList },
  { id: 'findings', label: 'Findings', icon: Activity },
  { id: 'treatment', label: 'Treatment', icon: Pill },
] as const

function RecordedPhase({
  label,
  icon: Icon,
}: {
  label: string
  icon: typeof ClipboardList
}) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-xl border border-status-success-border bg-surface-default px-3 py-3.5 text-center sm:px-4">
      <span className="flex size-9 items-center justify-center rounded-full bg-status-success-surface text-status-success-fg">
        <Icon size={16} strokeWidth={1.75} aria-hidden />
      </span>
      <p className="text-caption font-medium text-text-primary">{label}</p>
      <span className="flex items-center gap-1 text-[11px] font-medium text-status-success-fg">
        <Check size={11} strokeWidth={2.5} aria-hidden />
        Recorded
      </span>
    </div>
  )
}

export function VisitCompleted({
  patient,
  finalizedAt,
  onStartNewVisit,
  onViewPatient,
}: VisitCompletedProps) {
  const preset = motionPresets['fade-scale']
  const transition = resolveTransition(preset)
  const sealTransition = resolveTransition({ duration: 'deliberate', ease: 'out' })

  const formattedDate = finalizedAt.toLocaleString('en-GB', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })

  const name = patientFullName(patient)

  return (
    <motion.div
      initial="hidden"
      animate="visible"
      variants={staggerChildren(70)}
      className="mx-auto max-w-xl"
    >
      <motion.div variants={preset.variants} transition={transition}>
        <Card
          variant="raised"
          padding="lg"
          className="relative overflow-hidden rounded-2xl text-center"
        >
          <div
            className="pointer-events-none absolute inset-0 opacity-60"
            aria-hidden
            style={{
              background:
                'radial-gradient(ellipse 80% 55% at 50% 0%, var(--status-success-surface) 0%, transparent 70%)',
            }}
          />

          <div className="relative flex flex-col items-center">
            <motion.div
              initial={{ scale: 0.6, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ ...sealTransition, delay: 0.05 }}
              className="relative mb-6"
            >
              <span
                className="absolute inset-0 scale-125 rounded-full bg-status-success-surface opacity-70 blur-md"
                aria-hidden
              />
              <span className="relative flex size-20 items-center justify-center rounded-full border-2 border-status-success-border bg-status-success-surface text-status-success-fg shadow-[0_0_0_6px_var(--surface-raised),0_0_0_10px_var(--status-success-surface)]">
                <motion.span
                  initial={{ scale: 0, rotate: -20 }}
                  animate={{ scale: 1, rotate: 0 }}
                  transition={{ ...sealTransition, delay: 0.2 }}
                >
                  <Check size={36} strokeWidth={1.75} aria-hidden />
                </motion.span>
              </span>
            </motion.div>

            <h2 className="font-display text-h1 text-text-primary">Visit completed</h2>
            <p className="mt-2 max-w-sm text-body text-text-secondary">
              Documentation for{' '}
              <span className="font-medium text-text-primary">{name}</span> is on record and
              available in the patient chart.
            </p>
            <time
              dateTime={finalizedAt.toISOString()}
              className="mt-2 text-caption tabular-nums text-text-tertiary"
            >
              {formattedDate}
            </time>

            <motion.div
              variants={staggerChildren(50)}
              initial="hidden"
              animate="visible"
              className="mt-8 grid w-full grid-cols-3 gap-2 sm:gap-3"
              aria-label="Documented phases"
            >
              {DOCUMENTED_PHASES.map((phase, index) => (
                <motion.div
                  key={phase.id}
                  variants={motionPresets['slide-up'].variants}
                  transition={{ ...resolveTransition(motionPresets['slide-up']), delay: 0.15 + index * 0.06 }}
                >
                  <RecordedPhase label={phase.label} icon={phase.icon} />
                </motion.div>
              ))}
            </motion.div>

            <div className="mt-8 flex w-full flex-col-reverse gap-2 sm:flex-row sm:justify-center">
              {onViewPatient ? (
                <Button
                  variant="secondary"
                  leadingIcon={<UserRound size={16} />}
                  onClick={onViewPatient}
                >
                  View patient record
                </Button>
              ) : null}
              <Button
                variant="secondary"
                leadingIcon={<Printer size={16} />}
                onClick={() => window.print()}
              >
                Print summary
              </Button>
              <Button
                variant="primary"
                trailingIcon={<ArrowRight size={16} />}
                onClick={onStartNewVisit}
              >
                Start new visit
              </Button>
            </div>
          </div>
        </Card>
      </motion.div>
    </motion.div>
  )
}
