import { useCallback, useMemo, useState } from 'react'
import type { Patient } from '@/data/patients'
import { MOCK_PATIENTS } from '@/data/patients'
import type { VisitInvoice } from './billing/types'
import {
  EMPTY_VISIT_FORM,
  type VisitFormData,
  type VisitPhase,
} from './types'

export const VISIT_PHASES: { id: VisitPhase; label: string; description: string }[] = [
  { id: 'intake', label: 'Intake', description: 'Chief complaint & history' },
  { id: 'findings', label: 'Findings & diagnosis', description: 'Exam, vitals & assessment' },
  { id: 'treatment', label: 'Treatment', description: 'Plan, prescriptions & files' },
]

const PHASE_ORDER: VisitPhase[] = ['intake', 'findings', 'treatment', 'summary', 'billing', 'completed']

export type UseVisitFormOptions = {
  patientId?: string
}

export function useVisitForm({ patientId }: UseVisitFormOptions = {}) {
  const patient = useMemo(
    () => MOCK_PATIENTS.find((p) => p.id === patientId) ?? MOCK_PATIENTS[0],
    [patientId],
  )

  const [phase, setPhase] = useState<VisitPhase>('intake')
  const [direction, setDirection] = useState(1)
  const [form, setForm] = useState<VisitFormData>(() => seedFromPatient(patient))
  const [finalizedAt, setFinalizedAt] = useState<Date | null>(null)
  const [invoice, setInvoice] = useState<VisitInvoice | null>(null)

  const phaseIndex = PHASE_ORDER.indexOf(phase)
  const isSummary = phase === 'summary'
  const isBilling = phase === 'billing'
  const isCompleted = phase === 'completed'

  const updateForm = useCallback((patch: Partial<VisitFormData>) => {
    setForm((prev) => ({ ...prev, ...patch }))
  }, [])

  const goNext = useCallback(() => {
    const idx = PHASE_ORDER.indexOf(phase)
    if (idx < PHASE_ORDER.length - 2) {
      setDirection(1)
      setPhase(PHASE_ORDER[idx + 1])
    } else if (phase === 'treatment') {
      setDirection(1)
      setPhase('summary')
    }
  }, [phase])

  const goBack = useCallback(() => {
    if (phase === 'billing') {
      setDirection(-1)
      setPhase('summary')
      return
    }
    if (phase === 'summary') {
      setDirection(-1)
      setFinalizedAt(null)
      setPhase('treatment')
      return
    }
    const idx = PHASE_ORDER.indexOf(phase)
    if (idx > 0) {
      setDirection(-1)
      setPhase(PHASE_ORDER[idx - 1])
    }
  }, [phase])

  const goToPhase = useCallback(
    (target: VisitPhase) => {
      if (target === 'summary' || target === 'billing' || target === 'completed') return
      const currentIdx = PHASE_ORDER.indexOf(phase === 'summary' ? 'treatment' : phase)
      const targetIdx = PHASE_ORDER.indexOf(target)
      setDirection(targetIdx >= currentIdx ? 1 : -1)
      setPhase(target)
      setFinalizedAt(null)
    },
    [phase],
  )

  const ensureSummary = useCallback(() => {
    setPhase('summary')
  }, [])

  const beginBilling = useCallback(() => {
    setDirection(1)
    setPhase('billing')
  }, [])

  const completeVisit = useCallback((visitInvoice: VisitInvoice) => {
    setInvoice(visitInvoice)
    setFinalizedAt(new Date())
    setDirection(1)
    setPhase('completed')
  }, [])

  const finalizeVisit = useCallback(() => {
    beginBilling()
  }, [beginBilling])

  const resetVisit = useCallback(() => {
    setForm(seedFromPatient(patient))
    setPhase('intake')
    setDirection(1)
    setFinalizedAt(null)
    setInvoice(null)
  }, [patient])

  const progress = isSummary || isBilling || isCompleted
    ? 100
    : ((phaseIndex + 1) / (PHASE_ORDER.length - 2)) * 100

  return {
    patient,
    form,
    updateForm,
    phase,
    phaseIndex: isSummary || isBilling || isCompleted ? VISIT_PHASES.length : phaseIndex,
    direction,
    isSummary,
    isBilling,
    isCompleted,
    finalizedAt,
    invoice,
    progress,
    goNext,
    goBack,
    goToPhase,
    resetVisit,
    ensureSummary,
    beginBilling,
    completeVisit,
    finalizeVisit,
    canGoBack: phase !== 'intake',
    isLastFormPhase: phase === 'treatment',
  }
}

function seedFromPatient(patient: Patient): VisitFormData {
  return {
    ...EMPTY_VISIT_FORM,
    allergies: patient.allergies.map((label, i) => ({
      id: `patient-allergy-${i}`,
      label,
      meta: 'From record',
    })),
    chronicConditions: patient.diagnoses
      .filter((d) => d.status === 'active')
      .map((d) => ({
        id: d.id,
        label: d.name,
        meta: d.code,
      })),
  }
}
