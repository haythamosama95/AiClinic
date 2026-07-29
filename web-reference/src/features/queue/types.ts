export type QueueAppointmentStatus =
  | 'scheduled'
  | 'confirmed'
  | 'checked_in'
  | 'waiting'
  | 'ready'
  | 'in_consultation'
  | 'completed'
  | 'no_show'
  | 'cancelled'

export type VisitType = 'appointment' | 'walk_in'

export type QueueAppointment = {
  id: string
  patientId: string
  patientName: string
  patientMrn: string
  time: string
  timeLabel: string
  preferredDoctorId: string | null
  preferredDoctorName: string | null
  assignedDoctorId: string | null
  assignedDoctorName: string | null
  status: QueueAppointmentStatus
  visitType: VisitType
  checkedInAt: string | null
  notes?: string
  isUrgent?: boolean
}

export type DoctorShiftStatus = 'idle' | 'with_patient' | 'on_break'

export type DoctorOnShift = {
  id: string
  fullName: string
  specialty: string
  status: DoctorShiftStatus
  currentPatientName: string | null
  patientsSeen: number
  patientsRemaining: number
  roomNumber: string
  shiftEndsAt: string
}

export type WaitingPatient = {
  id: string
  appointmentId: string
  patientName: string
  patientMrn: string
  checkedInAt: string
  waitMinutes: number
  preferredDoctorName: string | null
  visitType: VisitType
  isOverdue: boolean
}

export type QueueStats = {
  scheduled: number
  checkedIn: number
  waiting: number
  inConsultation: number
  completed: number
  noShow: number
  avgWaitMinutes: number
  walkIns: number
}
