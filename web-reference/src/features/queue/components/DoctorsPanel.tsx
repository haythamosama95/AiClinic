import { Coffee, Stethoscope, UserCheck } from 'lucide-react'
import { cn } from '@/lib/cn'
import type { Appointment, Doctor } from '../types'
import { formatDuration, getDoctorLagMinutes, getIdleMinutes } from '../utils'

type DoctorsPanelProps = {
  doctors: Doctor[]
  appointments: Appointment[]
  now: number
  embedded?: boolean
  className?: string
}

const STATUS_CONFIG = {
  available: {
    label: 'Available',
    badgeClass: 'bg-status-success-surface text-status-success-fg',
    barColor: 'var(--status-success-fg)',
    Icon: UserCheck,
  },
  with_patient: {
    label: 'With patient',
    badgeClass: 'bg-status-info-surface text-status-info-fg',
    barColor: 'var(--status-info-fg)',
    Icon: Stethoscope,
  },
  on_break: {
    label: 'On break',
    badgeClass: 'bg-surface-muted text-text-tertiary',
    barColor: 'var(--text-tertiary)',
    Icon: Coffee,
  },
} as const

export function DoctorsPanel({
  doctors,
  appointments,
  now,
  embedded = false,
  className,
}: DoctorsPanelProps) {
  return (
    <section
      className={cn(
        embedded ? '' : 'rounded-xl border border-border-default bg-surface-default',
        className,
      )}
      aria-labelledby="doctors-panel-title"
    >
      <header
        className={cn(
          'shrink-0 px-4 py-3',
          !embedded && 'border-b border-border-default',
        )}
      >
        <h2 id="doctors-panel-title" className="queue-heading text-sm font-semibold text-text-primary">
          Doctors on shift
        </h2>
        <p className="text-xs text-text-secondary">{doctors.length} providers today</p>
      </header>

      <ul
        className={cn(
          'divide-y divide-border-subtle',
          embedded
            ? 'max-h-[min(60vh,28rem)] overflow-y-auto'
            : 'min-h-0 flex-1 overflow-y-auto',
        )}
      >
        {doctors.map((doctor) => {
          const config = STATUS_CONFIG[doctor.status]
          const lag = getDoctorLagMinutes(doctor, appointments, now)
          const idle = getIdleMinutes(doctor, now)

          return (
            <li key={doctor.id} className="px-4 py-3">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-text-primary">{doctor.name}</p>
                  <p className="text-xs text-text-secondary">{doctor.specialty}</p>
                </div>
                <span
                  className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide ${config.badgeClass}`}
                >
                  <config.Icon className="h-3 w-3" aria-hidden="true" />
                  {config.label}
                </span>
              </div>

              {doctor.currentPatientName && (
                <p className="mt-1.5 text-xs text-text-secondary">
                  With <span className="font-medium text-text-primary">{doctor.currentPatientName}</span>
                </p>
              )}

              <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
                <span className="text-text-secondary">{doctor.patientsSeenToday} seen today</span>
                {doctor.status === 'available' && idle > 0 && (
                  <span className="queue-mono text-status-success-fg">Idle {formatDuration(idle)}</span>
                )}
                {lag >= 15 && (
                  <span className="queue-mono rounded bg-status-warning-surface px-1.5 py-0.5 font-medium text-status-warning-fg">
                    +{lag} min behind
                  </span>
                )}
              </div>

              <div className="mt-2 h-1 overflow-hidden rounded-full bg-border-default">
                <div
                  className="h-full rounded-full transition-all"
                  style={{
                    width: `${Math.min(100, doctor.patientsSeenToday * 12)}%`,
                    backgroundColor: config.barColor,
                  }}
                  role="presentation"
                />
              </div>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
