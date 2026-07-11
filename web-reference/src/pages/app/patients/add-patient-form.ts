import {
  MOCK_PATIENTS,
  patientFullName,
  type Patient,
} from '@/data/patients'

export type AddPatientFormValues = {
  fullName: string
  phone: string
  dateOfBirth: Date | null
  gender: string
  maritalStatus: string
  notes: string
}

export type AddPatientFormErrors = Partial<Record<keyof AddPatientFormValues | '_form', string>>

export const EMPTY_ADD_PATIENT_FORM: AddPatientFormValues = {
  fullName: '',
  phone: '',
  dateOfBirth: null,
  gender: '',
  maritalStatus: '',
  notes: '',
}

const GENDER_VALUES = new Set(['male', 'female', 'other'])
const MARITAL_STATUS_VALUES = new Set(['single', 'married', 'divorced', 'widowed'])

function normalizePhone(value: string): string {
  return value.replace(/\D/g, '')
}

function normalizeName(value: string): string {
  return value.trim().toLowerCase()
}

function toIsoDate(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

export function validateAddPatientForm(values: AddPatientFormValues): AddPatientFormErrors {
  const errors: AddPatientFormErrors = {}
  const name = values.fullName.trim()

  if (!name) {
    errors.fullName = 'Enter the patient’s full name.'
  } else if (name.length < 2) {
    errors.fullName = 'Full name must be at least 2 characters.'
  }

  const phoneDigits = normalizePhone(values.phone)
  if (phoneDigits && (phoneDigits.length < 8 || phoneDigits.length > 15)) {
    errors.phone = 'Phone number must be 8–15 digits.'
  }

  if (values.gender && !GENDER_VALUES.has(values.gender)) {
    errors.gender = 'Select a valid gender.'
  }

  if (values.maritalStatus && !MARITAL_STATUS_VALUES.has(values.maritalStatus)) {
    errors.maritalStatus = 'Select a valid marital state.'
  }

  return errors
}

export function findPatientDuplicates(
  values: AddPatientFormValues,
  excludePatientId?: string,
): Patient[] {
  const phoneDigits = normalizePhone(values.phone)
  const name = normalizeName(values.fullName)
  const dob = values.dateOfBirth ? toIsoDate(values.dateOfBirth) : null

  return MOCK_PATIENTS.filter((patient) => {
    if (excludePatientId && patient.id === excludePatientId) return false
    if (patient.status === 'archived') return false

    const patientPhone = normalizePhone(patient.phone)
    if (phoneDigits.length >= 8 && (patientPhone === phoneDigits || patientPhone.endsWith(phoneDigits))) {
      return true
    }

    if (
      name.length >= 3 &&
      dob &&
      normalizeName(patientFullName(patient)) === name &&
      patient.dateOfBirth === dob
    ) {
      return true
    }

    return false
  })
}

