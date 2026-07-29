import { Footprints, PanelRight, RefreshCw, SearchX } from 'lucide-react'
import { motion } from 'motion/react'
import { useCallback, useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Badge } from '@/components/badge'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { PageHeader } from '@/components/layout/PageHeader'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { Tabs } from '@/components/navigation/Tabs'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import { formatFullDate } from '@/features/appointments/slot-availability'
import {
  DoctorShiftCard,
  FlowRibbon,
  QueueAppointmentRow,
  QueueQuickActions,
  QueueStatsRow,
  WaitingPatientCard,
} from '@/features/queue/components'
import {
  computeQueueStats,
  deriveWaitingPatients,
  DOCTORS_ON_SHIFT,
  INITIAL_APPOINTMENTS,
  QUEUE_BRANCH,
  QUEUE_SHIFT_LABEL,
  QUEUE_TODAY,
} from '@/features/queue/mock-data'
import type { QueueAppointment, QueueAppointmentStatus } from '@/features/queue/types'

type AppointmentFilter = 'all' | 'waiting' | 'in_progress' | 'done'
type FloorTab = 'doctors' | 'waiting'

const DEMO_TIME_LABEL = '10:15 AM'

const FILTER_TABS: { id: AppointmentFilter; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'waiting', label: 'Waiting' },
  { id: 'in_progress', label: 'In progress' },
  { id: 'done', label: 'Done' },
]

function matchesFilter(appointment: QueueAppointment, filter: AppointmentFilter): boolean {
  switch (filter) {
    case 'waiting':
      return ['checked_in', 'waiting', 'ready'].includes(appointment.status)
    case 'in_progress':
      return appointment.status === 'in_consultation'
    case 'done':
      return ['completed', 'no_show', 'cancelled'].includes(appointment.status)
    default:
      return true
  }
}

function matchesSearch(appointment: QueueAppointment, query: string): boolean {
  if (!query.trim()) return true
  const q = query.trim().toLowerCase()
  return (
    appointment.patientName.toLowerCase().includes(q) ||
    appointment.patientMrn.toLowerCase().includes(q) ||
    (appointment.preferredDoctorName?.toLowerCase().includes(q) ?? false) ||
    (appointment.assignedDoctorName?.toLowerCase().includes(q) ?? false)
  )
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

export type QueuePageProps = {
  onNavigate?: (route: string) => void
}

export function QueuePage({ onNavigate }: QueuePageProps = {}) {
  const [appointments, setAppointments] = useState<QueueAppointment[]>(INITIAL_APPOINTMENTS)
  const [filter, setFilter] = useState<AppointmentFilter>('all')
  const [search, setSearch] = useState('')
  const [floorTab, setFloorTab] = useState<FloorTab>('doctors')

  const stats = useMemo(() => computeQueueStats(appointments), [appointments])
  const waitingPatients = useMemo(() => deriveWaitingPatients(appointments), [appointments])

  const filteredAppointments = useMemo(() => {
    return appointments
      .filter((a) => matchesFilter(a, filter))
      .filter((a) => matchesSearch(a, search))
      .sort((a, b) => a.time.localeCompare(b.time))
  }, [appointments, filter, search])

  const nextToCheckIn = useMemo(
    () =>
      appointments.find(
        (a) => ['scheduled', 'confirmed'].includes(a.status) && a.visitType === 'appointment',
      ),
    [appointments],
  )

  const handleStatusChange = useCallback(
    (appointmentId: string, status: QueueAppointmentStatus) => {
      setAppointments((prev) =>
        prev.map((a) => {
          if (a.id !== appointmentId) return a
          const updated: QueueAppointment = { ...a, status }
          if (status === 'checked_in' && !a.checkedInAt) {
            updated.checkedInAt = '2026-07-13T10:15:00'
          }
          return updated
        }),
      )
    },
    [],
  )

  const handleRefresh = useCallback(() => {
    setAppointments(INITIAL_APPOINTMENTS)
    setFilter('all')
    setSearch('')
  }, [])

  const handleAddWalkIn = useCallback(() => {
    setAppointments((prev) => [...prev, createWalkInAppointment()])
  }, [])

  const handleCheckInNext = useCallback(() => {
    if (!nextToCheckIn) return
    handleStatusChange(nextToCheckIn.id, 'checked_in')
  }, [nextToCheckIn, handleStatusChange])

  const handleNotify = useCallback((appointmentId: string) => {
    void appointmentId
    // Demo: notification toast would fire here
  }, [])

  const handleSendToRoom = useCallback(
    (appointmentId: string) => {
      handleStatusChange(appointmentId, 'ready')
    },
    [handleStatusChange],
  )

  const handleCallNext = useCallback(
    (doctorId: string) => {
      const waiting = appointments.find(
        (a) =>
          ['checked_in', 'waiting', 'ready'].includes(a.status) &&
          (a.preferredDoctorId === doctorId || a.preferredDoctorId === null),
      )
      if (!waiting) return
      setAppointments((prev) =>
        prev.map((a) =>
          a.id === waiting.id
            ? {
              ...a,
              status: 'in_consultation',
              assignedDoctorId: doctorId,
              assignedDoctorName:
                DOCTORS_ON_SHIFT.find((d) => d.id === doctorId)?.fullName ?? null,
            }
            : a,
        ),
      )
    },
    [appointments],
  )

  const pageDescription = `${formatFullDate(QUEUE_TODAY)} · ${QUEUE_BRANCH} · ${QUEUE_SHIFT_LABEL}`

  const floorTabItems = useMemo(
    () => [
      {
        id: 'doctors' as const,
        label: (
          <span className="inline-flex items-center gap-1.5">
            Doctors on shift
            <Badge color="neutral" variant="soft" size="sm">
              {DOCTORS_ON_SHIFT.length}
            </Badge>
          </span>
        ),
      },
      {
        id: 'waiting' as const,
        label: (
          <span className="inline-flex items-center gap-1.5">
            Waiting room
            <Badge
              color={waitingPatients.length > 0 ? 'warning' : 'neutral'}
              variant="soft"
              size="sm"
            >
              {waitingPatients.length}
            </Badge>
          </span>
        ),
      },
    ],
    [waitingPatients.length],
  )

  const floorDescription =
    floorTab === 'doctors'
      ? `${DOCTORS_ON_SHIFT.length} providers this shift`
      : waitingPatients.length > 0
        ? `${waitingPatients.length} patient${waitingPatients.length !== 1 ? 's' : ''} waiting`
        : 'No one waiting'

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22 }}
      className="space-y-6"
    >
      <PageHeader
        title="Queue"
        description={pageDescription}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              leadingIcon={<PanelRight size={15} />}
              onClick={() => onNavigate?.('queue/board')}
            >
              Desk view
            </Button>
            <Button
              variant="secondary"
              size="sm"
              leadingIcon={<RefreshCw size={14} />}
              onClick={handleRefresh}
            >
              Refresh mock
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
        }
      />

      <div
        className="flex items-center justify-between gap-4 rounded-xl border border-border-subtle bg-surface-default px-4 py-2.5 shadow-elevation-0"
        aria-label="Live clock"
      >
        <div className="flex items-center gap-3">
          <span className="relative flex size-2.5" aria-hidden>
            <span className="absolute inline-flex size-full animate-ping rounded-full bg-status-success-fg opacity-40" />
            <span className="relative inline-flex size-2.5 rounded-full bg-status-success-fg" />
          </span>
          <span className="text-caption font-medium uppercase tracking-wider text-status-success-fg">
            Live
          </span>
        </div>
        <p className="text-h2 tabular-nums text-text-primary">{DEMO_TIME_LABEL}</p>
        <p className="text-caption text-text-tertiary">Demo time · reception desk view</p>
      </div>

      <QueueStatsRow stats={stats} />
      <FlowRibbon appointments={appointments} />

      <div className="grid gap-6 lg:grid-cols-3">
        <section className="space-y-4 lg:col-span-2">
          <SectionHeader
            title="Today's appointments"
            description={`${appointments.length} on the board`}
          />

          <div className="space-y-3">
            <Tabs
              items={FILTER_TABS.map((tab) => ({
                id: tab.id,
                label: tab.label,
              }))}
              value={filter}
              onChange={(id) => setFilter(id as AppointmentFilter)}
              variant="segmented"
              aria-label="Appointment filters"
            />

            <SearchInput
              placeholder="Search patient, MRN, or doctor…"
              aria-label="Search appointments"
              value={search}
              onValueChange={setSearch}
              showShortcutHint={false}
            />
          </div>

          {filteredAppointments.length === 0 ? (
            <div className="rounded-2xl border border-border-subtle bg-surface-default px-6 py-14 text-center shadow-elevation-1">
              <SearchX size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
              <p className="mt-4 text-body-strong text-text-primary">No appointments match</p>
              <p className="mt-1 text-body-sm text-text-secondary">
                Try a different filter or search term.
              </p>
              {filter !== 'all' || search ? (
                <Button
                  className="mt-6"
                  variant="secondary"
                  onClick={() => {
                    setFilter('all')
                    setSearch('')
                  }}
                >
                  Clear filters
                </Button>
              ) : null}
            </div>
          ) : (
            <div className="overflow-hidden rounded-xl border border-border-subtle bg-surface-default shadow-elevation-0">
              <table className="w-full min-w-0 text-left" aria-label="Today's appointments">
                <thead className="border-b border-border-subtle bg-surface-muted/40">
                  <tr className="text-caption text-text-tertiary">
                    <th className="px-4 py-2.5 font-medium">Time</th>
                    <th className="px-4 py-2.5 font-medium">Patient</th>
                    <th className="px-4 py-2.5 font-medium">Type</th>
                    <th className="px-4 py-2.5 font-medium">Doctor</th>
                    <th className="px-4 py-2.5 font-medium">Status</th>
                    <th className="px-4 py-2.5 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredAppointments.map((appointment) => (
                    <QueueAppointmentRow
                      key={appointment.id}
                      appointment={appointment}
                      onStatusChange={handleStatusChange}
                      onNotify={handleNotify}
                    />
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <aside className="flex min-h-0 flex-col rounded-xl border border-border-subtle bg-surface-default shadow-elevation-0">
          <div className="space-y-3 border-b border-border-subtle p-4">
            <SectionHeader title="Floor" description={floorDescription} />
            <Tabs
              items={floorTabItems}
              value={floorTab}
              onChange={(id) => setFloorTab(id as FloorTab)}
              variant="segmented"
              aria-label="Floor view"
              className="w-full"
            />
          </div>

          <div
            role="tabpanel"
            aria-label={floorTab === 'doctors' ? 'Doctors on shift' : 'Waiting room'}
            className="min-h-[18rem] flex-1 space-y-2 overflow-y-auto p-4"
          >
            {floorTab === 'doctors' ? (
              DOCTORS_ON_SHIFT.map((doctor) => (
                <DoctorShiftCard
                  key={doctor.id}
                  doctor={doctor}
                  onCallNext={handleCallNext}
                />
              ))
            ) : waitingPatients.length === 0 ? (
              <EmptyState
                variant="no-results"
                title="Waiting room empty"
                description="Patients appear here after check-in."
                className="rounded-lg border border-dashed border-border-default"
              />
            ) : (
              waitingPatients.map((patient) => (
                <WaitingPatientCard
                  key={patient.id}
                  patient={patient}
                  onNotify={handleNotify}
                  onSendToRoom={handleSendToRoom}
                />
              ))
            )}
          </div>
        </aside>
      </div>

      <QueueQuickActions
        onAddWalkIn={handleAddWalkIn}
        onCheckInNext={handleCheckInNext}
        onBroadcast={() => undefined}
        onPrintQueueSlip={handleRefresh}
      />
    </motion.div>
  )
}
