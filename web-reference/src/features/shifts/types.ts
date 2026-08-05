export type RoleId = 'doctor' | 'nurse' | 'receptionist' | 'lab-tech'

export type CalendarView = 'week' | 'month'

export type CopyScope = 'day' | 'week' | 'month' | 'role'

export type StaffStatus = 'available' | 'on-leave' | 'partially-assigned' | 'fully-assigned'

export type ShiftType = {
  id: string
  roleId: RoleId
  label: string
  startTime: string
  endTime: string
  defaultHeadcount: number
  accentClass: string
}

export type Role = {
  id: RoleId
  label: string
  description: string
  icon: string
  accentClass: string
}

export type StaffMember = {
  id: string
  name: string
  roleId: RoleId
  status: StaffStatus
  weeklyHours: number
  maxWeeklyHours: number
}

export type ShiftInstance = {
  id: string
  roleId: RoleId
  shiftTypeId: string
  date: string
  startTime: string
  endTime: string
  headcount: number
  assignments: string[]
  notes?: string
}

export type CreateShiftInput = {
  roleId: RoleId
  shiftTypeId: string
  startTime: string
  endTime: string
  headcount: number
  dates: string[]
  notes?: string
}

export type CopyScheduleInput = {
  scope: CopyScope
  sourceDate: string
  targetDate: string
  sourceRoleId?: RoleId
  targetRoleId?: RoleId
  includeAssignments: boolean
}

export type DuplicateShiftInput = {
  sourceShiftId: string
  dates: string[]
}

export type ShiftCoverageSummary = {
  totalSlots: number
  filledSlots: number
  understaffedShifts: number
  unassignedStaff: number
}
