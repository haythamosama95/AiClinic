import { ArrowRight, Bell, Footprints } from 'lucide-react'
import { motion } from 'motion/react'
import { Badge } from '@/components/badge'
import { Button } from '@/components/actions/Button'
import { Card } from '@/components/card/Card'
import { cn } from '@/lib/cn'
import { formatWaitDuration } from '@/features/queue/queue-status'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import type { WaitingPatient } from '@/features/queue/types'

export type WaitingPatientCardProps = {
  patient: WaitingPatient
  onNotify: (appointmentId: string) => void
  onSendToRoom: (appointmentId: string) => void
  className?: string
}

export function WaitingPatientCard({
  patient,
  onNotify,
  onSendToRoom,
  className,
}: WaitingPatientCardProps) {
  const transition = resolveTransition(motionPresets['fade-scale'])

  return (
    <motion.div
      initial={getReducedMotion() ? false : 'hidden'}
      animate="visible"
      variants={motionPresets['fade-scale'].variants}
      transition={transition}
      className={className}
    >
      <Card
        variant="flat"
        padding="sm"
        className={cn(
          'border-s-[3px]',
          patient.isOverdue
            ? 'border-s-status-warning-fg bg-status-warning-surface/25'
            : 'border-s-[var(--color-teal-500)]',
        )}
      >
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate text-body-strong text-text-primary">{patient.patientName}</p>
            <p className="truncate font-mono text-caption tabular-nums text-text-tertiary">
              {patient.patientMrn}
            </p>
          </div>
          <div className="text-end">
            <p
              className={cn(
                'font-mono text-body-sm font-medium tabular-nums',
                patient.isOverdue ? 'text-status-warning-fg' : 'text-text-primary',
              )}
            >
              {formatWaitDuration(patient.waitMinutes)}
            </p>
            <p className="text-caption text-text-tertiary">waiting</p>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          {patient.visitType === 'walk_in' ? (
            <Badge color="teal" variant="outline" size="sm">
              <Footprints size={11} aria-hidden className="shrink-0" />
              Walk-in
            </Badge>
          ) : (
            <Badge color="neutral" variant="soft" size="sm">
              Appointment
            </Badge>
          )}
          {patient.isOverdue ? (
            <Badge color="warning" variant="soft" size="sm">
              Overdue
            </Badge>
          ) : null}
        </div>

        {patient.preferredDoctorName ? (
          <p className="mt-2 truncate text-caption text-text-secondary">
            Prefers {patient.preferredDoctorName}
          </p>
        ) : (
          <p className="mt-2 text-caption text-text-tertiary">No doctor preference</p>
        )}

        <div className="mt-4 flex gap-2">
          <Button
            variant="ghost"
            size="sm"
            className="flex-1"
            leadingIcon={<Bell size={14} />}
            onClick={() => onNotify(patient.appointmentId)}
          >
            Notify
          </Button>
          <Button
            variant="secondary"
            size="sm"
            className="flex-1"
            leadingIcon={<ArrowRight size={14} />}
            onClick={() => onSendToRoom(patient.appointmentId)}
          >
            Send to room
          </Button>
        </div>
      </Card>
    </motion.div>
  )
}
