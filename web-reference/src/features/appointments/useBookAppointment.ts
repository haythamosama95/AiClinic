import { useCallback, useEffect, useMemo, useState } from 'react'
import { useToast } from '@/components/toast/Toast'
import { MOCK_PATIENTS, patientFullName } from '@/data/patients'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import {
  APPOINTMENT_BRANCHES,
  doctorsForBranch,
  getBranchById,
  getDoctorById,
  SLOT_LABELS,
} from './mock-data'
import {
  addDaysIso,
  formatFullDate,
  getSlotsForDay,
  resolveAssignedDoctor,
} from './slot-availability'
import type { BookAppointmentDraft } from './types'

const EMPTY_DRAFT: BookAppointmentDraft = {
  patientId: null,
  branchId: null,
  preferredDoctorId: null,
  date: null,
  time: null,
}

export type UseBookAppointmentOptions = {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess?: () => void
}

export function useBookAppointment({ open, onOpenChange, onSuccess }: UseBookAppointmentOptions) {
  const { toast } = useToast()
  const [step, setStep] = useState(0)
  const [draft, setDraft] = useState<BookAppointmentDraft>(EMPTY_DRAFT)
  const [submitting, setSubmitting] = useState(false)
  const [errors, setErrors] = useState<Partial<Record<'patient' | 'branch' | 'date' | 'time', string>>>({})

  const todayIso = useMemo(() => new Date().toISOString().slice(0, 10), [])

  useEffect(() => {
    if (!open) {
      setStep(0)
      setDraft(EMPTY_DRAFT)
      setErrors({})
      setSubmitting(false)
    }
  }, [open])

  const patientItems: ComboboxItem[] = useMemo(
    () =>
      MOCK_PATIENTS.filter((p) => p.status === 'active').map((p) => ({
        id: p.id,
        label: patientFullName(p),
        meta: p.mrn,
        initials: `${p.firstName[0]}${p.lastName[0]}`,
      })),
    [],
  )

  const branchOptions = useMemo(
    () =>
      APPOINTMENT_BRANCHES.filter((b) => b.isActive).map((b) => ({
        value: b.id,
        label: b.name,
      })),
    [],
  )

  const doctorOptions = useMemo(() => {
    if (!draft.branchId) return []
    const doctors = doctorsForBranch(draft.branchId)
    return [
      { value: '', label: 'Any available doctor' },
      ...doctors.map((d) => ({ value: d.id, label: d.fullName })),
    ]
  }, [draft.branchId])

  const dayOptions = useMemo(() => {
    return Array.from({ length: 14 }, (_, i) => {
      const iso = addDaysIso(todayIso, i)
      return iso
    })
  }, [todayIso])

  const slots = useMemo(() => {
    if (!draft.branchId || !draft.date) return []
    return getSlotsForDay(draft.branchId, draft.date, draft.preferredDoctorId)
  }, [draft.branchId, draft.date, draft.preferredDoctorId])

  const selectedPatient = patientItems.find((p) => p.id === draft.patientId) ?? null

  const updateDraft = useCallback((patch: Partial<BookAppointmentDraft>) => {
    setDraft((prev) => {
      const next = { ...prev, ...patch }
      if (patch.branchId !== undefined && patch.branchId !== prev.branchId) {
        next.preferredDoctorId = null
        next.date = null
        next.time = null
      }
      if (patch.preferredDoctorId !== undefined) {
        next.time = null
      }
      if (patch.date !== undefined) {
        next.time = null
      }
      return next
    })
    setErrors({})
  }, [])

  const validateStep1 = useCallback(() => {
    const next: typeof errors = {}
    if (!draft.patientId) next.patient = 'Select a patient to continue.'
    if (!draft.branchId) next.branch = 'Select a branch to continue.'
    setErrors(next)
    return Object.keys(next).length === 0
  }, [draft.patientId, draft.branchId])

  const validateStep2 = useCallback(() => {
    const next: typeof errors = {}
    if (!draft.date) next.date = 'Pick a day for the appointment.'
    if (!draft.time) next.time = 'Choose an available time slot.'
    setErrors(next)
    return Object.keys(next).length === 0
  }, [draft.date, draft.time])

  const goNext = useCallback(() => {
    if (step === 0 && validateStep1()) {
      if (!draft.date) updateDraft({ date: todayIso })
      setStep(1)
    }
  }, [step, validateStep1, draft.date, todayIso, updateDraft])

  const goBack = useCallback(() => {
    setStep((s) => Math.max(0, s - 1))
    setErrors({})
  }, [])

  const handleConfirm = useCallback(async () => {
    if (!validateStep2() || !draft.branchId || !draft.date || !draft.time || !draft.patientId) return

    const slot = slots.find((s) => s.time === draft.time)
    if (!slot || slot.status === 'locked') {
      setErrors({ time: 'This slot is no longer available.' })
      return
    }

    const doctorId = resolveAssignedDoctor(slot, draft.preferredDoctorId)
    const patient = MOCK_PATIENTS.find((p) => p.id === draft.patientId)
    const doctor = doctorId ? getDoctorById(doctorId) : undefined
    const branch = getBranchById(draft.branchId)

    setSubmitting(true)
    await new Promise((r) => setTimeout(r, 600))
    setSubmitting(false)

    toast({
      variant: 'success',
      message: `Appointment booked for ${patient ? patientFullName(patient) : 'patient'} on ${formatFullDate(draft.date)} at ${SLOT_LABELS[draft.time as keyof typeof SLOT_LABELS]} with ${doctor?.fullName ?? 'a doctor'} · ${branch?.name ?? 'branch'}.`,
    })

    onOpenChange(false)
    onSuccess?.()
  }, [validateStep2, draft, slots, toast, onOpenChange, onSuccess])

  return {
    step,
    draft,
    errors,
    submitting,
    patientItems,
    branchOptions,
    doctorOptions,
    dayOptions,
    slots,
    selectedPatient,
    todayIso,
    updateDraft,
    goNext,
    goBack,
    handleConfirm,
    preferredDoctor: draft.preferredDoctorId
      ? getDoctorById(draft.preferredDoctorId)
      : null,
    branch: draft.branchId ? getBranchById(draft.branchId) : null,
    hasPreferredDoctor: Boolean(draft.preferredDoctorId),
    doctorCount: draft.branchId ? doctorsForBranch(draft.branchId).length : 0,
  }
}
