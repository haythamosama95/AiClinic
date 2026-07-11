import {
  MOCK_PATIENTS,
  patientFullName,
  type Patient,
  type PatientStatus,
} from '@/data/patients'

export type PatientStatusFilter = 'all' | PatientStatus
export type PatientSortKey =
  | 'name-asc'
  | 'name-desc'
  | 'lastVisit-desc'
  | 'lastVisit-asc'
  | 'dob-asc'
  | 'dob-desc'

export type PatientListControls = {
  search: string
  status: PatientStatusFilter
  sort: PatientSortKey
}

export const PATIENT_SORT_OPTIONS = [
  { value: 'name-asc', label: 'Name (A → Z)' },
  { value: 'name-desc', label: 'Name (Z → A)' },
  { value: 'lastVisit-desc', label: 'Last visit (newest)' },
  { value: 'lastVisit-asc', label: 'Last visit (oldest)' },
  { value: 'dob-asc', label: 'Date of birth (oldest)' },
  { value: 'dob-desc', label: 'Date of birth (newest)' },
] as const

export const DEFAULT_PATIENT_CONTROLS: PatientListControls = {
  search: '',
  status: 'all',
  sort: 'name-asc',
}

const STATUS_OPTIONS = [
  { value: 'all', label: 'All statuses' },
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
  { value: 'archived', label: 'Archived' },
] as const

export { STATUS_OPTIONS }

function sortPatients(rows: Patient[], sort: PatientSortKey): Patient[] {
  const sorted = [...rows]
  switch (sort) {
    case 'name-asc':
      return sorted.sort((a, b) => patientFullName(a).localeCompare(patientFullName(b)))
    case 'name-desc':
      return sorted.sort((a, b) => patientFullName(b).localeCompare(patientFullName(a)))
    case 'lastVisit-desc':
      return sorted.sort((a, b) => (b.lastVisit ?? '').localeCompare(a.lastVisit ?? ''))
    case 'lastVisit-asc':
      return sorted.sort((a, b) => (a.lastVisit ?? '').localeCompare(b.lastVisit ?? ''))
    case 'dob-asc':
      return sorted.sort((a, b) => a.dateOfBirth.localeCompare(b.dateOfBirth))
    case 'dob-desc':
      return sorted.sort((a, b) => b.dateOfBirth.localeCompare(a.dateOfBirth))
    default:
      return sorted
  }
}

export function filterAndSortPatients(
  patients: Patient[],
  controls: PatientListControls,
): Patient[] {
  let rows = patients
  if (controls.search) {
    const q = controls.search.toLowerCase()
    rows = rows.filter(
      (p) =>
        patientFullName(p).toLowerCase().includes(q) ||
        p.mrn.toLowerCase().includes(q) ||
        p.email.toLowerCase().includes(q) ||
        p.phone.includes(q),
    )
  }
  if (controls.status !== 'all') {
    rows = rows.filter((p) => p.status === controls.status)
  }
  return sortPatients(rows, controls.sort)
}

export const ALL_PATIENTS = MOCK_PATIENTS
