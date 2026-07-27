import { MOCK_BRANCHES } from '@/components/navigation/nav-model'
import {
  MOCK_PATIENT_VISITS,
  getPatientById,
  getVisitById,
  patientFullName,
  type PatientVisit,
} from '@/data/patients'
import { MOCK_SERVICE_CATALOG, type CatalogService } from '@/data/services'

export type InvoiceStatus = 'draft' | 'issued' | 'partially_paid' | 'paid' | 'voided'
export type PaymentMethod = 'cash' | 'card' | 'bank_transfer' | 'insurance_settlement'
export type DiscountKind = 'percentage' | 'fixed'

export type InvoiceLineItem = {
  id: string
  description: string
  quantity: number
  unitPrice: number
  lineSubtotal: number
  discountKind?: DiscountKind
  discountValue?: number
  discountAmount: number
  lineTotal: number
}

export type InvoicePayment = {
  id: string
  method: PaymentMethod
  /** Positive = payment, negative = refund (append-only ledger) */
  amount: number
  note?: string
  recordedByName: string
  recordedAt: string
}

export type InsuranceProvider = {
  id: string
  name: string
}

export type Invoice = {
  id: string
  invoiceNumber: string | null
  status: InvoiceStatus
  branchId: string
  patientId: string
  visitId: string
  currency: string
  items: InvoiceLineItem[]
  payments: InvoicePayment[]
  subtotal: number
  discountKind?: DiscountKind
  discountValue?: number
  discountAmount: number
  insuranceProviderId?: string
  insuranceCoveredAmount: number
  createdAt: string
  updatedAt: string
  issuedAt?: string
  voidReason?: string
  voidedAt?: string
  voidedByName?: string
}

export type InvoiceListRow = {
  id: string
  invoiceNumber: string | null
  status: InvoiceStatus
  patientId: string
  patientName: string
  patientMrn: string
  branchId: string
  branchName: string
  branchCode: string
  subtotal: number
  discountAmount: number
  insuranceCoveredAmount: number
  paidAmount: number
  balance: number
  createdAt: string
  issuedAt?: string
}

export const BRANCH_CODES: Record<string, string> = {
  downtown: 'MAIN',
  'nasr-city': 'NSR',
  alexandria: 'ALX',
}

export const MOCK_INSURANCE_PROVIDERS: InsuranceProvider[] = [
  { id: 'ins-bluecross', name: 'BlueCross' },
  { id: 'ins-aetna', name: 'Aetna' },
  { id: 'ins-unitedhealth', name: 'UnitedHealth' },
  { id: 'ins-cigna', name: 'Cigna' },
  { id: 'ins-humana', name: 'Humana' },
]

const STAFF_NAMES = ['Mona Saeed', 'Youssef Adel', 'Layla Hassan', 'Ahmed Nabil']
const PAYMENT_METHODS: PaymentMethod[] = ['cash', 'card', 'bank_transfer', 'insurance_settlement']
const VOID_REASONS = [
  'Incorrect service selected on the invoice',
  'Duplicate invoice created in error',
  'Patient requested cancellation before payment',
  'Pricing correction required — reissuing under a new invoice',
]

const STATUS_CYCLE: InvoiceStatus[] = [
  'paid',
  'issued',
  'partially_paid',
  'paid',
  'draft',
  'issued',
  'paid',
  'voided',
  'partially_paid',
  'paid',
]

function pick<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]
}

function pickN<T>(arr: readonly T[], n: number): T[] {
  const shuffled = [...arr].sort(() => 0.5 - Math.random())
  return shuffled.slice(0, Math.max(0, Math.min(n, arr.length)))
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100
}

function branchIdForName(name: string): string {
  return MOCK_BRANCHES.find((b) => b.name === name)?.id ?? MOCK_BRANCHES[0].id
}

function makeLineItem(service: CatalogService, quantity: number, applyDiscount: boolean): InvoiceLineItem {
  const lineSubtotal = round2(service.price * quantity)
  let discountKind: DiscountKind | undefined
  let discountValue: number | undefined
  let discountAmount = 0

  if (applyDiscount) {
    discountKind = 'percentage'
    discountValue = 10
    discountAmount = round2(lineSubtotal * 0.1)
  }

  return {
    id: `line-${service.id}-${Math.random().toString(36).slice(2, 8)}`,
    description: service.name,
    quantity,
    unitPrice: service.price,
    lineSubtotal,
    discountKind,
    discountValue,
    discountAmount,
    lineTotal: round2(lineSubtotal - discountAmount),
  }
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date)
  next.setDate(next.getDate() + days)
  return next
}

function buildPayments(
  status: InvoiceStatus,
  originalDue: number,
  createdAt: Date,
): InvoicePayment[] {
  if (status === 'draft' || status === 'issued' || originalDue <= 0) return []

  const firstDate = addDays(createdAt, 1 + Math.floor(Math.random() * 3))

  if (status === 'partially_paid') {
    const ratio = 0.3 + Math.random() * 0.35
    const amount = round2(originalDue * ratio)

    if (Math.random() < 0.25) {
      const refundDate = addDays(firstDate, 2 + Math.floor(Math.random() * 4))
      const refundAmount = round2(originalDue * 0.2)
      return [
        {
          id: `pay-${Math.random().toString(36).slice(2, 8)}`,
          method: pick(PAYMENT_METHODS),
          amount: originalDue,
          recordedByName: pick(STAFF_NAMES),
          recordedAt: firstDate.toISOString(),
        },
        {
          id: `pay-${Math.random().toString(36).slice(2, 8)}`,
          method: pick(PAYMENT_METHODS),
          amount: -refundAmount,
          note: 'Refund for overcharged service line',
          recordedByName: pick(STAFF_NAMES),
          recordedAt: refundDate.toISOString(),
        },
      ]
    }

    return [
      {
        id: `pay-${Math.random().toString(36).slice(2, 8)}`,
        method: pick(PAYMENT_METHODS),
        amount,
        recordedByName: pick(STAFF_NAMES),
        recordedAt: firstDate.toISOString(),
      },
    ]
  }

  if (status === 'paid') {
    if (Math.random() > 0.45) {
      return [
        {
          id: `pay-${Math.random().toString(36).slice(2, 8)}`,
          method: pick(PAYMENT_METHODS),
          amount: originalDue,
          recordedByName: pick(STAFF_NAMES),
          recordedAt: firstDate.toISOString(),
        },
      ]
    }
    const first = round2(originalDue * 0.5)
    const second = round2(originalDue - first)
    const secondDate = addDays(firstDate, 2 + Math.floor(Math.random() * 5))
    return [
      {
        id: `pay-${Math.random().toString(36).slice(2, 8)}`,
        method: pick(PAYMENT_METHODS),
        amount: first,
        recordedByName: pick(STAFF_NAMES),
        recordedAt: firstDate.toISOString(),
      },
      {
        id: `pay-${Math.random().toString(36).slice(2, 8)}`,
        method: pick(PAYMENT_METHODS),
        amount: second,
        recordedByName: pick(STAFF_NAMES),
        recordedAt: secondDate.toISOString(),
      },
    ]
  }

  if (status === 'voided' && Math.random() < 0.4) {
    return [
      {
        id: `pay-${Math.random().toString(36).slice(2, 8)}`,
        method: pick(PAYMENT_METHODS),
        amount: round2(originalDue * 0.25),
        recordedByName: pick(STAFF_NAMES),
        recordedAt: firstDate.toISOString(),
      },
    ]
  }

  return []
}

function buildInvoice(visit: PatientVisit, index: number, branchSequences: Map<string, number>): Invoice {
  const branchId = branchIdForName(visit.branch)
  const branchCode = BRANCH_CODES[branchId] ?? 'MAIN'
  const status = STATUS_CYCLE[index % STATUS_CYCLE.length]

  const createdAt = addDays(new Date(`${visit.date}T09:30:00`), 0)
  const serviceCount = 1 + Math.floor(Math.random() * 3)
  const services = pickN(MOCK_SERVICE_CATALOG, serviceCount)

  const useLineDiscount = Math.random() < 0.22
  const items = services.map((service, i) =>
    makeLineItem(service, 1 + Math.floor(Math.random() * 2), useLineDiscount && i === 0),
  )

  const rawSubtotal = round2(items.reduce((sum, item) => sum + item.lineTotal, 0))

  let discountKind: DiscountKind | undefined
  let discountValue: number | undefined
  let discountAmount = 0
  if (!useLineDiscount && Math.random() < 0.22) {
    if (Math.random() > 0.5) {
      discountKind = 'percentage'
      discountValue = pick([5, 10, 15, 20])
      discountAmount = round2(rawSubtotal * (discountValue / 100))
    } else {
      discountKind = 'fixed'
      discountValue = round2(Math.min(rawSubtotal * 0.3, 25 + Math.random() * 75))
      discountAmount = discountValue
    }
  }

  let insuranceProviderId: string | undefined
  let insuranceCoveredAmount = 0
  const remainderAfterDiscount = round2(rawSubtotal - discountAmount)
  if (Math.random() < 0.35 && remainderAfterDiscount > 0) {
    insuranceProviderId = pick(MOCK_INSURANCE_PROVIDERS).id
    insuranceCoveredAmount = round2(remainderAfterDiscount * (0.2 + Math.random() * 0.4))
  }

  const originalDue = round2(rawSubtotal - discountAmount - insuranceCoveredAmount)
  const resolvedStatus: InvoiceStatus = originalDue <= 0 && status === 'partially_paid' ? 'paid' : status

  const payments = buildPayments(resolvedStatus, originalDue, createdAt)

  let invoiceNumber: string | null = null
  let issuedAt: string | undefined
  if (resolvedStatus !== 'draft') {
    const seq = (branchSequences.get(branchId) ?? 0) + 1
    branchSequences.set(branchId, seq)
    invoiceNumber = `INV-${branchCode}-${String(seq).padStart(6, '0')}`
    issuedAt = addDays(createdAt, Math.random() > 0.7 ? 1 : 0).toISOString()
  }

  let voidReason: string | undefined
  let voidedAt: string | undefined
  let voidedByName: string | undefined
  if (resolvedStatus === 'voided') {
    voidReason = pick(VOID_REASONS)
    const lastPaymentDate = payments.length > 0 ? new Date(payments[payments.length - 1].recordedAt) : new Date(issuedAt ?? createdAt)
    voidedAt = addDays(lastPaymentDate, 1 + Math.floor(Math.random() * 3)).toISOString()
    voidedByName = pick(STAFF_NAMES)
  }

  const updatedTimestamps = [
    createdAt.toISOString(),
    issuedAt,
    ...payments.map((p) => p.recordedAt),
    voidedAt,
  ].filter((v): v is string => Boolean(v))
  const updatedAt = updatedTimestamps.sort().at(-1) ?? createdAt.toISOString()

  return {
    id: `inv-${visit.id}`,
    invoiceNumber,
    status: resolvedStatus,
    branchId,
    patientId: visit.patientId,
    visitId: visit.id,
    currency: 'EGP',
    items,
    payments,
    subtotal: rawSubtotal,
    discountKind,
    discountValue,
    discountAmount,
    insuranceProviderId,
    insuranceCoveredAmount,
    createdAt: createdAt.toISOString(),
    updatedAt,
    issuedAt,
    voidReason,
    voidedAt,
    voidedByName,
  }
}

const candidateVisits = MOCK_PATIENT_VISITS.filter((_, i) => i % 2 === 0)
const branchSequences = new Map<string, number>()

export const MOCK_INVOICES: Invoice[] = candidateVisits.map((visit, i) =>
  buildInvoice(visit, i, branchSequences),
)

export function originalDueAmount(invoice: Invoice): number {
  return round2(invoice.subtotal - invoice.discountAmount - invoice.insuranceCoveredAmount)
}

export function netPaidAmount(invoice: Invoice): number {
  return round2(invoice.payments.reduce((sum, p) => sum + p.amount, 0))
}

export function invoiceBalance(invoice: Invoice): number {
  return round2(originalDueAmount(invoice) - netPaidAmount(invoice))
}

function toListRow(invoice: Invoice): InvoiceListRow {
  const patient = getPatientById(invoice.patientId)
  const branch = MOCK_BRANCHES.find((b) => b.id === invoice.branchId)
  return {
    id: invoice.id,
    invoiceNumber: invoice.invoiceNumber,
    status: invoice.status,
    patientId: invoice.patientId,
    patientName: patient ? patientFullName(patient) : 'Unknown patient',
    patientMrn: patient?.mrn ?? '—',
    branchId: invoice.branchId,
    branchName: branch?.name ?? 'Unknown branch',
    branchCode: BRANCH_CODES[invoice.branchId] ?? '—',
    subtotal: invoice.subtotal,
    discountAmount: invoice.discountAmount,
    insuranceCoveredAmount: invoice.insuranceCoveredAmount,
    paidAmount: netPaidAmount(invoice),
    balance: invoiceBalance(invoice),
    createdAt: invoice.createdAt,
    issuedAt: invoice.issuedAt,
  }
}

export const MOCK_INVOICE_LIST_ROWS: InvoiceListRow[] = MOCK_INVOICES.map(toListRow)

export function getInvoiceById(id: string): Invoice | undefined {
  return MOCK_INVOICES.find((inv) => inv.id === id)
}

export function getInvoicesForPatient(patientId: string): InvoiceListRow[] {
  return MOCK_INVOICE_LIST_ROWS.filter((row) => row.patientId === patientId)
}

export function getInsuranceProviderById(id?: string): InsuranceProvider | undefined {
  if (!id) return undefined
  return MOCK_INSURANCE_PROVIDERS.find((p) => p.id === id)
}

export function getVisitForInvoice(invoice: Invoice): PatientVisit | undefined {
  return getVisitById(invoice.visitId)
}

export function getBranchById(id: string) {
  return MOCK_BRANCHES.find((b) => b.id === id)
}

export const INVOICE_STATUS_OPTIONS: { value: InvoiceStatus; label: string }[] = [
  { value: 'draft', label: 'Draft' },
  { value: 'issued', label: 'Issued' },
  { value: 'partially_paid', label: 'Partially paid' },
  { value: 'paid', label: 'Paid' },
  { value: 'voided', label: 'Voided' },
]

export function invoiceStatusLabel(status: InvoiceStatus): string {
  return INVOICE_STATUS_OPTIONS.find((o) => o.value === status)?.label ?? status
}

export function invoiceStatusColor(
  status: InvoiceStatus,
): 'neutral' | 'teal' | 'warning' | 'success' | 'danger' {
  switch (status) {
    case 'draft':
      return 'neutral'
    case 'issued':
      return 'teal'
    case 'partially_paid':
      return 'warning'
    case 'paid':
      return 'success'
    case 'voided':
      return 'danger'
    default:
      return 'neutral'
  }
}

export function invoiceStatusDescription(status: InvoiceStatus): string {
  switch (status) {
    case 'draft':
      return 'Created from the visit and still editable. Not yet assigned an invoice number.'
    case 'issued':
      return 'Finalized and numbered — line items are frozen while payment is awaited.'
    case 'partially_paid':
      return 'At least one payment has been recorded, but a balance still remains.'
    case 'paid':
      return 'Balance is settled in full. No further payment is required.'
    case 'voided':
      return 'Cancelled with a reason and locked. No further payments or edits are allowed.'
    default:
      return ''
  }
}

export function paymentMethodLabel(method: PaymentMethod): string {
  switch (method) {
    case 'cash':
      return 'Cash'
    case 'card':
      return 'Card'
    case 'bank_transfer':
      return 'Bank transfer'
    case 'insurance_settlement':
      return 'Insurance settlement'
    default:
      return method
  }
}

export function discountLabel(kind: DiscountKind | undefined, value: number | undefined): string {
  if (!kind || value === undefined) return '—'
  return kind === 'percentage' ? `${value}% off` : `${value.toFixed(2)} off`
}

export function formatDate(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}

export function formatDateTime(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

export const ALL_INVOICES = MOCK_INVOICE_LIST_ROWS
