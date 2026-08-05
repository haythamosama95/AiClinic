import type { Role, ShiftType, StaffMember } from './types'

export const ROLES: Role[] = [
  {
    id: 'doctor',
    label: 'Doctors',
    description: 'Consultation blocks and on-call coverage',
    icon: 'stethoscope',
    accentClass: 'shift-accent-doctor',
  },
  {
    id: 'nurse',
    label: 'Nurses',
    description: 'Ward rotations and patient care',
    icon: 'heart-pulse',
    accentClass: 'shift-accent-nurse',
  },
  {
    id: 'receptionist',
    label: 'Reception',
    description: 'Front desk and patient intake',
    icon: 'headset',
    accentClass: 'shift-accent-reception',
  },
  {
    id: 'lab-tech',
    label: 'Lab',
    description: 'Diagnostics and specimen processing',
    icon: 'flask-conical',
    accentClass: 'shift-accent-lab',
  },
]

export const SHIFT_TYPES: ShiftType[] = [
  { id: 'doc-morning', roleId: 'doctor', label: 'Morning consultation', startTime: '08:00', endTime: '12:00', defaultHeadcount: 3, accentClass: 'shift-band-doctor' },
  { id: 'doc-afternoon', roleId: 'doctor', label: 'Afternoon consultation', startTime: '13:00', endTime: '17:00', defaultHeadcount: 3, accentClass: 'shift-band-doctor' },
  { id: 'doc-evening', roleId: 'doctor', label: 'Evening clinic', startTime: '17:00', endTime: '21:00', defaultHeadcount: 2, accentClass: 'shift-band-doctor' },
  { id: 'nurse-day', roleId: 'nurse', label: 'Day ward', startTime: '07:00', endTime: '15:00', defaultHeadcount: 4, accentClass: 'shift-band-nurse' },
  { id: 'nurse-evening', roleId: 'nurse', label: 'Evening ward', startTime: '15:00', endTime: '23:00', defaultHeadcount: 3, accentClass: 'shift-band-nurse' },
  { id: 'nurse-night', roleId: 'nurse', label: 'Night ward', startTime: '23:00', endTime: '07:00', defaultHeadcount: 2, accentClass: 'shift-band-nurse' },
  { id: 'rec-am', roleId: 'receptionist', label: 'Morning desk', startTime: '08:00', endTime: '14:00', defaultHeadcount: 2, accentClass: 'shift-band-reception' },
  { id: 'rec-pm', roleId: 'receptionist', label: 'Afternoon desk', startTime: '14:00', endTime: '20:00', defaultHeadcount: 2, accentClass: 'shift-band-reception' },
  { id: 'lab-am', roleId: 'lab-tech', label: 'Morning lab', startTime: '07:00', endTime: '12:00', defaultHeadcount: 2, accentClass: 'shift-band-lab' },
  { id: 'lab-pm', roleId: 'lab-tech', label: 'Afternoon lab', startTime: '12:00', endTime: '17:00', defaultHeadcount: 2, accentClass: 'shift-band-lab' },
]

export const STAFF: StaffMember[] = [
  { id: 's1', name: 'Dr. Amira Hassan', roleId: 'doctor', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's2', name: 'Dr. Omar Khalil', roleId: 'doctor', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's3', name: 'Dr. Layla Mansour', roleId: 'doctor', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's4', name: 'Dr. Karim Nasser', roleId: 'doctor', status: 'on-leave', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's5', name: 'Nurse Sara Ibrahim', roleId: 'nurse', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's6', name: 'Nurse Fatima Ali', roleId: 'nurse', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's7', name: 'Nurse Youssef Mahmoud', roleId: 'nurse', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's8', name: 'Nurse Hana Saleh', roleId: 'nurse', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's9', name: 'Rania Farouk', roleId: 'receptionist', status: 'available', weeklyHours: 0, maxWeeklyHours: 38 },
  { id: 's10', name: 'Tarek Mostafa', roleId: 'receptionist', status: 'available', weeklyHours: 0, maxWeeklyHours: 38 },
  { id: 's11', name: 'Dina Awad', roleId: 'receptionist', status: 'available', weeklyHours: 0, maxWeeklyHours: 38 },
  { id: 's12', name: 'Hassan Rizk', roleId: 'lab-tech', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
  { id: 's13', name: 'Maya Zaki', roleId: 'lab-tech', status: 'available', weeklyHours: 0, maxWeeklyHours: 40 },
]
