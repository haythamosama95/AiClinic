import { WEEKDAYS } from './constants'
import type { WorkingDayHours, WorkingSchedule, Weekday } from './types'

export function defaultWorkingSchedule(): WorkingSchedule {
  return {
    days: WEEKDAYS.map(({ id }) => ({
      day: id,
      isWorkingDay: id !== 'sunday',
      openTime: id === 'sunday' ? null : '09:00',
      closeTime: id === 'sunday' ? null : '17:00',
    })),
  }
}

export function emptyWorkingSchedule(): WorkingSchedule {
  return {
    days: WEEKDAYS.map(({ id }) => ({
      day: id,
      isWorkingDay: false,
      openTime: null,
      closeTime: null,
    })),
  }
}

export function hasConfiguredWorkingHours(schedule: WorkingSchedule): boolean {
  return schedule.days.some(isValidWorkingDay)
}

export function isValidWorkingDay(hours: WorkingDayHours): boolean {
  if (!hours.isWorkingDay) return false
  const open = parseHmTime(hours.openTime)
  const close = parseHmTime(hours.closeTime)
  if (open === null || close === null) return false
  return open < close
}

function parseHmTime(input: string | null): number | null {
  if (!input?.trim()) return null
  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(input.trim())
  if (!match) return null
  return Number(match[1]) * 60 + Number(match[2])
}

export function weekdayLabel(day: Weekday): string {
  return WEEKDAYS.find((d) => d.id === day)?.label ?? day
}

export function formatWorkingHoursSummary(schedule: WorkingSchedule): string {
  const openDays = schedule.days.filter((d) => d.isWorkingDay && d.openTime && d.closeTime)
  if (openDays.length === 0) return 'Not configured'
  if (openDays.length === 1) {
    const d = openDays[0]
    return `${weekdayLabel(d.day)} ${d.openTime}–${d.closeTime}`
  }
  const first = openDays[0]
  const sameHours = openDays.every(
    (d) => d.openTime === first.openTime && d.closeTime === first.closeTime,
  )
  if (sameHours) {
    return `${openDays.length} days · ${first.openTime}–${first.closeTime}`
  }
  return `${openDays.length} days configured`
}
