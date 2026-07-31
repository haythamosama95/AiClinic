import type { StaffRole } from './types'

export const CURRENCY_CODES = [
  'AED',
  'AUD',
  'BHD',
  'CAD',
  'CHF',
  'CNY',
  'EGP',
  'EUR',
  'GBP',
  'INR',
  'JOD',
  'JPY',
  'KWD',
  'OMR',
  'QAR',
  'SAR',
  'TRY',
  'USD',
  'ZAR',
] as const

export const TIMEZONES = [
  'Africa/Cairo',
  'Africa/Johannesburg',
  'Africa/Lagos',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/New_York',
  'America/Toronto',
  'Asia/Baghdad',
  'Asia/Dubai',
  'Asia/Kolkata',
  'Asia/Kuwait',
  'Asia/Qatar',
  'Asia/Riyadh',
  'Asia/Tokyo',
  'Australia/Sydney',
  'Europe/Berlin',
  'Europe/London',
  'Europe/Paris',
  'UTC',
] as const

export const WEEKDAYS = [
  { id: 'monday' as const, label: 'Monday' },
  { id: 'tuesday' as const, label: 'Tuesday' },
  { id: 'wednesday' as const, label: 'Wednesday' },
  { id: 'thursday' as const, label: 'Thursday' },
  { id: 'friday' as const, label: 'Friday' },
  { id: 'saturday' as const, label: 'Saturday' },
  { id: 'sunday' as const, label: 'Sunday' },
]

export const STAFF_ROLES: { value: StaffRole; label: string }[] = [
  { value: 'administrator', label: 'Administrator' },
  { value: 'doctor', label: 'Doctor' },
  { value: 'receptionist', label: 'Receptionist' },
  { value: 'lab_staff', label: 'Lab staff' },
]

export const ROLE_LABELS: Record<StaffRole, string> = {
  administrator: 'Administrator',
  doctor: 'Doctor',
  receptionist: 'Receptionist',
  lab_staff: 'Lab staff',
}

export const ROLE_PERMISSIONS: Record<StaffRole, string[]> = {
  administrator: [
    'Manage staff and branches',
    'Full patient records',
    'Appointments and visits',
    'Billing, invoices, and payments',
    'Service catalog',
    'Analytics and AI access',
  ],
  doctor: [
    'View and create patients',
    'Appointments and visits',
    'Edit clinical notes (SOAP)',
    'Upload visit attachments',
    'AI access',
  ],
  receptionist: [
    'View patients',
    'Manage appointments',
    'View and create invoices',
    'Record payments',
  ],
  lab_staff: [
    'View patients',
    'Read appointments',
    'Upload visit attachments',
  ],
}

export const STAFF_USERNAME_HINT =
  '3–32 characters. Letters, numbers, dots, underscores, and hyphens. Must start with a letter.'

export const STAFF_PASSWORD_HINT =
  'At least 8 characters with uppercase, lowercase, and a number.'
