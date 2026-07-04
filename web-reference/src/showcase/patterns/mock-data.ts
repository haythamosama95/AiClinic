export type ServiceRow = {
  id: string
  name: string
  category: string
  defaultPrice: number
  status: 'active' | 'inactive'
  branches: number
}

export const MOCK_SERVICES: ServiceRow[] = [
  { id: 's1', name: 'General consultation', category: 'Consultation', defaultPrice: 350, status: 'active', branches: 3 },
  { id: 's2', name: 'Dental cleaning', category: 'Dental', defaultPrice: 500, status: 'active', branches: 2 },
  { id: 's3', name: 'Blood panel (CBC)', category: 'Lab', defaultPrice: 180, status: 'active', branches: 3 },
  { id: 's4', name: 'X-ray (chest)', category: 'Imaging', defaultPrice: 220, status: 'inactive', branches: 1 },
  { id: 's5', name: 'Physiotherapy session', category: 'Therapy', defaultPrice: 400, status: 'active', branches: 2 },
  { id: 's6', name: 'Vaccination (flu)', category: 'Preventive', defaultPrice: 150, status: 'active', branches: 3 },
  { id: 's7', name: 'ECG', category: 'Cardiology', defaultPrice: 275, status: 'active', branches: 2 },
  { id: 's8', name: 'Ultrasound (abdominal)', category: 'Imaging', defaultPrice: 650, status: 'active', branches: 2 },
]

export type PatientRow = {
  id: string
  name: string
  mrn: string
  phone: string
  lastVisit: string
  status: 'active' | 'inactive'
}

export const MOCK_PATIENTS: PatientRow[] = [
  { id: 'p1', name: 'Layla Hassan', mrn: 'MRN-10482', phone: '+20 100 234 5678', lastVisit: '28 Jun 2026', status: 'active' },
  { id: 'p2', name: 'Omar Farouk', mrn: 'MRN-09231', phone: '+20 101 876 5432', lastVisit: '30 Jun 2026', status: 'active' },
  { id: 'p3', name: 'Nadia El-Sayed', mrn: 'MRN-11890', phone: '+20 102 345 6789', lastVisit: '01 Jul 2026', status: 'active' },
  { id: 'p4', name: 'Karim Mostafa', mrn: 'MRN-07654', phone: '+20 103 456 7890', lastVisit: '15 May 2026', status: 'inactive' },
  { id: 'p5', name: 'Sara Ibrahim', mrn: 'MRN-12001', phone: '+20 104 567 8901', lastVisit: '03 Jul 2026', status: 'active' },
]

export const MOCK_BRANCHES = [
  { id: 'b1', name: 'Downtown', active: true, override: null as number | null },
  { id: 'b2', name: 'Maadi', active: true, override: 320 },
  { id: 'b3', name: 'Heliopolis', active: false, override: null },
]

export const MOCK_APPOINTMENTS = [
  { id: 'a1', time: '9:00 AM', patient: 'Layla Hassan', doctor: 'Dr. Ahmed', status: 'confirmed' as const, branch: 'Downtown' },
  { id: 'a2', time: '9:30 AM', patient: 'Omar Farouk', doctor: 'Dr. Sara', status: 'pending' as const, branch: 'Downtown' },
  { id: 'a3', time: '10:00 AM', patient: 'Nadia El-Sayed', doctor: 'Dr. Ahmed', status: 'confirmed' as const, branch: 'Downtown' },
  { id: 'a4', time: '10:30 AM', patient: 'Karim Mostafa', doctor: 'Dr. Youssef', status: 'cancelled' as const, branch: 'Maadi' },
]

export const MOCK_INVOICES = [
  { id: 'inv1', patient: 'Layla Hassan', amount: 1250, status: 'paid' as const, date: '02 Jul 2026' },
  { id: 'inv2', patient: 'Omar Farouk', amount: 850, status: 'partial' as const, date: '03 Jul 2026' },
  { id: 'inv3', patient: 'Sara Ibrahim', amount: 420, status: 'unpaid' as const, date: '04 Jul 2026' },
]
