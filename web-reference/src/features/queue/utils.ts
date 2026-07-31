import type {
  Appointment,
  AppointmentStatus,
  CheckedInSortMode,
  Doctor,
  KpiTrend,
  QueueKpiFilter,
  QueueStats,
} from './types'

export function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  })
}

export function formatDuration(minutes: number): string {
  if (minutes < 1) return '<1m'
  if (minutes < 60) return `${Math.round(minutes)}m`
  const h = Math.floor(minutes / 60)
  const m = Math.round(minutes % 60)
  return m > 0 ? `${h}h ${m}m` : `${h}h`
}

export function getWaitMinutes(appointment: Appointment, now = Date.now()): number {
  const start = appointment.checkedInAt ?? appointment.arrivedAt
  if (!start) return 0
  if (appointment.consultationStartedAt) {
    return (new Date(appointment.consultationStartedAt).getTime() - new Date(start).getTime()) / 60_000
  }
  return (now - new Date(start).getTime()) / 60_000
}

export function isOverdue(appointment: Appointment, now = Date.now()): boolean {
  if (['completed', 'cancelled', 'no_show', 'in_progress'].includes(appointment.status)) {
    return false
  }
  return new Date(appointment.scheduledTime).getTime() < now
}

export function isEarlyArrival(appointment: Appointment): boolean {
  if (!appointment.arrivedAt) return false
  const scheduled = new Date(appointment.scheduledTime).getTime()
  const arrived = new Date(appointment.arrivedAt).getTime()
  return arrived < scheduled - 10 * 60_000
}

export function computeQueueStats(appointments: Appointment[], now = Date.now()): QueueStats {
  const active = appointments.filter((a) => !['cancelled'].includes(a.status))
  const waiting = appointments.filter((a) => a.status === 'arrived').length
  const checkedIn = appointments.filter((a) => a.status === 'checked_in').length
  const inProgress = appointments.filter((a) => a.status === 'in_progress').length
  const completed = appointments.filter((a) => a.status === 'completed').length
  const cancelled = appointments.filter((a) => a.status === 'cancelled').length
  const noShow = appointments.filter((a) => a.status === 'no_show').length

  const completedWithWait = appointments.filter(
    (a) => a.status === 'completed' && a.checkedInAt && a.consultationStartedAt,
  )
  const avgWaitMinutes =
    completedWithWait.length > 0
      ? completedWithWait.reduce((sum, a) => sum + getWaitMinutes(a), 0) / completedWithWait.length
      : 0

  const inConsultation = appointments.filter(
    (a) => a.status === 'completed' && a.consultationStartedAt,
  )
  const avgConsultationMinutes =
    inConsultation.length > 0
      ? inConsultation.reduce((sum, a) => {
          const start = new Date(a.consultationStartedAt!).getTime()
          const end = start + 20 * 60_000
          return sum + (end - start) / 60_000
        }, 0) / inConsultation.length
      : 22

  const checkedInWaiting = appointments.filter((a) => a.status === 'checked_in')
  const longestWaitMinutes =
    checkedInWaiting.length > 0
      ? Math.max(...checkedInWaiting.map((a) => getWaitMinutes(a, now)))
      : 0

  return {
    total: active.length,
    waiting,
    checkedIn,
    inProgress,
    completed,
    cancelled,
    noShow,
    avgWaitMinutes: Math.round(avgWaitMinutes),
    avgConsultationMinutes: Math.round(avgConsultationMinutes),
    currentQueueLength: waiting + checkedIn,
    longestWaitMinutes: Math.round(longestWaitMinutes),
  }
}

export function getMinutesOverdue(appointment: Appointment, now = Date.now()): number {
  if (!isOverdue(appointment, now)) return 0
  return (now - new Date(appointment.scheduledTime).getTime()) / 60_000
}

export function getDoctorLagMinutes(doctor: Doctor, appointments: Appointment[], now = Date.now()): number {
  if (doctor.status === 'with_patient') {
    const current = appointments.find((a) => a.id === doctor.currentPatientId)
    if (current?.consultationStartedAt) {
      const elapsed = (now - new Date(current.consultationStartedAt).getTime()) / 60_000
      return Math.max(0, Math.round(elapsed - 20))
    }
    return 0
  }
  const pending = appointments.filter(
    (a) =>
      a.status === 'checked_in' &&
      (a.preferredDoctorId === doctor.id || a.assignedDoctorId === doctor.id),
  )
  if (pending.length > 2) return 15 + pending.length * 5
  return 0
}

export function buildAlertSummary(
  appointments: Appointment[],
  doctors: Doctor[],
  now = Date.now(),
): string | null {
  const longWaits = appointments.filter(
    (a) => a.status === 'checked_in' && getWaitMinutes(a, now) > 20,
  )
  const overdue = appointments.filter((a) => isOverdue(a, now) && a.status === 'scheduled')
  const laggingDoctors = doctors
    .map((d) => ({ doctor: d, lag: getDoctorLagMinutes(d, appointments, now) }))
    .filter((x) => x.lag >= 15)
    .sort((a, b) => b.lag - a.lag)

  const parts: string[] = []
  if (longWaits.length > 0) {
    parts.push(`${longWaits.length} long wait${longWaits.length > 1 ? 's' : ''}`)
  }
  if (overdue.length > 0) {
    parts.push(`${overdue.length} overdue`)
  }
  if (laggingDoctors.length > 0) {
    const top = laggingDoctors[0]
    parts.push(`${top.doctor.name.split(' ').slice(-1)[0]} +${top.lag} min behind`)
  }
  return parts.length > 0 ? parts.join(' · ') : null
}

export function sortAppointmentsForTriage(appointments: Appointment[], now = Date.now()): Appointment[] {
  return [...appointments].sort((a, b) => {
    const aOverdue = isOverdue(a, now) && a.status === 'scheduled' ? 1 : 0
    const bOverdue = isOverdue(b, now) && b.status === 'scheduled' ? 1 : 0
    if (aOverdue !== bOverdue) return bOverdue - aOverdue
    if (aOverdue && bOverdue) {
      return getMinutesOverdue(b, now) - getMinutesOverdue(a, now)
    }
    const statusOrder: Record<AppointmentStatus, number> = {
      arrived: 0,
      checked_in: 1,
      in_progress: 2,
      scheduled: 3,
      completed: 4,
      cancelled: 5,
      no_show: 6,
    }
    const orderDiff = statusOrder[a.status] - statusOrder[b.status]
    if (orderDiff !== 0) return orderDiff
    return new Date(a.scheduledTime).getTime() - new Date(b.scheduledTime).getTime()
  })
}

export function filterByKpi(appointments: Appointment[], filter: QueueKpiFilter): Appointment[] {
  switch (filter) {
    case 'waiting':
      return appointments.filter((a) => a.status === 'arrived')
    case 'checked_in':
      return appointments.filter((a) => a.status === 'checked_in')
    case 'in_progress':
      return appointments.filter((a) => a.status === 'in_progress')
    case 'completed':
      return appointments.filter((a) => a.status === 'completed')
    case 'cancelled':
      return appointments.filter((a) => a.status === 'cancelled')
    case 'no_show':
      return appointments.filter((a) => a.status === 'no_show')
    default:
      return appointments
  }
}

export function filterByStatusChip(
  appointments: Appointment[],
  statuses: Set<AppointmentStatus>,
): Appointment[] {
  if (statuses.size === 0) return appointments
  return appointments.filter((a) => statuses.has(a.status))
}

export function sortCheckedInPatients(
  appointments: Appointment[],
  sort: CheckedInSortMode,
  now = Date.now(),
): Appointment[] {
  const checkedIn = appointments.filter((a) => a.status === 'checked_in')
  if (sort === 'next_in_order') {
    return checkedIn.sort(
      (a, b) => new Date(a.scheduledTime).getTime() - new Date(b.scheduledTime).getTime(),
    )
  }
  return checkedIn.sort((a, b) => getWaitMinutes(b, now) - getWaitMinutes(a, now))
}

export function getCheckedInPatients(
  appointments: Appointment[],
  sort: CheckedInSortMode = 'longest_wait',
  now = Date.now(),
): Appointment[] {
  return sortCheckedInPatients(appointments, sort, now)
}

/** Mock day-over-day trends for KPI cards (replace with API data in production). */
export function getKpiTrends(): Record<string, KpiTrend> {
  const dayLabel = new Date(Date.now() - 86_400_000).toLocaleDateString('en-US', {
    weekday: 'short',
  })
  return {
    total: { label: '+3 vs yesterday', direction: 'up', favorableUp: true },
    waiting: { label: '+2 vs yesterday', direction: 'up', favorableUp: false },
    checked_in: { label: '−1 vs yesterday', direction: 'down', favorableUp: true },
    in_progress: { label: 'same as yesterday', direction: 'flat', favorableUp: true },
    completed: { label: '+4 vs yesterday', direction: 'up', favorableUp: true },
    queue_length: { label: '+1 vs yesterday', direction: 'up', favorableUp: false },
    avg_wait: { label: '−3m vs yesterday', direction: 'down', favorableUp: true },
    avg_consult: { label: '+2m vs yesterday', direction: 'up', favorableUp: false },
    cancelled: { label: `−1 vs ${dayLabel}`, direction: 'down', favorableUp: true },
    no_show: { label: 'same as yesterday', direction: 'flat', favorableUp: true },
  }
}

export function getQueueHealthIssues(
  appointments: Appointment[],
  doctors: Doctor[],
  now = Date.now(),
): string[] {
  const issues: string[] = []
  const longWaits = appointments.filter(
    (a) => a.status === 'checked_in' && getWaitMinutes(a, now) > 30,
  )
  if (longWaits.length > 0) {
    issues.push(
      `${longWaits.length} patient${longWaits.length > 1 ? 's' : ''} waiting over 30 minutes`,
    )
  }
  const overdue = appointments.filter((a) => isOverdue(a, now) && a.status === 'scheduled')
  if (overdue.length > 0) {
    issues.push(`${overdue.length} overdue appointment${overdue.length > 1 ? 's' : ''} not yet arrived`)
  }
  const availableDoctors = doctors.filter((d) => d.status === 'available').length
  const queueLength = appointments.filter((a) => a.status === 'checked_in').length
  if (queueLength > 0 && availableDoctors === 0) {
    issues.push('No doctors currently available — queue backing up')
  }
  return issues
}

export function getIdleMinutes(doctor: Doctor, now = Date.now()): number {
  if (!doctor.idleSince) return 0
  return (now - new Date(doctor.idleSince).getTime()) / 60_000
}

export function getArrivingSoon(appointments: Appointment[], now = Date.now(), windowMinutes = 60): Appointment[] {
  const windowEnd = now + windowMinutes * 60_000
  return appointments
    .filter(
      (a) =>
        a.status === 'scheduled' &&
        new Date(a.scheduledTime).getTime() >= now &&
        new Date(a.scheduledTime).getTime() <= windowEnd,
    )
    .sort((a, b) => new Date(a.scheduledTime).getTime() - new Date(b.scheduledTime).getTime())
}

export function getMinutesUntilAppointment(appointment: Appointment, now = Date.now()): number {
  return Math.max(0, (new Date(appointment.scheduledTime).getTime() - now) / 60_000)
}

export function todayFormatted(): string {
  return new Date().toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  })
}
