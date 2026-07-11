export const TIMEZONE_OPTIONS = [
  { value: 'Africa/Cairo', label: 'Cairo (GMT+2)' },
  { value: 'Asia/Riyadh', label: 'Riyadh (GMT+3)' },
  { value: 'Asia/Dubai', label: 'Dubai (GMT+4)' },
  { value: 'Europe/London', label: 'London (GMT+0)' },
  { value: 'Europe/Berlin', label: 'Berlin (GMT+1)' },
  { value: 'America/New_York', label: 'New York (GMT-5)' },
] as const

export const CURRENCY_OPTIONS = [
  { value: 'EGP', label: 'Egyptian Pound (EGP)' },
  { value: 'SAR', label: 'Saudi Riyal (SAR)' },
  { value: 'AED', label: 'UAE Dirham (AED)' },
  { value: 'USD', label: 'US Dollar (USD)' },
  { value: 'EUR', label: 'Euro (EUR)' },
  { value: 'GBP', label: 'British Pound (GBP)' },
] as const

export const STAFF_ROLE_OPTIONS = [
  { value: 'owner', label: 'Owner' },
  { value: 'administrator', label: 'Administrator' },
  { value: 'doctor', label: 'Doctor' },
  { value: 'receptionist', label: 'Receptionist' },
  { value: 'nurse', label: 'Nurse' },
] as const

export const DAYS_OF_WEEK = [
  { id: 'mon', label: 'Monday', short: 'Mon' },
  { id: 'tue', label: 'Tuesday', short: 'Tue' },
  { id: 'wed', label: 'Wednesday', short: 'Wed' },
  { id: 'thu', label: 'Thursday', short: 'Thu' },
  { id: 'fri', label: 'Friday', short: 'Fri' },
  { id: 'sat', label: 'Saturday', short: 'Sat' },
  { id: 'sun', label: 'Sunday', short: 'Sun' },
] as const

export type DayId = (typeof DAYS_OF_WEEK)[number]['id']

export type WorkingDay = {
  day: DayId
  enabled: boolean
  openTime: string
  closeTime: string
}

export type BranchDraft = {
  id: string
  name: string
  code: string
  mobile: string
  mapLocation: string
  workingDays: WorkingDay[]
}

export type StaffDraft = {
  id: string
  name: string
  mobile: string
  username: string
  password: string
  role: string
  branchIds: string[]
}

export type ServiceDraft = {
  id: string
  name: string
  price: number | null
}

export type OrganizationDraft = {
  name: string
  timezone: string
  currency: string
}

export type SetupDraft = {
  organization: OrganizationDraft
  branches: BranchDraft[]
  staff: StaffDraft[]
  services: ServiceDraft[]
}

export function createDefaultWorkingDays(): WorkingDay[] {
  return DAYS_OF_WEEK.map((day) => ({
    day: day.id,
    enabled: day.id !== 'fri' && day.id !== 'sat',
    openTime: '09:00',
    closeTime: '17:00',
  }))
}

export function createEmptyBranch(): BranchDraft {
  return {
    id: crypto.randomUUID(),
    name: '',
    code: '',
    mobile: '',
    mapLocation: '',
    workingDays: createDefaultWorkingDays(),
  }
}

export function createEmptyStaff(): StaffDraft {
  return {
    id: crypto.randomUUID(),
    name: '',
    mobile: '',
    username: '',
    password: '',
    role: 'receptionist',
    branchIds: [],
  }
}

export function createEmptyService(): ServiceDraft {
  return {
    id: crypto.randomUUID(),
    name: '',
    price: null,
  }
}

export function createDefaultSetup(): SetupDraft {
  return {
    organization: {
      name: '',
      timezone: 'Africa/Cairo',
      currency: 'EGP',
    },
    branches: [createEmptyBranch()],
    staff: [createEmptyStaff()],
    services: [createEmptyService()],
  }
}

export const SETTINGS_SCREENS = [
  { id: 'general', label: 'General', description: 'Organization profile and regional defaults' },
  { id: 'setup', label: 'Setup', description: 'Guided clinic configuration wizard' },
  { id: 'branches', label: 'Branches', description: 'Locations, hours, and contact details' },
  { id: 'staff', label: 'Staff', description: 'Team members, roles, and access' },
  { id: 'services', label: 'Services', description: 'Procedures and billable catalog' },
  { id: 'notifications', label: 'Notifications', description: 'Alerts and delivery preferences' },
] as const

export type SettingsScreenId = (typeof SETTINGS_SCREENS)[number]['id']
