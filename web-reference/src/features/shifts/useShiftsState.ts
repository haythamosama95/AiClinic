import { useCallback, useMemo, useState } from 'react'
import { useToast } from '@/components/toast/Toast'
import { SHIFT_TYPES, STAFF } from './mock-data'
import type {
  CalendarView,
  CopyScheduleInput,
  CreateShiftInput,
  DuplicateShiftInput,
  RoleId,
  ShiftInstance,
  StaffMember,
} from './types'
import {
  computeCoverage,
  copyShifts,
  deriveStaffStatus,
  findShiftPlacementConflicts,
  formatShiftConflictDates,
  getStaffWeeklyHours,
  getWeekDays,
  parseDate,
  planCopySchedule,
  staffHasConflict,
} from './utils'

let shiftIdCounter = 0

function nextShiftId(): string {
  shiftIdCounter += 1
  return `sh-${Date.now()}-${shiftIdCounter}`
}

export function useShiftsState() {
  const { toast } = useToast()
  const [shifts, setShifts] = useState<ShiftInstance[]>([])
  const [selectedRoleId, setSelectedRoleId] = useState<RoleId>('doctor')
  const [calendarView, setCalendarView] = useState<CalendarView>('week')
  const [anchorDate, setAnchorDate] = useState(() => new Date())
  const [selectedShiftId, setSelectedShiftId] = useState<string | null>(null)
  const [assignShiftId, setAssignShiftId] = useState<string | null>(null)
  const [createOpen, setCreateOpen] = useState(false)
  const [copyOpen, setCopyOpen] = useState(false)
  const [duplicateShiftId, setDuplicateShiftId] = useState<string | null>(null)
  const [rosterSearch, setRosterSearch] = useState('')

  const weekDays = useMemo(() => getWeekDays(anchorDate), [anchorDate])

  const roleShifts = useMemo(
    () => shifts.filter((s) => s.roleId === selectedRoleId),
    [shifts, selectedRoleId],
  )

  const coverage = useMemo(
    () => computeCoverage(shifts, STAFF, selectedRoleId, weekDays),
    [shifts, selectedRoleId, weekDays],
  )

  const selectedShift = useMemo(
    () => shifts.find((s) => s.id === selectedShiftId) ?? null,
    [shifts, selectedShiftId],
  )

  const assignShift = useMemo(
    () => shifts.find((s) => s.id === assignShiftId) ?? null,
    [shifts, assignShiftId],
  )

  const duplicateShift = useMemo(
    () => shifts.find((s) => s.id === duplicateShiftId) ?? null,
    [shifts, duplicateShiftId],
  )

  const roleStaff = useMemo((): StaffMember[] => {
    const q = rosterSearch.trim().toLowerCase()
    return STAFF.filter((s) => s.roleId === selectedRoleId)
      .map((member) => {
        const weeklyHours = Math.round(getStaffWeeklyHours(member.id, shifts, weekDays))
        return {
          ...member,
          weeklyHours,
          status: deriveStaffStatus(member, weeklyHours),
        }
      })
      .filter((s) => !q || s.name.toLowerCase().includes(q))
  }, [selectedRoleId, rosterSearch, shifts, weekDays])

  const createShift = useCallback(
    (input: CreateShiftInput) => {
      const newShifts: ShiftInstance[] = input.dates.map((date) => ({
        id: nextShiftId(),
        roleId: input.roleId,
        shiftTypeId: input.shiftTypeId,
        date,
        startTime: input.startTime,
        endTime: input.endTime,
        headcount: input.headcount,
        assignments: [],
        notes: input.notes,
      }))

      setShifts((prev) => [...prev, ...newShifts])

      if (input.dates.length > 0) {
        setAnchorDate(parseDate(input.dates[0]))
        setCalendarView('week')
      }

      toast({
        variant: 'success',
        message: `Created ${newShifts.length} shift${newShifts.length === 1 ? '' : 's'}`,
      })
    },
    [toast],
  )

  const copySchedule = useCallback(
    (input: CopyScheduleInput): boolean => {
      const planned = planCopySchedule(shifts, input, SHIFT_TYPES)
      if (planned.length === 0) {
        toast({ variant: 'info', message: 'No shifts to copy in the source period' })
        return false
      }

      const conflicts = findShiftPlacementConflicts(shifts, planned)
      if (conflicts.length > 0) {
        toast({
          variant: 'danger',
          message: `Copy cancelled: existing shifts would be overwritten on ${formatShiftConflictDates(conflicts)}`,
        })
        return false
      }

      setShifts(copyShifts(shifts, input, SHIFT_TYPES))
      toast({
        variant: 'success',
        message: `Copied ${planned.length} shift${planned.length === 1 ? '' : 's'} to the target period`,
      })
      return true
    },
    [shifts, toast],
  )

  const assignStaff = useCallback(
    (shiftId: string, staffId: string) => {
      const shift = shifts.find((s) => s.id === shiftId)
      if (!shift) return

      if (shift.assignments.includes(staffId)) {
        toast({ variant: 'info', message: 'Staff member is already assigned to this shift' })
        return
      }

      if (shift.assignments.length >= shift.headcount) {
        toast({
          variant: 'danger',
          message: `This shift is full (${shift.headcount} staff maximum)`,
        })
        return
      }

      if (staffHasConflict(staffId, shift, shifts)) {
        toast({ variant: 'danger', message: 'This person has a conflicting shift at that time' })
        return
      }

      setShifts((prev) =>
        prev.map((s) =>
          s.id === shiftId ? { ...s, assignments: [...s.assignments, staffId] } : s,
        ),
      )
      const staff = STAFF.find((s) => s.id === staffId)
      toast({
        variant: 'success',
        message: `${staff?.name ?? 'Staff'} assigned to shift`,
      })
    },
    [shifts, toast],
  )

  const unassignStaff = useCallback(
    (shiftId: string, staffId: string) => {
      setShifts((prev) =>
        prev.map((s) =>
          s.id === shiftId
            ? { ...s, assignments: s.assignments.filter((id) => id !== staffId) }
            : s,
        ),
      )
      toast({ variant: 'neutral', message: 'Staff removed from shift' })
    },
    [toast],
  )

  const deleteShift = useCallback(
    (shiftId: string) => {
      setShifts((prev) => prev.filter((s) => s.id !== shiftId))
      setSelectedShiftId(null)
      toast({ variant: 'neutral', message: 'Shift deleted' })
    },
    [toast],
  )

  const duplicateShiftToDates = useCallback(
    (input: DuplicateShiftInput): boolean => {
      const source = shifts.find((s) => s.id === input.sourceShiftId)
      if (!source) return false

      const targetDates = input.dates.filter((date) => date !== source.date)
      if (targetDates.length === 0) {
        toast({
          variant: 'danger',
          message: 'Select at least one date different from the source shift',
        })
        return false
      }

      const newShifts: ShiftInstance[] = targetDates.map((date) => ({
        id: nextShiftId(),
        roleId: source.roleId,
        shiftTypeId: source.shiftTypeId,
        date,
        startTime: source.startTime,
        endTime: source.endTime,
        headcount: source.headcount,
        assignments: [...source.assignments],
        notes: source.notes,
      }))

      const conflicts = findShiftPlacementConflicts(shifts, newShifts)
      if (conflicts.length > 0) {
        toast({
          variant: 'danger',
          message: `Duplicate cancelled: existing shifts would be overwritten on ${formatShiftConflictDates(conflicts)}`,
        })
        return false
      }

      setShifts((prev) => [...prev, ...newShifts])
      setAnchorDate(parseDate(targetDates[0]))
      setCalendarView('week')
      setDuplicateShiftId(null)
      toast({
        variant: 'success',
        message: `Duplicated shift to ${newShifts.length} date${newShifts.length === 1 ? '' : 's'}`,
      })
      return true
    },
    [shifts, toast],
  )

  const updateShiftHeadcount = useCallback((shiftId: string, headcount: number) => {
    setShifts((prev) =>
      prev.map((s) => (s.id === shiftId ? { ...s, headcount } : s)),
    )
  }, [])

  const navigateCalendar = useCallback(
    (delta: number) => {
      setAnchorDate((prev) => {
        const next = new Date(prev)
        if (calendarView === 'month') next.setMonth(next.getMonth() + delta)
        else next.setDate(next.getDate() + delta * 7)
        return next
      })
    },
    [calendarView],
  )

  const goToToday = useCallback(() => {
    setAnchorDate(new Date())
  }, [])

  return {
    shifts,
    roleShifts,
    selectedRoleId,
    setSelectedRoleId,
    calendarView,
    setCalendarView,
    anchorDate,
    setAnchorDate,
    weekDays,
    coverage,
    selectedShift,
    selectedShiftId,
    setSelectedShiftId,
    assignShift,
    assignShiftId,
    setAssignShiftId,
    createOpen,
    setCreateOpen,
    copyOpen,
    setCopyOpen,
    duplicateShift,
    duplicateShiftId,
    setDuplicateShiftId,
    rosterSearch,
    setRosterSearch,
    roleStaff,
    createShift,
    copySchedule,
    assignStaff,
    unassignStaff,
    deleteShift,
    duplicateShiftToDates,
    updateShiftHeadcount,
    navigateCalendar,
    goToToday,
  }
}

export type ShiftsState = ReturnType<typeof useShiftsState>
