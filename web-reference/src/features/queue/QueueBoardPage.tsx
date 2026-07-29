import { Footprints, LayoutList, RefreshCw } from 'lucide-react'
import { useCallback, useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { formatFullDate } from '@/features/appointments/slot-availability'
import { DeskDoctorStrip } from '@/features/queue/desk/DeskDoctorStrip'
import { DeskScheduleRow } from '@/features/queue/desk/DeskScheduleRow'
import { DeskWaitingRow } from '@/features/queue/desk/DeskWaitingRow'
import { splitAppointments } from '@/features/queue/desk/desk-helpers'
import {
  computeQueueStats,
  DOCTORS_ON_SHIFT,
  INITIAL_APPOINTMENTS,
  QUEUE_BRANCH,
  QUEUE_SHIFT_LABEL,
  QUEUE_TODAY,
} from '@/features/queue/mock-data'
import type { QueueAppointment, QueueAppointmentStatus } from '@/features/queue/types'

const DEMO_TIME_LABEL = '10:15 AM'

export type QueueBoardPageProps = {
  onNavigate?: (route: string) => void
}

function createWalkInAppointment(): QueueAppointment {
  return {
    id: `q-walk-${Date.now()}`,
    patientId: 'p-walk',
    patientName: 'Walk-in patient',
    patientMrn: 'MRN-WALK',
    time: '10:15',
    timeLabel: DEMO_TIME_LABEL,
    preferredDoctorId: null,
    preferredDoctorName: null,
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'checked_in',
    visitType: 'walk_in',
    checkedInAt: '2026-07-13T10:15:00',
    notes: 'New walk-in',
    isUrgent: false,
  }
}

export function QueueBoardPage({ onNavigate }: QueueBoardPageProps) {
  const [appointments, setAppointments] = useState<QueueAppointment[]>(INITIAL_APPOINTMENTS)

  const stats = useMemo(() => computeQueueStats(appointments), [appointments])
  const { schedule, waiting, maxWait } = useMemo(
    () => splitAppointments(appointments),
    [appointments],
  )

  const handleStatusChange = useCallback((appointmentId: string, status: QueueAppointmentStatus) => {
    setAppointments((prev) =>
      prev.map((appointment) => {
        if (appointment.id !== appointmentId) return appointment
        const updated: QueueAppointment = { ...appointment, status }
        if (status === 'checked_in' && !appointment.checkedInAt) {
          updated.checkedInAt = '2026-07-13T10:15:00'
        }
        return updated
      }),
    )
  }, [])

  const handleRefresh = useCallback(() => {
    setAppointments(INITIAL_APPOINTMENTS)
  }, [])

  const handleAddWalkIn = useCallback(() => {
    setAppointments((prev) => [...prev, createWalkInAppointment()])
  }, [])

  return (
    <div className="mx-auto flex w-full max-w-7xl flex-col gap-5">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-h1 text-text-primary">Queue</h1>
          <p className="mt-1 text-body-sm text-text-secondary">
            {formatFullDate(QUEUE_TODAY)} · {QUEUE_BRANCH} · {QUEUE_SHIFT_LABEL}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            leadingIcon={<LayoutList size={15} />}
            onClick={() => onNavigate?.('queue')}
          >
            Dashboard view
          </Button>
          <Button
            variant="secondary"
            size="sm"
            leadingIcon={<RefreshCw size={14} />}
            onClick={handleRefresh}
          >
            Reset
          </Button>
          <Button
            variant="primary"
            size="sm"
            leadingIcon={<Footprints size={14} />}
            onClick={handleAddWalkIn}
          >
            Add walk-in
          </Button>
        </div>
      </header>

      <div className="flex flex-wrap items-center gap-x-6 gap-y-2 rounded-lg border border-border-subtle bg-surface-default px-4 py-3 text-body-sm">
        <span className="inline-flex items-center gap-2 text-text-secondary">
          <span className="relative flex size-2" aria-hidden>
            <span className="absolute inline-flex size-full animate-ping rounded-full bg-status-success-fg opacity-40" />
            <span className="relative inline-flex size-2 rounded-full bg-status-success-fg" />
          </span>
          <span className="font-mono tabular-nums text-text-primary">{DEMO_TIME_LABEL}</span>
        </span>
        <span className="hidden h-4 w-px bg-border-subtle sm:block" aria-hidden />
        <span className="text-text-secondary">
          <span className="font-mono tabular-nums text-text-primary">{stats.waiting}</span> waiting
        </span>
        <span className="text-text-secondary">
          <span className="font-mono tabular-nums text-text-primary">{stats.inConsultation}</span> in
          rooms
        </span>
        <span className="text-text-secondary">
          <span className="font-mono tabular-nums text-text-primary">{stats.scheduled}</span> yet to
          arrive
        </span>
      </div>

      <DeskDoctorStrip doctors={DOCTORS_ON_SHIFT} appointments={appointments} />

      <div className="grid gap-5 lg:grid-cols-2">
        <section className="overflow-hidden rounded-xl border border-border-subtle bg-surface-default">
          <div className="border-b border-border-subtle px-4 py-3">
            <h2 className="text-body-strong text-text-primary">Today&apos;s run</h2>
            <p className="text-caption text-text-tertiary">Active appointments by time</p>
          </div>

          {schedule.length === 0 ? (
            <EmptyState
              variant="no-results"
              title="No active appointments"
              description="Everyone has been seen or cleared for today."
              className="py-10"
            />
          ) : (
            <div role="list">
              {schedule.map((appointment) => (
                <DeskScheduleRow
                  key={appointment.id}
                  appointment={appointment}
                  isNow={appointment.time === '10:00' || appointment.status === 'in_consultation'}
                  onStatusChange={handleStatusChange}
                />
              ))}
            </div>
          )}
        </section>

        <section className="overflow-hidden rounded-xl border border-border-subtle bg-surface-default">
          <div className="border-b border-border-subtle px-4 py-3">
            <h2 className="text-body-strong text-text-primary">In the building</h2>
            <p className="text-caption text-text-tertiary">
              Checked in, sorted by longest wait
            </p>
          </div>

          {waiting.length === 0 ? (
            <EmptyState
              variant="no-results"
              title="No one waiting"
              description="Patients show up here after check-in."
              className="py-10"
            />
          ) : (
            <div role="list">
              {waiting.map(({ appointment, waitMinutes }) => (
                <DeskWaitingRow
                  key={appointment.id}
                  appointment={appointment}
                  waitMinutes={waitMinutes}
                  maxWait={maxWait}
                  onStatusChange={handleStatusChange}
                />
              ))}
            </div>
          )}
        </section>
      </div>
    </div>
  )
}
