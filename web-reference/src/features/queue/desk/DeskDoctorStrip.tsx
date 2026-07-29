import { Coffee, DoorOpen, Stethoscope } from 'lucide-react'
import { cn } from '@/lib/cn'
import { doctorQueueCount } from '@/features/queue/desk/desk-helpers'
import type { DoctorOnShift, QueueAppointment } from '@/features/queue/types'

const STATUS_META = {
  idle: {
    label: 'Available',
    dot: 'bg-status-success-fg',
    icon: DoorOpen,
    surface: 'bg-status-success-surface/50',
  },
  with_patient: {
    label: 'With patient',
    dot: 'bg-action-primary',
    icon: Stethoscope,
    surface: 'bg-surface-selected',
  },
  on_break: {
    label: 'On break',
    dot: 'bg-status-warning-fg',
    icon: Coffee,
    surface: 'bg-status-warning-surface/40',
  },
} as const

export type DeskDoctorStripProps = {
  doctors: DoctorOnShift[]
  appointments: QueueAppointment[]
}

export function DeskDoctorStrip({ doctors, appointments }: DeskDoctorStripProps) {
  return (
    <div
      className="grid gap-px overflow-hidden rounded-lg border border-border-subtle bg-border-subtle sm:grid-cols-3"
      role="list"
      aria-label="Doctors on shift"
    >
      {doctors.map((doctor) => {
        const meta = STATUS_META[doctor.status]
        const Icon = meta.icon
        const queueCount = doctorQueueCount(appointments, doctor.id)

        return (
          <div
            key={doctor.id}
            role="listitem"
            className={cn('flex flex-col gap-2 bg-surface-default px-4 py-3', meta.surface)}
          >
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="truncate text-body-strong text-text-primary">{doctor.fullName}</p>
                <p className="truncate text-caption text-text-secondary">{doctor.roomNumber}</p>
              </div>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-default/80 px-2 py-0.5 text-caption text-text-secondary">
                <span className={cn('size-1.5 rounded-full', meta.dot)} aria-hidden />
                <Icon size={11} aria-hidden />
                {meta.label}
              </span>
            </div>

            {doctor.currentPatientName ? (
              <p className="truncate text-body-sm text-text-primary">
                {doctor.currentPatientName}
              </p>
            ) : (
              <p className="text-body-sm text-text-tertiary">No patient in room</p>
            )}

            <p className="font-mono text-caption tabular-nums text-text-tertiary">
              {queueCount} in queue · {doctor.patientsSeen} seen today
            </p>
          </div>
        )
      })}
    </div>
  )
}
