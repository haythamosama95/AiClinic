export type CatalogService = {
  id: string
  name: string
  price: number
}

export const MOCK_SERVICE_CATALOG: CatalogService[] = [
  { id: 'svc-consultation', name: 'General consultation', price: 350 },
  { id: 'svc-follow-up', name: 'Follow-up visit', price: 200 },
  { id: 'svc-ecg', name: 'ECG', price: 150 },
  { id: 'svc-blood-panel', name: 'Complete blood count', price: 180 },
  { id: 'svc-xray', name: 'Chest X-ray', price: 250 },
  { id: 'svc-ultrasound', name: 'Abdominal ultrasound', price: 450 },
  { id: 'svc-injection', name: 'Intramuscular injection', price: 75 },
  { id: 'svc-wound-dressing', name: 'Wound dressing', price: 120 },
  { id: 'svc-iv-therapy', name: 'IV fluid therapy', price: 300 },
  { id: 'svc-physio', name: 'Physiotherapy session', price: 280 },
  { id: 'svc-dental-cleaning', name: 'Dental cleaning', price: 400 },
  { id: 'svc-vaccination', name: 'Vaccination administration', price: 100 },
]

export function searchServices(query: string, catalog: CatalogService[]): CatalogService[] {
  const q = query.trim().toLowerCase()
  if (!q) return catalog
  return catalog.filter((s) => s.name.toLowerCase().includes(q))
}

export function getServiceById(id: string, catalog: CatalogService[]): CatalogService | undefined {
  return catalog.find((s) => s.id === id)
}

export function generateInvoiceNumber(): string {
  const year = new Date().getFullYear()
  const seq = String(Math.floor(Math.random() * 9000) + 1000)
  return `INV-${year}-${seq}`
}
