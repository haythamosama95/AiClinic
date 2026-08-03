import type { AppointmentBranch, AppointmentDoctor, ExistingBooking } from './types'

export const APPOINTMENT_BRANCHES: AppointmentBranch[] = [
  { id: 'downtown', name: 'Downtown Clinic', isActive: true },
  { id: 'nasr-city', name: 'Nasr City', isActive: true },
]

export const APPOINTMENT_DOCTORS: AppointmentDoctor[] = [
  { id: 'doc-sarah', fullName: 'Dr. Sarah Ali', branchIds: ['downtown', 'nasr-city'] },
  { id: 'doc-ahmed', fullName: 'Dr. Ahmed Mostafa', branchIds: ['downtown'] },
  { id: 'doc-laila', fullName: 'Dr. Laila Osman', branchIds: ['downtown', 'nasr-city'] },
  { id: 'doc-karim', fullName: 'Dr. Karim Nabil', branchIds: ['nasr-city'] },
]

/** 30-minute slots from 09:00 through 16:30 */
export const SLOT_TIMES = [
  '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  '12:00', '12:30', '13:00', '13:30', '14:00', '14:30',
  '15:00', '15:30', '16:00', '16:30',
] as const

function formatSlotLabel(time: string): string {
  const [h, m] = time.split(':').map(Number)
  const period = h >= 12 ? 'PM' : 'AM'
  const hour = h > 12 ? h - 12 : h === 0 ? 12 : h
  return `${hour}:${m.toString().padStart(2, '0')} ${period}`
}

export const SLOT_LABELS = Object.fromEntries(
  SLOT_TIMES.map((t) => [t, formatSlotLabel(t)]),
) as Record<(typeof SLOT_TIMES)[number], string>

/** Seed bookings so slot states vary meaningfully across days and branches. */
export const MOCK_BOOKINGS: ExistingBooking[] = [
  // Downtown — Jul 13 (today): busy morning, mixed afternoon
  { branchId: 'downtown', doctorId: 'doc-sarah', date: '2026-07-13', time: '09:00', patientId: 'p1' },
  { branchId: 'downtown', doctorId: 'doc-ahmed', date: '2026-07-13', time: '09:00', patientId: 'p2' },
  { branchId: 'downtown', doctorId: 'doc-laila', date: '2026-07-13', time: '09:00', patientId: 'p3' },
  { branchId: 'downtown', doctorId: 'doc-sarah', date: '2026-07-13', time: '09:30', patientId: 'p4' },
  { branchId: 'downtown', doctorId: 'doc-ahmed', date: '2026-07-13', time: '10:00', patientId: 'p5' },
  { branchId: 'downtown', doctorId: 'doc-laila', date: '2026-07-13', time: '11:00', patientId: 'p1' },
  { branchId: 'downtown', doctorId: 'doc-sarah', date: '2026-07-13', time: '14:00', patientId: 'p2' },
  { branchId: 'downtown', doctorId: 'doc-ahmed', date: '2026-07-13', time: '14:00', patientId: 'p3' },
  { branchId: 'downtown', doctorId: 'doc-laila', date: '2026-07-13', time: '14:30', patientId: 'p4' },
  { branchId: 'downtown', doctorId: 'doc-sarah', date: '2026-07-13', time: '16:00', patientId: 'p5' },
  { branchId: 'downtown', doctorId: 'doc-ahmed', date: '2026-07-13', time: '16:00', patientId: 'p1' },
  { branchId: 'downtown', doctorId: 'doc-laila', date: '2026-07-13', time: '16:00', patientId: 'p2' },

  // Downtown — Jul 14: lighter load
  { branchId: 'downtown', doctorId: 'doc-sarah', date: '2026-07-14', time: '10:00', patientId: 'p3' },
  { branchId: 'downtown', doctorId: 'doc-ahmed', date: '2026-07-14', time: '11:30', patientId: 'p4' },

  // Nasr City — Jul 13
  { branchId: 'nasr-city', doctorId: 'doc-sarah', date: '2026-07-13', time: '09:30', patientId: 'p1' },
  { branchId: 'nasr-city', doctorId: 'doc-laila', date: '2026-07-13', time: '09:30', patientId: 'p2' },
  { branchId: 'nasr-city', doctorId: 'doc-karim', date: '2026-07-13', time: '09:30', patientId: 'p3' },
  { branchId: 'nasr-city', doctorId: 'doc-karim', date: '2026-07-13', time: '13:00', patientId: 'p4' },
  { branchId: 'nasr-city', doctorId: 'doc-sarah', date: '2026-07-13', time: '15:00', patientId: 'p5' },
]

export function getDoctorById(id: string): AppointmentDoctor | undefined {
  return APPOINTMENT_DOCTORS.find((d) => d.id === id)
}

export function getBranchById(id: string): AppointmentBranch | undefined {
  return APPOINTMENT_BRANCHES.find((b) => b.id === id)
}

export function doctorsForBranch(branchId: string): AppointmentDoctor[] {
  return APPOINTMENT_DOCTORS.filter((d) => d.branchIds.includes(branchId))
}
