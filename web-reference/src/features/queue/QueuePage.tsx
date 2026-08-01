import { useCallback, useEffect, useMemo, useState } from 'react'
import type { Appointment, AppointmentStatus, Doctor } from './types'
import { INITIAL_APPOINTMENTS, INITIAL_DOCTORS } from './mock-data'
import {
  computeQueueStats,
  filterByStatusChip,
  getCheckedInPatients,
  sortAppointmentsForTriage,
} from './utils'
import { QueueStats } from './components/QueueStats'
import { QueueToolbar } from './components/QueueToolbar'
import { AppointmentsTable } from './components/AppointmentsTable'
import { FlowControlPanel } from './components/FlowControlPanel'
import { ConfirmDialog } from './components/ConfirmDialog'
import { UndoToast } from './components/UndoToast'
import './queue.css'

type PendingConfirm = {
  appointmentId: string
  target: AppointmentStatus
  patientName: string
}

type UndoState = {
  appointments: Appointment[]
  doctors: Doctor[]
  message: string
}

export function QueuePage() {
  const [appointments, setAppointments] = useState<Appointment[]>(INITIAL_APPOINTMENTS)
  const [doctors, setDoctors] = useState<Doctor[]>(INITIAL_DOCTORS)
  const [now, setNow] = useState(Date.now())
  const [search, setSearch] = useState('')
  const [statusFilters, setStatusFilters] = useState<Set<AppointmentStatus>>(new Set())
  const [pendingConfirm, setPendingConfirm] = useState<PendingConfirm | null>(null)
  const [undo, setUndo] = useState<UndoState | null>(null)

  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), 30_000)
    return () => clearInterval(interval)
  }, [])

  useEffect(() => {
    if (!undo) return
    const timer = setTimeout(() => setUndo(null), 5000)
    return () => clearTimeout(timer)
  }, [undo])

  const stats = useMemo(() => computeQueueStats(appointments, now), [appointments, now])

  const filteredAppointments = useMemo(() => {
    let result = filterByStatusChip(appointments, statusFilters)
    if (search.trim()) {
      const q = search.toLowerCase()
      result = result.filter((a) => a.patientName.toLowerCase().includes(q))
    }
    return sortAppointmentsForTriage(result, now)
  }, [appointments, statusFilters, search, now])

  const checkedInPatients = useMemo(() => getCheckedInPatients(appointments), [appointments])

  const applyTransition = useCallback(
    (appointmentId: string, target: AppointmentStatus, doctorId?: string) => {
      setAppointments((prev) => {
        setUndo({ appointments: prev, doctors, message: 'Status updated' })
        const timestamp = new Date().toISOString()
        return prev.map((apt) => {
          if (apt.id !== appointmentId) return apt
          const updated: Appointment = { ...apt, status: target }
          if (target === 'arrived') updated.arrivedAt = timestamp
          if (target === 'checked_in') {
            updated.checkedInAt = timestamp
            if (!updated.arrivedAt) updated.arrivedAt = timestamp
          }
          if (target === 'in_progress') {
            updated.consultationStartedAt = timestamp
            if (doctorId) {
              const doc = doctors.find((d) => d.id === doctorId)
              updated.assignedDoctorId = doctorId
              updated.assignedDoctorName = doc?.name ?? null
            }
          }
          return updated
        })
      })

      if (target === 'in_progress' && doctorId) {
        const apt = appointments.find((a) => a.id === appointmentId)
        setDoctors((prev) =>
          prev.map((d) =>
            d.id === doctorId
              ? {
                  ...d,
                  status: 'with_patient' as const,
                  currentPatientId: appointmentId,
                  currentPatientName: apt?.patientName ?? null,
                  idleSince: null,
                }
              : d,
          ),
        )
      }
    },
    [appointments, doctors],
  )

  const handleTransition = useCallback(
    (appointmentId: string, target: AppointmentStatus, doctorId?: string) => {
      const apt = appointments.find((a) => a.id === appointmentId)
      if (!apt) return

      if (target === 'cancelled' || target === 'no_show') {
        setPendingConfirm({ appointmentId, target, patientName: apt.patientName })
        return
      }
      applyTransition(appointmentId, target, doctorId)
    },
    [appointments, applyTransition],
  )

  const handleConfirm = () => {
    if (!pendingConfirm) return
    applyTransition(pendingConfirm.appointmentId, pendingConfirm.target)
    setPendingConfirm(null)
  }

  const handleUndo = () => {
    if (!undo) return
    setAppointments(undo.appointments)
    setDoctors(undo.doctors)
    setUndo(null)
  }

  const toggleStatusFilter = (status: AppointmentStatus) => {
    setStatusFilters((prev) => {
      const next = new Set(prev)
      if (next.has(status)) next.delete(status)
      else next.add(status)
      return next
    })
  }

  return (
    <div className="queue-page min-h-full">
      <div className="space-y-5">
        <header>
          <h1 className="queue-heading text-2xl font-bold tracking-tight text-text-primary">Queue</h1>
          <p className="mt-1 text-sm text-text-secondary">
            Today&apos;s patient flow — scan exceptions, move patients forward
          </p>
        </header>

        <QueueStats stats={stats} />

        <QueueToolbar
          search={search}
          onSearchChange={setSearch}
          statusFilters={statusFilters}
          onToggleStatus={toggleStatusFilter}
          onClearFilters={() => setStatusFilters(new Set())}
        />

        <div className="grid items-start gap-5 lg:grid-cols-[1fr_340px] xl:grid-cols-[1fr_380px]">
          <div>
            <div className="mb-3 flex items-center justify-between">
              <h2 className="queue-heading text-sm font-semibold text-text-primary">
                Today&apos;s appointments
              </h2>
              <span className="text-xs text-text-secondary">{filteredAppointments.length} shown</span>
            </div>
            <AppointmentsTable
              appointments={filteredAppointments}
              doctors={doctors}
              now={now}
              onTransition={handleTransition}
            />
          </div>

          <FlowControlPanel
            patients={checkedInPatients}
            doctors={doctors}
            appointments={appointments}
            now={now}
          />
        </div>
      </div>

      <ConfirmDialog
        open={pendingConfirm !== null}
        title={pendingConfirm?.target === 'no_show' ? 'Mark as no show?' : 'Cancel appointment?'}
        message={
          pendingConfirm
            ? `${pendingConfirm.patientName} — this action requires confirmation.`
            : ''
        }
        confirmLabel={pendingConfirm?.target === 'no_show' ? 'Mark no show' : 'Cancel appointment'}
        onConfirm={handleConfirm}
        onCancel={() => setPendingConfirm(null)}
        danger
      />

      <UndoToast message={undo?.message ?? null} onUndo={handleUndo} />
    </div>
  )
}
