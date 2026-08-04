export type Weekday =
  | 'monday'
  | 'tuesday'
  | 'wednesday'
  | 'thursday'
  | 'friday'
  | 'saturday'
  | 'sunday'

export type WorkingDayHours = {
  day: Weekday
  isWorkingDay: boolean
  openTime: string | null
  closeTime: string | null
}

export type WorkingSchedule = {
  days: WorkingDayHours[]
}

export type OrganizationProfile = {
  name: string
  logoUrl: string | null
  currencyCode: string
  timezone: string
}

export type BranchRecord = {
  id: string
  name: string
  code: string
  address: string
  phone: string
  mapsUrl: string
  isActive: boolean
  workingSchedule: WorkingSchedule
}

export type StaffRole = 'administrator' | 'doctor' | 'receptionist' | 'lab_staff'

export type StaffRecord = {
  id: string
  fullName: string
  phone: string
  username: string
  role: StaffRole
  branchIds: string[]
  primaryBranchId: string | null
  isActive: boolean
}

export type OrganizationFormValues = OrganizationProfile

export type BranchFormValues = {
  name: string
  code: string
  address: string
  phone: string
  mapsUrl: string
  workingSchedule: WorkingSchedule
}

export type StaffFormValues = {
  fullName: string
  phone: string
  username: string
  password: string
  role: StaffRole | ''
  branchIds: string[]
  primaryBranchId: string | null
}

export type ServiceRecord = {
  id: string
  name: string
  price: number | null
  allBranches: boolean
  branchIds: string[]
}
