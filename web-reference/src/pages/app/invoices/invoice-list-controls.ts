import { MOCK_BRANCHES } from '@/components/navigation/nav-model'
import {
  ALL_INVOICES,
  INVOICE_STATUS_OPTIONS,
  type InvoiceListRow,
  type InvoiceStatus,
} from '@/data/invoices'

export type InvoiceStatusFilter = 'all' | InvoiceStatus
export type InvoiceBranchFilter = 'all' | string
export type InvoiceSortKey =
  | 'date-desc'
  | 'date-asc'
  | 'balance-desc'
  | 'balance-asc'
  | 'amount-desc'
  | 'amount-asc'

export type InvoiceListControls = {
  search: string
  status: InvoiceStatusFilter
  branch: InvoiceBranchFilter
  sort: InvoiceSortKey
}

export const INVOICE_SORT_OPTIONS = [
  { value: 'date-desc', label: 'Created (newest)' },
  { value: 'date-asc', label: 'Created (oldest)' },
  { value: 'balance-desc', label: 'Remaining (highest)' },
  { value: 'balance-asc', label: 'Remaining (lowest)' },
  { value: 'amount-desc', label: 'Subtotal (highest)' },
  { value: 'amount-asc', label: 'Subtotal (lowest)' },
] as const

export const DEFAULT_INVOICE_CONTROLS: InvoiceListControls = {
  search: '',
  status: 'all',
  branch: 'all',
  sort: 'date-desc',
}

export const INVOICE_STATUS_FILTER_OPTIONS = [
  { value: 'all', label: 'All statuses' },
  ...INVOICE_STATUS_OPTIONS,
] as const

export const INVOICE_BRANCH_FILTER_OPTIONS = [
  { value: 'all', label: 'All branches' },
  ...MOCK_BRANCHES.map((b) => ({ value: b.id, label: b.name })),
] as const

function sortInvoices(rows: InvoiceListRow[], sort: InvoiceSortKey): InvoiceListRow[] {
  const sorted = [...rows]
  switch (sort) {
    case 'date-desc':
      return sorted.sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    case 'date-asc':
      return sorted.sort((a, b) => a.createdAt.localeCompare(b.createdAt))
    case 'balance-desc':
      return sorted.sort((a, b) => b.balance - a.balance)
    case 'balance-asc':
      return sorted.sort((a, b) => a.balance - b.balance)
    case 'amount-desc':
      return sorted.sort((a, b) => b.subtotal - a.subtotal)
    case 'amount-asc':
      return sorted.sort((a, b) => a.subtotal - b.subtotal)
    default:
      return sorted
  }
}

export function filterAndSortInvoices(
  rows: InvoiceListRow[],
  controls: InvoiceListControls,
): InvoiceListRow[] {
  let filtered = rows
  if (controls.search) {
    const q = controls.search.toLowerCase()
    filtered = filtered.filter(
      (row) =>
        (row.invoiceNumber ?? '').toLowerCase().includes(q) ||
        row.patientName.toLowerCase().includes(q) ||
        row.patientMrn.toLowerCase().includes(q),
    )
  }
  if (controls.status !== 'all') {
    filtered = filtered.filter((row) => row.status === controls.status)
  }
  if (controls.branch !== 'all') {
    filtered = filtered.filter((row) => row.branchId === controls.branch)
  }
  return sortInvoices(filtered, controls.sort)
}

export { ALL_INVOICES }
