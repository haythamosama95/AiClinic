export type PatientStatus = 'active' | 'inactive' | 'archived'

export type Diagnosis = {
  id: string
  code: string
  name: string
  date: string
  status: 'active' | 'resolved'
  provider: string
}

export type Patient = {
  id: string
  mrn: string
  firstName: string
  lastName: string
  email: string
  phone: string
  dateOfBirth: string
  gender: 'male' | 'female' | 'other'
  status: PatientStatus
  bloodType?: string
  address: string
  insuranceProvider?: string
  insuranceId?: string
  allergies: string[]
  diagnoses: Diagnosis[]
  lastVisit?: string
  nextAppointment?: string
  createdAt: string
}

export type PatientVisit = {
  id: string
  patientId: string
  date: string
  doctor: string
  branch: string
}

export type PatientDocument = {
  id: string
  patientId: string
  visitId: string
  name: string
  fileType: string
  sizeBytes: number
}

export type InvoiceStatus = 'draft' | 'sent' | 'paid' | 'overdue' | 'cancelled'

export type PatientInvoice = {
  id: string
  number: string
  patientId: string
  date: string
  dueDate: string
  status: InvoiceStatus
  total: number
}

const firstNames = [
  'Emma', 'Liam', 'Olivia', 'Noah', 'Ava', 'Ethan', 'Sophia', 'Mason',
  'Isabella', 'William', 'Mia', 'James', 'Charlotte', 'Benjamin', 'Amelia',
  'Lucas', 'Harper', 'Henry', 'Evelyn', 'Alexander', 'Layla', 'Omar', 'Nadia',
]
const lastNames = [
  'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis',
  'Rodriguez', 'Martinez', 'Anderson', 'Taylor', 'Thomas', 'Moore', 'Jackson',
  'Martin', 'Lee', 'Thompson', 'White', 'Harris', 'Clark', 'Hassan', 'Farouk',
]
const doctors = [
  'Dr. Sarah Chen', 'Dr. Michael Park', 'Dr. Emily Watson',
  'Dr. James Liu', 'Dr. Anna Kowalski',
]
const branches = ['Downtown Clinic', 'Nasr City', 'Alexandria']
const documentNames = [
  'Lab results.pdf',
  'Prescription.pdf',
  'Referral letter.pdf',
  'X-ray report.pdf',
  'Discharge summary.pdf',
]
const diagnosesCatalog = [
  { code: 'I10', name: 'Essential Hypertension' },
  { code: 'E11.9', name: 'Type 2 Diabetes Mellitus' },
  { code: 'J06.9', name: 'Acute Upper Respiratory Infection' },
  { code: 'M54.5', name: 'Low Back Pain' },
  { code: 'F41.1', name: 'Generalized Anxiety Disorder' },
  { code: 'K21.0', name: 'GERD with Esophagitis' },
]
const allergiesCatalog = [
  'Penicillin', 'Sulfa drugs', 'Latex', 'Peanuts', 'Shellfish', 'Aspirin', 'Ibuprofen',
]
const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'O+', 'O-']
const insurers = ['BlueCross', 'Aetna', 'UnitedHealth', 'Cigna', 'Humana']

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]
}

function pickN<T>(arr: T[], n: number): T[] {
  const shuffled = [...arr].sort(() => 0.5 - Math.random())
  return shuffled.slice(0, n)
}

function toIsoDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}

function genId(prefix: string, i: number): string {
  return `${prefix}-${String(i).padStart(4, '0')}`
}

export const MOCK_PATIENTS: Patient[] = Array.from({ length: 32 }, (_, i) => {
  const fn = firstNames[i % firstNames.length]
  const ln = lastNames[i % lastNames.length]
  const dob = new Date()
  dob.setFullYear(dob.getFullYear() - (25 + (i % 50)))
  const lastVisit = new Date()
  lastVisit.setDate(lastVisit.getDate() - (i % 30))
  const nextAppt = i % 5 !== 0 ? new Date() : null
  if (nextAppt) nextAppt.setDate(nextAppt.getDate() + (i % 14))

  return {
    id: genId('pat', i + 1),
    mrn: `MRN-${10000 + i}`,
    firstName: fn,
    lastName: ln,
    email: `${fn.toLowerCase()}.${ln.toLowerCase()}@email.com`,
    phone: `+20 10${String(i).padStart(1, '0')} ${String(100 + i * 3).padStart(3, '0')} ${String(1000 + i * 7).slice(-4)}`,
    dateOfBirth: toIsoDate(dob),
    gender: i % 3 === 0 ? 'female' : i % 3 === 1 ? 'male' : 'other',
    status: i % 10 === 0 ? 'inactive' : i % 15 === 0 ? 'archived' : 'active',
    bloodType: pick(bloodTypes),
    address: `${100 + i} Main St, Suite ${i % 20}, Cairo`,
    insuranceProvider: pick(insurers),
    insuranceId: `INS-${20000 + i}`,
    allergies: pickN(allergiesCatalog, Math.floor(Math.random() * 3)),
    diagnoses: pickN(diagnosesCatalog, Math.floor(Math.random() * 3) + 1).map((d, j) => {
      const diagDate = new Date()
      diagDate.setDate(diagDate.getDate() - j * 30)
      return {
        id: `diag-${i}-${j}`,
        ...d,
        date: toIsoDate(diagDate),
        status: j === 0 ? 'active' as const : pick(['active', 'resolved'] as const),
        provider: pick(doctors),
      }
    }),
    lastVisit: toIsoDate(lastVisit),
    nextAppointment: nextAppt ? toIsoDate(nextAppt) : undefined,
    createdAt: toIsoDate(new Date(dob.getFullYear() - 1, dob.getMonth(), dob.getDate())),
  }
})

export const MOCK_PATIENT_VISITS: PatientVisit[] = MOCK_PATIENTS.flatMap((patient, i) => {
  const visitCount = 2 + (i % 4)
  return Array.from({ length: visitCount }, (_, j) => {
    const visitDate = new Date()
    visitDate.setDate(visitDate.getDate() - j * 14 - (i % 7))
    return {
      id: `visit-${patient.id}-${j}`,
      patientId: patient.id,
      date: toIsoDate(visitDate),
      doctor: doctors[(i + j) % doctors.length],
      branch: branches[(i + j) % branches.length],
    }
  })
})

export const MOCK_PATIENT_DOCUMENTS: PatientDocument[] = MOCK_PATIENT_VISITS.flatMap((visit, i) => {
  const docCount = i % 3 === 0 ? 0 : 1 + (i % 2)
  return Array.from({ length: docCount }, (_, j) => ({
    id: `doc-${visit.id}-${j}`,
    patientId: visit.patientId,
    visitId: visit.id,
    name: documentNames[(i + j) % documentNames.length],
    fileType: 'PDF',
    sizeBytes: 48_000 + ((i * 17 + j * 11) % 400) * 1024,
  }))
})

export const MOCK_PATIENT_INVOICES: PatientInvoice[] = Array.from({ length: 28 }, (_, i) => {
  const patient = MOCK_PATIENTS[i % MOCK_PATIENTS.length]
  const subtotal = 150 + (i % 10) * 75
  const total = subtotal * 1.08
  const statuses: InvoiceStatus[] = ['draft', 'sent', 'paid', 'overdue', 'cancelled']
  const invDate = new Date()
  invDate.setDate(invDate.getDate() - (i % 30))
  const dueDate = new Date()
  dueDate.setDate(dueDate.getDate() + (30 - (i % 30)))

  return {
    id: genId('inv', i + 1),
    number: `INV-2026-${String(1000 + i)}`,
    patientId: patient.id,
    date: toIsoDate(invDate),
    dueDate: toIsoDate(dueDate),
    status: statuses[i % statuses.length],
    total,
  }
})

export function getPatientById(id: string): Patient | undefined {
  return MOCK_PATIENTS.find((p) => p.id === id)
}

export function getInvoicesForPatient(patientId: string): PatientInvoice[] {
  return MOCK_PATIENT_INVOICES.filter((inv) => inv.patientId === patientId)
}

export function getVisitsForPatient(patientId: string): PatientVisit[] {
  return MOCK_PATIENT_VISITS.filter((v) => v.patientId === patientId).sort(
    (a, b) => b.date.localeCompare(a.date),
  )
}

export function getDocumentsForPatient(patientId: string): PatientDocument[] {
  return MOCK_PATIENT_DOCUMENTS.filter((d) => d.patientId === patientId)
}

export function getVisitById(visitId: string): PatientVisit | undefined {
  return MOCK_PATIENT_VISITS.find((v) => v.id === visitId)
}

export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function downloadPatientDocument(
  doc: PatientDocument,
  visit?: PatientVisit,
): void {
  const visitLine = visit
    ? `Linked visit: ${formatDate(visit.date)} · ${visit.doctor} · ${visit.branch}`
    : 'Linked visit: Not available'
  const content = [
    `Document: ${doc.name}`,
    `Type: ${doc.fileType}`,
    visitLine,
    '',
    'This is mock content for the web reference UI.',
  ].join('\n')
  const blob = new Blob([content], { type: 'text/plain' })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = doc.name.replace(/\.pdf$/i, '.txt')
  anchor.click()
  URL.revokeObjectURL(url)
}

export function patientFullName(patient: Patient): string {
  return `${patient.firstName} ${patient.lastName}`
}

export function formatDate(iso: string): string {
  const d = new Date(iso + 'T00:00:00')
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}

export function patientStatusColor(status: PatientStatus): 'success' | 'neutral' | 'danger' {
  if (status === 'active') return 'success'
  if (status === 'archived') return 'danger'
  return 'neutral'
}

export function invoiceStatusColor(status: InvoiceStatus): 'success' | 'warning' | 'danger' | 'neutral' {
  if (status === 'paid') return 'success'
  if (status === 'overdue') return 'danger'
  if (status === 'sent') return 'warning'
  return 'neutral'
}
