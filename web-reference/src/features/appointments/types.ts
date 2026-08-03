export type AppointmentBranch = {
  id: string
  name: string
  isActive: boolean
}

export type AppointmentDoctor = {
  id: string
  fullName: string
  branchIds: string[]
}

export type ExistingBooking = {
  branchId: string
  doctorId: string
  date: string
  time: string
  patientId: string
}

export type SlotStatus = 'locked' | 'available' | 'preferred' | 'alternate'

export type TimeSlot = {
  time: string
  label: string
  status: SlotStatus
  availableDoctorIds: string[]
}

export type BookAppointmentDraft = {
  patientId: string | null
  branchId: string | null
  preferredDoctorId: string | null
  date: string | null
  time: string | null
}
