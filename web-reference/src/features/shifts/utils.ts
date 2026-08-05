import type { CopyScheduleInput, RoleId, ShiftCoverageSummary, ShiftInstance, StaffMember } from './types'

export function parseTime(time: string): number {
  const [h, m] = time.split(':').map(Number)
  return h * 60 + m
}

export function formatTimeRange(start: string, end: string): string {
  return `${formatTime12(start)} – ${formatTime12(end)}`
}

export function formatTime12(time: string): string {
  const [hStr, mStr] = time.split(':')
  let h = Number(hStr)
  const m = mStr
  const period = h >= 12 ? 'PM' : 'AM'
  if (h > 12) h -= 12
  if (h === 0) h = 12
  return `${h}:${m} ${period}`
}

export function startOfWeek(date: Date): Date {
  const d = new Date(date)
  const day = d.getDay()
  d.setDate(d.getDate() - day)
  d.setHours(0, 0, 0, 0)
  return d
}

export function addDays(date: Date, days: number): Date {
  const d = new Date(date)
  d.setDate(d.getDate() + days)
  return d
}

export function toDateString(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

export function parseDate(str: string): Date {
  const [y, m, d] = str.split('-').map(Number)
  return new Date(y, m - 1, d)
}

export function getWeekDays(anchor: Date): Date[] {
  const start = startOfWeek(anchor)
  return Array.from({ length: 7 }, (_, i) => addDays(start, i))
}

export function getMonthDays(year: number, month: number): (Date | null)[] {
  const first = new Date(year, month, 1)
  const last = new Date(year, month + 1, 0)
  const days: (Date | null)[] = []
  for (let i = 0; i < first.getDay(); i++) days.push(null)
  for (let d = 1; d <= last.getDate(); d++) days.push(new Date(year, month, d))
  return days
}

export function datesInRange(
  start: string,
  end: string,
  weekdays?: number[],
  excludeDates?: string[],
): string[] {
  const excluded = new Set(excludeDates ?? [])
  const result: string[] = []
  const current = parseDate(start)
  const last = parseDate(end)
  while (current <= last) {
    const date = toDateString(current)
    if ((!weekdays || weekdays.includes(current.getDay())) && !excluded.has(date)) {
      result.push(date)
    }
    current.setDate(current.getDate() + 1)
  }
  return result
}

export function shiftFillRatio(shift: ShiftInstance): number {
  if (shift.headcount === 0) return 1
  return Math.min(shift.assignments.length / shift.headcount, 1)
}

export function isUnderstaffed(shift: ShiftInstance): boolean {
  return shift.assignments.length < shift.headcount
}

export function isShiftFull(shift: ShiftInstance): boolean {
  return shift.assignments.length >= shift.headcount
}

export function isOverstaffed(shift: ShiftInstance): boolean {
  return shift.assignments.length > shift.headcount
}

export function hasTimeOverlap(a: ShiftInstance, b: ShiftInstance): boolean {
  if (a.date !== b.date) return false
  const aStart = parseTime(a.startTime)
  let aEnd = parseTime(a.endTime)
  let bStart = parseTime(b.startTime)
  let bEnd = parseTime(b.endTime)
  if (aEnd <= aStart) aEnd += 24 * 60
  if (bEnd <= bStart) bEnd += 24 * 60
  return aStart < bEnd && bStart < aEnd
}

export function shiftsWouldConflict(existing: ShiftInstance, candidate: ShiftInstance): boolean {
  if (existing.roleId !== candidate.roleId) return false
  if (existing.date !== candidate.date) return false
  return hasTimeOverlap(existing, candidate)
}

export function findShiftPlacementConflicts(
  existingShifts: ShiftInstance[],
  plannedShifts: ShiftInstance[],
): ShiftInstance[] {
  const conflicting = new Map<string, ShiftInstance>()
  for (const planned of plannedShifts) {
    for (const existing of existingShifts) {
      if (shiftsWouldConflict(existing, planned)) {
        conflicting.set(existing.id, existing)
      }
    }
  }
  return [...conflicting.values()]
}

export function formatShiftConflictDates(conflicts: ShiftInstance[]): string {
  const dates = [...new Set(conflicts.map((shift) => shift.date))]
  const preview = dates.slice(0, 3).join(', ')
  return dates.length > 3 ? `${preview}…` : preview
}

export function staffHasConflict(
  staffId: string,
  targetShift: ShiftInstance,
  allShifts: ShiftInstance[],
): boolean {
  const staffShifts = allShifts.filter(
    (s) => s.id !== targetShift.id && s.assignments.includes(staffId),
  )
  return staffShifts.some((s) => hasTimeOverlap(s, targetShift))
}

export function computeCoverage(
  shifts: ShiftInstance[],
  staff: StaffMember[],
  roleId: RoleId,
  weekDays: Date[],
): ShiftCoverageSummary {
  const weekDates = new Set(weekDays.map(toDateString))
  const roleShifts = shifts.filter((s) => s.roleId === roleId && weekDates.has(s.date))
  const totalSlots = roleShifts.reduce((sum, s) => sum + s.headcount, 0)
  const filledSlots = roleShifts.reduce((sum, s) => sum + s.assignments.length, 0)
  const understaffedShifts = roleShifts.filter(isUnderstaffed).length
  const roleStaff = staff.filter((s) => s.roleId === roleId && s.status !== 'on-leave')
  const assignedIds = new Set(roleShifts.flatMap((s) => s.assignments))
  const unassignedStaff = roleStaff.filter((s) => !assignedIds.has(s.id)).length

  return { totalSlots, filledSlots, understaffedShifts, unassignedStaff }
}

export function getStaffShiftsForWeek(
  staffId: string,
  shifts: ShiftInstance[],
  weekDays: Date[],
): ShiftInstance[] {
  const weekDates = new Set(weekDays.map(toDateString))
  return shifts
    .filter((s) => s.assignments.includes(staffId) && weekDates.has(s.date))
    .sort((a, b) => a.date.localeCompare(b.date) || parseTime(a.startTime) - parseTime(b.startTime))
}

export function shiftDurationHours(startTime: string, endTime: string): number {
  let start = parseTime(startTime)
  let end = parseTime(endTime)
  if (end <= start) end += 24 * 60
  return (end - start) / 60
}

export const SHIFT_GRID_START_HOUR = 6
export const SHIFT_GRID_HOUR_COUNT = 14
export const SHIFT_HOUR_HEIGHT_PX = 52

export function getShiftBandLayout(
  startTime: string,
  endTime: string,
  options?: { gridStartHour?: number; hourHeightPx?: number; gridHourCount?: number },
): { top: number; height: number } | null {
  const gridStartHour = options?.gridStartHour ?? SHIFT_GRID_START_HOUR
  const hourHeightPx = options?.hourHeightPx ?? SHIFT_HOUR_HEIGHT_PX
  const gridHourCount = options?.gridHourCount ?? SHIFT_GRID_HOUR_COUNT
  const gridStart = gridStartHour * 60
  const gridEnd = gridStart + gridHourCount * 60

  let start = parseTime(startTime)
  let end = parseTime(endTime)
  if (end <= start) end += 24 * 60

  if (end <= gridStart || start >= gridEnd) return null

  const visibleStart = Math.max(start, gridStart)
  const visibleEnd = Math.min(end, gridEnd)
  const top = ((visibleStart - gridStart) / 60) * hourHeightPx
  const height = ((visibleEnd - visibleStart) / 60) * hourHeightPx

  return { top, height: Math.max(height, 4) }
}

export function getStaffWeeklyHours(
  staffId: string,
  shifts: ShiftInstance[],
  weekDays: Date[],
): number {
  const weekShifts = getStaffShiftsForWeek(staffId, shifts, weekDays)
  return weekShifts.reduce((sum, s) => sum + shiftDurationHours(s.startTime, s.endTime), 0)
}

export function deriveStaffStatus(
  member: StaffMember,
  weeklyHours: number,
): StaffMember['status'] {
  if (member.status === 'on-leave') return 'on-leave'
  if (weeklyHours === 0) return 'available'
  if (weeklyHours >= member.maxWeeklyHours * 0.85) return 'fully-assigned'
  return 'partially-assigned'
}

export function getDayOffset(source: string, target: string): number {
  const s = parseDate(source)
  const t = parseDate(target)
  return Math.round((t.getTime() - s.getTime()) / (24 * 60 * 60 * 1000))
}

export function toMonthValue(date: Date | string): string {
  const d = typeof date === 'string' ? parseDate(date) : date
  const month = String(d.getMonth() + 1).padStart(2, '0')
  return `${d.getFullYear()}-${month}`
}

export function monthValueToDate(monthValue: string): string {
  return `${monthValue}-01`
}

export function formatWeekRangeLabel(anchorDate: string): string {
  const days = getWeekDays(parseDate(anchorDate))
  const formatDay = (date: Date) =>
    date.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
  return `${formatDay(days[0])} – ${formatDay(days[6])}`
}

export function formatMonthLabel(monthValue: string): string {
  const [year, month] = monthValue.split('-').map(Number)
  return new Date(year, month - 1, 1).toLocaleDateString('en-US', {
    month: 'long',
    year: 'numeric',
  })
}

export function copyShifts(
  shifts: ShiftInstance[],
  input: CopyScheduleInput,
  shiftTypes: { id: string; roleId: RoleId; startTime: string; endTime: string; defaultHeadcount: number }[],
): ShiftInstance[] {
  const newShifts = planCopySchedule(shifts, input, shiftTypes)
  return [...shifts, ...newShifts]
}

export function planCopySchedule(
  shifts: ShiftInstance[],
  input: CopyScheduleInput,
  shiftTypes: { id: string; roleId: RoleId; startTime: string; endTime: string; defaultHeadcount: number }[],
): ShiftInstance[] {
  const { scope, sourceDate, targetDate, sourceRoleId, targetRoleId, includeAssignments } = input
  const srcRole = sourceRoleId
  const tgtRole = targetRoleId ?? sourceRoleId

  let sourceShifts = shifts
  if (srcRole) sourceShifts = sourceShifts.filter((s) => s.roleId === srcRole)

  const offset = getDayOffset(sourceDate, targetDate)
  const newShifts: ShiftInstance[] = []

  if (scope === 'day') {
    const dayShifts = sourceShifts.filter((s) => s.date === sourceDate)
    for (const shift of dayShifts) {
      const tgtDate = toDateString(addDays(parseDate(shift.date), offset))
      newShifts.push(cloneShift(shift, tgtDate, tgtRole!, shiftTypes, includeAssignments))
    }
  } else if (scope === 'week') {
    const srcWeek = getWeekDays(parseDate(sourceDate)).map(toDateString)
    const tgtWeek = getWeekDays(parseDate(targetDate)).map(toDateString)
    const dayMap = Object.fromEntries(srcWeek.map((d, i) => [d, tgtWeek[i]]))
    const weekShifts = sourceShifts.filter((s) => srcWeek.includes(s.date))
    for (const shift of weekShifts) {
      const tgtDate = dayMap[shift.date]
      if (tgtDate) newShifts.push(cloneShift(shift, tgtDate, tgtRole!, shiftTypes, includeAssignments))
    }
  } else if (scope === 'month') {
    const src = parseDate(sourceDate)
    const tgt = parseDate(targetDate)
    const srcMonth = src.getMonth()
    const srcYear = src.getFullYear()
    const monthShifts = sourceShifts.filter((s) => {
      const d = parseDate(s.date)
      return d.getMonth() === srcMonth && d.getFullYear() === srcYear
    })
    for (const shift of monthShifts) {
      const d = parseDate(shift.date)
      const tgtDate = toDateString(new Date(tgt.getFullYear(), tgt.getMonth(), d.getDate()))
      newShifts.push(cloneShift(shift, tgtDate, tgtRole!, shiftTypes, includeAssignments))
    }
  } else if (scope === 'role' && srcRole && tgtRole) {
    const dayShifts = sourceShifts.filter((s) => s.roleId === srcRole)
    for (const shift of dayShifts) {
      newShifts.push(cloneShift(shift, shift.date, tgtRole, shiftTypes, includeAssignments))
    }
  }

  return newShifts
}

function cloneShift(
  source: ShiftInstance,
  date: string,
  roleId: RoleId,
  shiftTypes: { id: string; roleId: RoleId; startTime: string; endTime: string; defaultHeadcount: number }[],
  includeAssignments: boolean,
): ShiftInstance {
  const matchingType = shiftTypes.find(
    (t) => t.roleId === roleId && t.startTime === source.startTime && t.endTime === source.endTime,
  )
  return {
    id: `sh-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    roleId,
    shiftTypeId: matchingType?.id ?? source.shiftTypeId,
    date,
    startTime: source.startTime,
    endTime: source.endTime,
    headcount: source.headcount,
    assignments: includeAssignments ? [...source.assignments] : [],
    notes: source.notes,
  }
}

export const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const

export const WEEKDAY_FULL = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
] as const
