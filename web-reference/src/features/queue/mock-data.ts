import type {
  DoctorOnShift,
  QueueAppointment,
  QueueStats,
  WaitingPatient,
} from './types'

export const QUEUE_TODAY = '2026-07-13'
export const QUEUE_BRANCH = 'Downtown Clinic'
export const QUEUE_SHIFT_LABEL = 'Morning shift · 8:00 AM – 2:00 PM'

export const INITIAL_APPOINTMENTS: QueueAppointment[] = [
  {
    id: 'q1',
    patientId: 'p1',
    patientName: 'Emma Johnson',
    patientMrn: 'MRN-10001',
    time: '09:00',
    timeLabel: '9:00 AM',
    preferredDoctorId: 'doc-sarah',
    preferredDoctorName: 'Dr. Sarah Ali',
    assignedDoctorId: 'doc-sarah',
    assignedDoctorName: 'Dr. Sarah Ali',
    status: 'in_consultation',
    visitType: 'appointment',
    checkedInAt: '2026-07-13T08:52:00',
  },
  {
    id: 'q2',
    patientId: 'p2',
    patientName: 'Liam Williams',
    patientMrn: 'MRN-10002',
    time: '09:00',
    timeLabel: '9:00 AM',
    preferredDoctorId: 'doc-ahmed',
    preferredDoctorName: 'Dr. Ahmed Mostafa',
    assignedDoctorId: 'doc-ahmed',
    assignedDoctorName: 'Dr. Ahmed Mostafa',
    status: 'in_consultation',
    visitType: 'appointment',
    checkedInAt: '2026-07-13T08:55:00',
  },
  {
    id: 'q3',
    patientId: 'p3',
    patientName: 'Olivia Brown',
    patientMrn: 'MRN-10003',
    time: '09:00',
    timeLabel: '9:00 AM',
    preferredDoctorId: 'doc-laila',
    preferredDoctorName: 'Dr. Laila Osman',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'waiting',
    visitType: 'walk_in',
    checkedInAt: '2026-07-13T09:08:00',
    isUrgent: true,
    notes: 'Walk-in · chest discomfort',
  },
  {
    id: 'q4',
    patientId: 'p4',
    patientName: 'Noah Jones',
    patientMrn: 'MRN-10004',
    time: '09:30',
    timeLabel: '9:30 AM',
    preferredDoctorId: 'doc-sarah',
    preferredDoctorName: 'Dr. Sarah Ali',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'ready',
    visitType: 'appointment',
    checkedInAt: '2026-07-13T09:18:00',
  },
  {
    id: 'q5',
    patientId: 'p5',
    patientName: 'Ava Garcia',
    patientMrn: 'MRN-10005',
    time: '10:00',
    timeLabel: '10:00 AM',
    preferredDoctorId: 'doc-ahmed',
    preferredDoctorName: 'Dr. Ahmed Mostafa',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'checked_in',
    visitType: 'appointment',
    checkedInAt: '2026-07-13T09:42:00',
  },
  {
    id: 'q6',
    patientId: 'p1',
    patientName: 'Emma Johnson',
    patientMrn: 'MRN-10001',
    time: '11:00',
    timeLabel: '11:00 AM',
    preferredDoctorId: 'doc-laila',
    preferredDoctorName: 'Dr. Laila Osman',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'confirmed',
    visitType: 'appointment',
    checkedInAt: null,
  },
  {
    id: 'q7',
    patientId: 'p2',
    patientName: 'Liam Williams',
    patientMrn: 'MRN-10002',
    time: '14:00',
    timeLabel: '2:00 PM',
    preferredDoctorId: null,
    preferredDoctorName: null,
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'scheduled',
    visitType: 'appointment',
    checkedInAt: null,
  },
  {
    id: 'q8',
    patientId: 'p3',
    patientName: 'Olivia Brown',
    patientMrn: 'MRN-10003',
    time: '14:00',
    timeLabel: '2:00 PM',
    preferredDoctorId: 'doc-ahmed',
    preferredDoctorName: 'Dr. Ahmed Mostafa',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'scheduled',
    visitType: 'appointment',
    checkedInAt: null,
  },
  {
    id: 'q9',
    patientId: 'p4',
    patientName: 'Noah Jones',
    patientMrn: 'MRN-10004',
    time: '08:30',
    timeLabel: '8:30 AM',
    preferredDoctorId: 'doc-sarah',
    preferredDoctorName: 'Dr. Sarah Ali',
    assignedDoctorId: 'doc-sarah',
    assignedDoctorName: 'Dr. Sarah Ali',
    status: 'completed',
    visitType: 'appointment',
    checkedInAt: '2026-07-13T08:22:00',
  },
  {
    id: 'q10',
    patientId: 'p5',
    patientName: 'Ava Garcia',
    patientMrn: 'MRN-10005',
    time: '08:00',
    timeLabel: '8:00 AM',
    preferredDoctorId: 'doc-laila',
    preferredDoctorName: 'Dr. Laila Osman',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'no_show',
    visitType: 'appointment',
    checkedInAt: null,
  },
  {
    id: 'q11',
    patientId: 'p1',
    patientName: 'Emma Johnson',
    patientMrn: 'MRN-10001',
    time: '16:00',
    timeLabel: '4:00 PM',
    preferredDoctorId: 'doc-sarah',
    preferredDoctorName: 'Dr. Sarah Ali',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'confirmed',
    visitType: 'appointment',
    checkedInAt: null,
  },
  {
    id: 'q12',
    patientId: 'p2',
    patientName: 'Liam Williams',
    patientMrn: 'MRN-10002',
    time: '16:00',
    timeLabel: '4:00 PM',
    preferredDoctorId: 'doc-ahmed',
    preferredDoctorName: 'Dr. Ahmed Mostafa',
    assignedDoctorId: null,
    assignedDoctorName: null,
    status: 'cancelled',
    visitType: 'appointment',
    checkedInAt: null,
  },
]

export const DOCTORS_ON_SHIFT: DoctorOnShift[] = [
  {
    id: 'doc-sarah',
    fullName: 'Dr. Sarah Ali',
    specialty: 'General practice',
    status: 'with_patient',
    currentPatientName: 'Emma Johnson',
    patientsSeen: 3,
    patientsRemaining: 4,
    roomNumber: 'Room 2',
    shiftEndsAt: '2:00 PM',
  },
  {
    id: 'doc-ahmed',
    fullName: 'Dr. Ahmed Mostafa',
    specialty: 'Internal medicine',
    status: 'with_patient',
    currentPatientName: 'Liam Williams',
    patientsSeen: 2,
    patientsRemaining: 3,
    roomNumber: 'Room 4',
    shiftEndsAt: '2:00 PM',
  },
  {
    id: 'doc-laila',
    fullName: 'Dr. Laila Osman',
    specialty: 'Pediatrics',
    status: 'idle',
    currentPatientName: null,
    patientsSeen: 1,
    patientsRemaining: 2,
    roomNumber: 'Room 1',
    shiftEndsAt: '2:00 PM',
  },
]

export function computeQueueStats(appointments: QueueAppointment[]): QueueStats {
  const walkIns = appointments.filter((a) => a.visitType === 'walk_in').length
  const waiting = appointments.filter((a) =>
    ['checked_in', 'waiting', 'ready'].includes(a.status),
  ).length

  const checkedIn = appointments.filter(
    (a) => a.checkedInAt !== null && !['completed', 'no_show', 'cancelled'].includes(a.status),
  ).length

  const waitingPatients = appointments.filter(
    (a) => a.checkedInAt && ['waiting', 'ready', 'checked_in'].includes(a.status),
  )

  let totalWait = 0
  const now = new Date('2026-07-13T10:15:00')
  for (const appt of waitingPatients) {
    if (appt.checkedInAt) {
      const checkedIn = new Date(appt.checkedInAt)
      totalWait += Math.max(0, Math.floor((now.getTime() - checkedIn.getTime()) / 60000))
    }
  }
  const avgWaitMinutes =
    waitingPatients.length > 0 ? Math.round(totalWait / waitingPatients.length) : 0

  return {
    scheduled: appointments.filter((a) =>
      ['scheduled', 'confirmed'].includes(a.status),
    ).length,
    checkedIn,
    waiting,
    inConsultation: appointments.filter((a) => a.status === 'in_consultation').length,
    completed: appointments.filter((a) => a.status === 'completed').length,
    noShow: appointments.filter((a) => a.status === 'no_show').length,
    avgWaitMinutes,
    walkIns,
  }
}

export function deriveWaitingPatients(appointments: QueueAppointment[]): WaitingPatient[] {
  const now = new Date('2026-07-13T10:15:00')

  return appointments
    .filter(
      (a) =>
        a.checkedInAt !== null &&
        ['checked_in', 'waiting', 'ready'].includes(a.status),
    )
    .map((a) => {
      const checkedIn = new Date(a.checkedInAt!)
      const waitMinutes = Math.max(
        0,
        Math.floor((now.getTime() - checkedIn.getTime()) / 60000),
      )
      return {
        id: `wait-${a.id}`,
        appointmentId: a.id,
        patientName: a.patientName,
        patientMrn: a.patientMrn,
        checkedInAt: a.checkedInAt!,
        waitMinutes,
        preferredDoctorName: a.preferredDoctorName,
        visitType: a.visitType,
        isOverdue: waitMinutes >= 20,
      }
    })
    .sort((a, b) => b.waitMinutes - a.waitMinutes)
}
