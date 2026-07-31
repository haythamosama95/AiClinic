import type { Appointment, AppointmentStatus, Doctor } from '../types'
import { APPOINTMENT_TYPE_LABELS } from '../types'
import {
  formatDuration,
  formatTime,
  getMinutesOverdue,
  getWaitMinutes,
  isOverdue,
} from '../utils'
import { StatusBadge } from './StatusBadge'
import { AppointmentRowActions } from './AppointmentRowActions'

type AppointmentsTableProps = {
  appointments: Appointment[]
  doctors: Doctor[]
  now: number
  onTransition: (appointmentId: string, target: AppointmentStatus, doctorId?: string) => void
}

export function AppointmentsTable({
  appointments,
  doctors,
  now,
  onTransition,
}: AppointmentsTableProps) {
  if (appointments.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-border-default bg-surface-default px-6 py-12 text-center">
        <p className="text-sm font-medium text-text-primary">No appointments match your filters</p>
        <p className="mt-1 text-sm text-text-secondary">Try adjusting search or status filters</p>
      </div>
    )
  }

  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-default">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[720px] text-left text-sm">
          <thead>
            <tr className="border-b border-border-default bg-surface-sunken">
              <th className="queue-heading px-4 py-3 text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Patient
              </th>
              <th className="queue-heading px-4 py-3 text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Time
              </th>
              <th className="queue-heading px-4 py-3 text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Status
              </th>
              <th className="queue-heading px-4 py-3 text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Preferred doctor
              </th>
              <th className="queue-heading px-4 py-3 text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Type
              </th>
              <th className="queue-heading px-4 py-3 text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Wait
              </th>
              <th className="queue-heading px-4 py-3 text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Actions
              </th>
            </tr>
          </thead>
          <tbody>
            {appointments.map((apt) => {
              const overdue = isOverdue(apt, now) && apt.status === 'scheduled'
              const waitMin = getWaitMinutes(apt, now)
              const showWait = ['arrived', 'checked_in', 'in_progress'].includes(apt.status)

              return (
                <tr
                  key={apt.id}
                  className={`border-b border-border-subtle transition-colors hover:bg-surface-hover/80 ${
                    overdue ? 'border-l-4 border-l-status-danger-fg bg-status-danger-surface/30' : ''
                  }`}
                >
                  <td className="px-4 py-3">
                    <div className="font-medium text-text-primary">{apt.patientName}</div>
                    <div className="queue-mono mt-0.5 text-xs text-text-secondary">{apt.mrn}</div>
                  </td>
                  <td className="queue-mono px-4 py-3 text-text-primary">
                    <div>{formatTime(apt.scheduledTime)}</div>
                    {overdue && (
                      <div className="text-xs font-medium text-status-danger-fg">
                        {Math.round(getMinutesOverdue(apt, now))}m overdue
                      </div>
                    )}
                    {apt.arrivedAt && (
                      <div className="text-xs text-text-secondary">Arr {formatTime(apt.arrivedAt)}</div>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={apt.status} />
                  </td>
                  <td className="px-4 py-3 text-text-secondary">
                    {apt.preferredDoctorName ?? '—'}
                  </td>
                  <td className="px-4 py-3 text-text-secondary">
                    {APPOINTMENT_TYPE_LABELS[apt.appointmentType]}
                  </td>
                  <td className="queue-mono px-4 py-3">
                    {showWait ? (
                      <span
                        className={
                          waitMin > 30
                            ? 'font-semibold text-status-danger-fg'
                            : waitMin > 20
                              ? 'font-medium text-status-warning-fg'
                              : 'text-text-primary'
                        }
                      >
                        {formatDuration(waitMin)}
                      </span>
                    ) : (
                      <span className="text-text-placeholder">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <AppointmentRowActions
                      appointment={apt}
                      doctors={doctors}
                      onTransition={onTransition}
                    />
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
