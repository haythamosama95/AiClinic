import { useCallback, useEffect, useId, useState } from 'react'
import { useToast } from '@/components/toast/Toast'
import { getReducedMotion } from '@/lib/motion'
import {
  EMPTY_ADD_PATIENT_FORM,
  findPatientDuplicates,
  validateAddPatientForm,
  type AddPatientFormErrors,
  type AddPatientFormValues,
} from './add-patient-form'

export const MOCK_BRANCH_NAME = 'Downtown Clinic'

export type UseAddPatientRegistrationOptions = {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess?: (patientId: string) => void
}

export function useAddPatientRegistration({
  open,
  onOpenChange,
  onSuccess,
}: UseAddPatientRegistrationOptions) {
  const formId = useId()
  const { toast } = useToast()
  const [values, setValues] = useState<AddPatientFormValues>(EMPTY_ADD_PATIENT_FORM)
  const [errors, setErrors] = useState<AddPatientFormErrors>({})
  const [submitting, setSubmitting] = useState(false)
  const [duplicateOpen, setDuplicateOpen] = useState(false)
  const [duplicateCandidates, setDuplicateCandidates] = useState<ReturnType<typeof findPatientDuplicates>>([])
  const [acknowledgeDuplicate, setAcknowledgeDuplicate] = useState(false)

  const resetForm = useCallback(() => {
    setValues(EMPTY_ADD_PATIENT_FORM)
    setErrors({})
    setAcknowledgeDuplicate(false)
    setDuplicateCandidates([])
    setDuplicateOpen(false)
    setSubmitting(false)
  }, [])

  useEffect(() => {
    if (!open) {
      resetForm()
    }
  }, [open, resetForm])

  const updateField = <K extends keyof AddPatientFormValues>(
    key: K,
    value: AddPatientFormValues[K],
  ) => {
    setValues((prev) => ({ ...prev, [key]: value }))
    if (errors[key]) {
      setErrors((prev) => {
        const next = { ...prev }
        delete next[key]
        return next
      })
    }
    if (acknowledgeDuplicate) {
      setAcknowledgeDuplicate(false)
    }
  }

  const completeRegistration = async () => {
    setSubmitting(true)
    await new Promise((resolve) => window.setTimeout(resolve, 600))

    const mockPatientId = `pat-new-${Date.now()}`
    toast({
      variant: 'success',
      message: `${values.fullName.trim()} registered at ${MOCK_BRANCH_NAME}.`,
    })

    setSubmitting(false)
    onOpenChange(false)
    onSuccess?.(mockPatientId)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    const nextErrors = validateAddPatientForm(values)
    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }

    const candidates = findPatientDuplicates(values)
    if (candidates.length > 0 && !acknowledgeDuplicate) {
      setDuplicateCandidates(candidates)
      setDuplicateOpen(true)
      return
    }

    await completeRegistration()
  }

  const handleRegisterAnyway = async () => {
    setAcknowledgeDuplicate(true)
    setDuplicateOpen(false)
    await completeRegistration()
  }

  const handleOpenExistingPatient = (patientId: string) => {
    setDuplicateOpen(false)
    onOpenChange(false)
    onSuccess?.(patientId)
  }

  const trimmedName = values.fullName.trim()
  const showPreview = trimmedName.length >= 2
  const reducedMotion = getReducedMotion()

  return {
    formId,
    values,
    errors,
    submitting,
    duplicateOpen,
    duplicateCandidates,
    setDuplicateOpen,
    updateField,
    handleSubmit,
    handleRegisterAnyway,
    handleOpenExistingPatient,
    trimmedName,
    showPreview,
    reducedMotion,
  }
}
