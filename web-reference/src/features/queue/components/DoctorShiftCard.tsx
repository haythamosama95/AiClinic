import { Coffee, DoorOpen, PhoneForwarded, Stethoscope, UserRound } from 'lucide-react'
import { motion } from 'motion/react'
import { Badge } from '@/components/badge'
import { Button } from '@/components/actions/Button'
import { Card } from '@/components/card/Card'
import { Progress } from '@/components/progress/Progress'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import type { DoctorOnShift, DoctorShiftStatus } from '@/features/queue/types'

export type DoctorShiftCardProps = {
  doctor: DoctorOnShift
  onCallNext?: (doctorId: string) => void
  className?: string
}

const STATUS_CONFIG: Record<
  DoctorShiftStatus,
  { label: string; color: 'success' | 'teal' | 'warning'; icon: typeof Stethoscope }
> = {
  idle: { label: 'Available', color: 'success', icon: DoorOpen },
  with_patient: { label: 'With patient', color: 'teal', icon: Stethoscope },
  on_break: { label: 'On break', color: 'warning', icon: Coffee },
}

export function DoctorShiftCard({ doctor, onCallNext, className }: DoctorShiftCardProps) {
  const status = STATUS_CONFIG[doctor.status]
  const StatusIcon = status.icon
  const totalPatients = doctor.patientsSeen + doctor.patientsRemaining
  const progressValue =
    totalPatients > 0 ? Math.round((doctor.patientsSeen / totalPatients) * 100) : 0
  const transition = resolveTransition(motionPresets['fade-scale'])

  return (
    <motion.div
      initial={getReducedMotion() ? false : 'hidden'}
      animate="visible"
      variants={motionPresets['fade-scale'].variants}
      transition={transition}
      className={className}
    >
      <Card variant="raised" padding="sm" className="h-full">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate text-body-strong text-text-primary">{doctor.fullName}</p>
            <p className="truncate text-caption text-text-secondary">{doctor.specialty}</p>
          </div>
          <Badge color={status.color} variant="soft" size="sm">
            <StatusIcon size={11} aria-hidden className="shrink-0" />
            {status.label}
          </Badge>
        </div>

        <div className="mt-3 flex items-center gap-2 text-caption text-text-tertiary">
          <DoorOpen size={13} strokeWidth={1.75} aria-hidden />
          <span>{doctor.roomNumber}</span>
          <span aria-hidden>·</span>
          <span className="font-mono tabular-nums">Until {doctor.shiftEndsAt}</span>
        </div>

        {doctor.currentPatientName ? (
          <div className="mt-3 rounded-lg border border-border-subtle bg-surface-sunken px-3 py-2">
            <p className="text-caption text-text-tertiary">Current patient</p>
            <p className="mt-0.5 flex items-center gap-1.5 truncate text-body-sm text-text-primary">
              <UserRound size={14} className="shrink-0 text-text-link" aria-hidden />
              {doctor.currentPatientName}
            </p>
          </div>
        ) : (
          <p className="mt-3 text-body-sm text-text-tertiary">No patient in room</p>
        )}

        <div className="mt-4 space-y-1.5">
          <div className="flex items-center justify-between text-caption">
            <span className="text-text-secondary">Shift progress</span>
            <span className="font-mono tabular-nums text-text-tertiary">
              {doctor.patientsSeen} seen · {doctor.patientsRemaining} left
            </span>
          </div>
          <Progress value={progressValue} size="sm" />
        </div>

        {onCallNext && doctor.status === 'idle' ? (
          <Button
            variant="secondary"
            size="sm"
            className="mt-4 w-full"
            leadingIcon={<PhoneForwarded size={14} />}
            onClick={() => onCallNext(doctor.id)}
          >
            Call next patient
          </Button>
        ) : null}
      </Card>
    </motion.div>
  )
}
