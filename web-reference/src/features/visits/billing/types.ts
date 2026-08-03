import type { CatalogService } from '@/data/services'

export type SelectedServiceLine = {
  id: string
  serviceId: string
  name: string
  unitPrice: number
  quantity: number
}

export type DiscountType = 'none' | 'percentage' | 'fixed'

export type VisitInvoice = {
  number: string
  lines: SelectedServiceLine[]
  discountType: DiscountType
  discountValue: number
  subtotal: number
  discountAmount: number
  total: number
}

export type BillingStep = 'services' | 'invoice'

export function lineTotal(line: SelectedServiceLine): number {
  return line.unitPrice * line.quantity
}

export function computeInvoiceTotals(
  lines: SelectedServiceLine[],
  discountType: DiscountType,
  discountValue: number,
): Pick<VisitInvoice, 'subtotal' | 'discountAmount' | 'total'> {
  const subtotal = lines.reduce((sum, line) => sum + lineTotal(line), 0)
  let discountAmount = 0

  if (discountType === 'percentage' && discountValue > 0) {
    discountAmount = Math.min(subtotal, (subtotal * discountValue) / 100)
  } else if (discountType === 'fixed' && discountValue > 0) {
    discountAmount = Math.min(subtotal, discountValue)
  }

  return {
    subtotal,
    discountAmount,
    total: subtotal - discountAmount,
  }
}

export function createLineFromService(service: CatalogService): SelectedServiceLine {
  return {
    id: `line-${service.id}-${Date.now()}`,
    serviceId: service.id,
    name: service.name,
    unitPrice: service.price,
    quantity: 1,
  }
}
