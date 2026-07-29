import type { QueueAppointment } from '@/features/queue/types'

export const DEMO_NOW = new Date('2026-07-13T10:15:00')

const ACTIVE_WAIT_STATUSES = new Set(['checked_in', 'waiting', 'ready'])

export function waitMinutesSince(checkedInAt: string | null, now = DEMO_NOW): number {
  if (!checkedInAt) return 0
  const checkedIn = new Date(checkedInAt)
  return Math.max(0, Math.floor((now.getTime() - checkedIn.getTime()) / 60000))
}

export function isOverdueWait(minutes: number): boolean {
  return minutes >= 20
}

export function waitBarPercent(minutes: number, maxMinutes = 30): number {
  return Math.min(100, Math.round((minutes / maxMinutes) * 100))
}

export function splitAppointments(appointments: QueueAppointment[]) {
  const schedule = appointments
    .filter((a) => !['completed', 'no_show', 'cancelled'].includes(a.status))
    .sort((a, b) => a.time.localeCompare(b.time))

  const waiting = appointments
    .filter((a) => a.checkedInAt && ACTIVE_WAIT_STATUSES.has(a.status))
    .map((a) => ({
      appointment: a,
      waitMinutes: waitMinutesSince(a.checkedInAt),
    }))
    .sort((a, b) => b.waitMinutes - a.waitMinutes)

  const maxWait = waiting.reduce((max, item) => Math.max(max, item.waitMinutes), 1)

  return { schedule, waiting, maxWait }
}

export function doctorQueueCount(
  appointments: QueueAppointment[],
  doctorId: string,
): number {
  return appointments.filter(
    (a) =>
      ACTIVE_WAIT_STATUSES.has(a.status) &&
      (a.preferredDoctorId === doctorId || a.assignedDoctorId === doctorId),
  ).length
}
