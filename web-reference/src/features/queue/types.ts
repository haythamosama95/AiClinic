export type AppointmentStatus =
  | 'scheduled'
  | 'arrived'
  | 'checked_in'
  | 'in_progress'
  | 'completed'
  | 'cancelled'
  | 'no_show'

export type DoctorStatus = 'available' | 'with_patient' | 'on_break'

export type AppointmentType =
  | 'follow_up'
  | 'new_patient'
  | 'consultation'
  | 'procedure'
  | 'walk_in'

export type AppointmentExceptions = {
  copayDue?: boolean
  formsIncomplete?: boolean
  selfCheckInPending?: boolean
  insuranceIssue?: boolean
}

export type Appointment = {
  id: string
  patientName: string
  mrn: string
  scheduledTime: string
  status: AppointmentStatus
  preferredDoctorId: string | null
  preferredDoctorName: string | null
  appointmentType: AppointmentType
  isWalkIn: boolean
  arrivedAt: string | null
  checkedInAt: string | null
  consultationStartedAt: string | null
  assignedDoctorId: string | null
  assignedDoctorName: string | null
  notes?: string
  exceptions?: AppointmentExceptions
}

export type Doctor = {
  id: string
  name: string
  specialty: string
  status: DoctorStatus
  currentPatientId: string | null
  currentPatientName: string | null
  patientsSeenToday: number
  idleSince: string | null
}

export type QueueKpiFilter =
  | 'all'
  | 'waiting'
  | 'checked_in'
  | 'in_progress'
  | 'completed'
  | 'cancelled'
  | 'no_show'

export type QueueStats = {
  total: number
  waiting: number
  checkedIn: number
  inProgress: number
  completed: number
  cancelled: number
  noShow: number
  avgWaitMinutes: number
  avgConsultationMinutes: number
  currentQueueLength: number
  longestWaitMinutes: number
}

export type KpiTrend = {
  label: string
  direction: 'up' | 'down' | 'flat'
  /** Whether an upward trend is favorable for this metric */
  favorableUp: boolean
}

export type CheckedInSortMode = 'longest_wait' | 'next_in_order'

export type DoctorWithLag = Doctor & {
  lagMinutes: number
}

export type StatusTransition = {
  target: AppointmentStatus
  label: string
  variant?: 'default' | 'danger' | 'success'
}

export const STATUS_TRANSITIONS: Record<AppointmentStatus, StatusTransition[]> = {
  scheduled: [
    { target: 'arrived', label: 'Arrived' },
    { target: 'checked_in', label: 'Check in' },
    { target: 'cancelled', label: 'Cancel', variant: 'danger' },
    { target: 'no_show', label: 'No Show', variant: 'danger' },
  ],
  arrived: [
    { target: 'checked_in', label: 'Check in' },
    { target: 'cancelled', label: 'Cancel', variant: 'danger' },
  ],
  checked_in: [
    { target: 'in_progress', label: 'Start Consultation' },
    { target: 'cancelled', label: 'Cancel', variant: 'danger' },
  ],
  in_progress: [{ target: 'completed', label: 'Complete', variant: 'success' }],
  completed: [],
  cancelled: [],
  no_show: [],
}

export const APPOINTMENT_TYPE_LABELS: Record<AppointmentType, string> = {
  follow_up: 'Follow-up',
  new_patient: 'New Patient',
  consultation: 'Consultation',
  procedure: 'Procedure',
  walk_in: 'Walk-in',
}

export const STATUS_LABELS: Record<AppointmentStatus, string> = {
  scheduled: 'Scheduled',
  arrived: 'Arrived',
  checked_in: 'Checked In',
  in_progress: 'In Progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
  no_show: 'No Show',
}
