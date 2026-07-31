import {
  doctorsForBranch,
  MOCK_BOOKINGS,
  SLOT_LABELS,
  SLOT_TIMES,
} from './mock-data'
import type { SlotStatus, TimeSlot } from './types'

const CLOSED_WEEKDAYS = new Set([0]) // Sunday

function isWorkingDay(dateIso: string): boolean {
  const d = new Date(`${dateIso}T12:00:00`)
  return !CLOSED_WEEKDAYS.has(d.getDay())
}

function bookedDoctorIds(branchId: string, date: string, time: string): Set<string> {
  const ids = new Set<string>()
  for (const booking of MOCK_BOOKINGS) {
    if (booking.branchId === branchId && booking.date === date && booking.time === time) {
      ids.add(booking.doctorId)
    }
  }
  return ids
}

function resolveSlotStatus(
  availableDoctorIds: string[],
  preferredDoctorId: string | null,
): SlotStatus {
  if (availableDoctorIds.length === 0) return 'locked'
  if (!preferredDoctorId) return 'available'
  if (availableDoctorIds.includes(preferredDoctorId)) return 'preferred'
  return 'alternate'
}

export function getSlotsForDay(
  branchId: string,
  date: string,
  preferredDoctorId: string | null,
): TimeSlot[] {
  if (!isWorkingDay(date)) {
    return SLOT_TIMES.map((time) => ({
      time,
      label: SLOT_LABELS[time],
      status: 'locked' as const,
      availableDoctorIds: [],
    }))
  }

  const branchDoctors = doctorsForBranch(branchId)

  return SLOT_TIMES.map((time) => {
    const booked = bookedDoctorIds(branchId, date, time)
    const availableDoctorIds = branchDoctors
      .filter((d) => !booked.has(d.id))
      .map((d) => d.id)

    return {
      time,
      label: SLOT_LABELS[time],
      status: resolveSlotStatus(availableDoctorIds, preferredDoctorId),
      availableDoctorIds,
    }
  })
}

export function resolveAssignedDoctor(
  slot: TimeSlot,
  preferredDoctorId: string | null,
): string | null {
  if (slot.status === 'locked' || slot.availableDoctorIds.length === 0) return null
  if (preferredDoctorId && slot.availableDoctorIds.includes(preferredDoctorId)) {
    return preferredDoctorId
  }
  return slot.availableDoctorIds[0] ?? null
}

export function addDaysIso(baseIso: string, delta: number): string {
  const d = new Date(`${baseIso}T12:00:00`)
  d.setDate(d.getDate() + delta)
  return d.toISOString().slice(0, 10)
}

export function formatDayChip(dateIso: string): { weekday: string; day: number; month: string } {
  const d = new Date(`${dateIso}T12:00:00`)
  return {
    weekday: d.toLocaleDateString('en-US', { weekday: 'short' }),
    day: d.getDate(),
    month: d.toLocaleDateString('en-US', { month: 'short' }),
  }
}

export function formatFullDate(dateIso: string): string {
  const d = new Date(`${dateIso}T12:00:00`)
  return d.toLocaleDateString('en-GB', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  })
}
