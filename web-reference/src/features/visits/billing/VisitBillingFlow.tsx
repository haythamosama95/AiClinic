import { useCallback, useMemo, useState } from 'react'
import type { Patient } from '@/data/patients'
import {
  generateInvoiceNumber,
  MOCK_SERVICE_CATALOG,
  type CatalogService,
} from '@/data/services'
import { InvoiceReviewStep } from './InvoiceReviewStep'
import { ServiceSelectionStep } from './ServiceSelectionStep'
import type { BillingStep, DiscountType, SelectedServiceLine, VisitInvoice } from './types'
import { computeInvoiceTotals } from './types'

export type VisitBillingFlowProps = {
  patient: Patient
  onBack: () => void
  onComplete: (invoice: VisitInvoice) => void
}

export function VisitBillingFlow({ patient, onBack, onComplete }: VisitBillingFlowProps) {
  const [step, setStep] = useState<BillingStep>('services')
  const [catalog, setCatalog] = useState<CatalogService[]>(MOCK_SERVICE_CATALOG)
  const [selectedLines, setSelectedLines] = useState<SelectedServiceLine[]>([])
  const [invoiceNumber] = useState(() => generateInvoiceNumber())
  const [discountType, setDiscountType] = useState<DiscountType>('none')
  const [discountValue, setDiscountValue] = useState(0)

  const handleDiscountTypeChange = useCallback((type: DiscountType) => {
    setDiscountType(type)
    setDiscountValue(0)
  }, [])

  const invoice = useMemo((): VisitInvoice => {
    const totals = computeInvoiceTotals(selectedLines, discountType, discountValue)
    return {
      number: invoiceNumber,
      lines: selectedLines,
      discountType,
      discountValue,
      ...totals,
    }
  }, [selectedLines, discountType, discountValue, invoiceNumber])

  const handleFinalize = useCallback(() => {
    onComplete(invoice)
  }, [invoice, onComplete])

  if (step === 'invoice') {
    return (
      <InvoiceReviewStep
        patient={patient}
        invoiceNumber={invoiceNumber}
        lines={selectedLines}
        discountType={discountType}
        discountValue={discountValue}
        onDiscountTypeChange={handleDiscountTypeChange}
        onDiscountValueChange={setDiscountValue}
        onBack={() => setStep('services')}
        onFinalize={handleFinalize}
      />
    )
  }

  return (
    <ServiceSelectionStep
      catalog={catalog}
      selectedLines={selectedLines}
      onCatalogChange={setCatalog}
      onLinesChange={setSelectedLines}
      onContinue={() => setStep('invoice')}
      onBack={onBack}
    />
  )
}
