import type { BadgeProps } from '@/components/badge/Badge'
import type { QueueAppointmentStatus } from './types'

export const QUEUE_STATUS_LABELS: Record<QueueAppointmentStatus, string> = {
  scheduled: 'Scheduled',
  confirmed: 'Confirmed',
  checked_in: 'Checked in',
  waiting: 'Waiting',
  ready: 'Ready',
  in_consultation: 'In consultation',
  completed: 'Completed',
  no_show: 'No-show',
  cancelled: 'Cancelled',
}

export const QUEUE_STATUS_COLORS: Record<QueueAppointmentStatus, BadgeProps['color']> = {
  scheduled: 'neutral',
  confirmed: 'info',
  checked_in: 'info',
  waiting: 'warning',
  ready: 'warning',
  in_consultation: 'success',
  completed: 'success',
  no_show: 'danger',
  cancelled: 'danger',
}

/** Valid next statuses from each state — receptionist workflow */
export const STATUS_TRANSITIONS: Record<QueueAppointmentStatus, QueueAppointmentStatus[]> = {
  scheduled: ['confirmed', 'checked_in', 'cancelled', 'no_show'],
  confirmed: ['checked_in', 'cancelled', 'no_show'],
  checked_in: ['waiting', 'ready', 'cancelled'],
  waiting: ['ready', 'in_consultation', 'no_show'],
  ready: ['in_consultation', 'waiting', 'no_show'],
  in_consultation: ['completed', 'waiting'],
  completed: [],
  no_show: ['checked_in'],
  cancelled: ['scheduled'],
}

export function queueStatusLabel(status: QueueAppointmentStatus): string {
  return QUEUE_STATUS_LABELS[status]
}

export function queueStatusColor(status: QueueAppointmentStatus): BadgeProps['color'] {
  return QUEUE_STATUS_COLORS[status]
}

export function nextStatuses(status: QueueAppointmentStatus): QueueAppointmentStatus[] {
  return STATUS_TRANSITIONS[status]
}

export function formatWaitDuration(minutes: number): string {
  if (minutes < 1) return '< 1 min'
  if (minutes < 60) return `${minutes} min`
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return m > 0 ? `${h}h ${m}m` : `${h}h`
}
