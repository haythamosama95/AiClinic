import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { createDefaultSetup, type SetupDraft } from '@/data/settings'

const STORAGE_KEY = 'aiclinic:setup-draft'

type SetupContextValue = {
  draft: SetupDraft
  step: number
  completed: boolean
  setStep: (step: number) => void
  updateOrganization: (patch: Partial<SetupDraft['organization']>) => void
  setBranches: (branches: SetupDraft['branches']) => void
  setStaff: (staff: SetupDraft['staff']) => void
  setServices: (services: SetupDraft['services']) => void
  completeSetup: () => void
  resetSetup: () => void
}

const SetupContext = createContext<SetupContextValue | null>(null)

function loadDraft(): SetupDraft {
  if (typeof window === 'undefined') return createDefaultSetup()
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return JSON.parse(raw) as SetupDraft
  } catch {
    /* use default */
  }
  return createDefaultSetup()
}

function persistDraft(draft: SetupDraft) {
  if (typeof window === 'undefined') return
  localStorage.setItem(STORAGE_KEY, JSON.stringify(draft))
}

export function SetupProvider({ children }: { children: ReactNode }) {
  const [draft, setDraft] = useState<SetupDraft>(loadDraft)
  const [step, setStepState] = useState(0)
  const [completed, setCompleted] = useState(false)

  const setStep = useCallback((next: number) => {
    setStepState(Math.max(0, next))
  }, [])

  const updateOrganization = useCallback((patch: Partial<SetupDraft['organization']>) => {
    setDraft((prev) => {
      const next = { ...prev, organization: { ...prev.organization, ...patch } }
      persistDraft(next)
      return next
    })
  }, [])

  const setBranches = useCallback((branches: SetupDraft['branches']) => {
    setDraft((prev) => {
      const next = { ...prev, branches }
      persistDraft(next)
      return next
    })
  }, [])

  const setStaff = useCallback((staff: SetupDraft['staff']) => {
    setDraft((prev) => {
      const next = { ...prev, staff }
      persistDraft(next)
      return next
    })
  }, [])

  const setServices = useCallback((services: SetupDraft['services']) => {
    setDraft((prev) => {
      const next = { ...prev, services }
      persistDraft(next)
      return next
    })
  }, [])

  const completeSetup = useCallback(() => {
    setCompleted(true)
    localStorage.setItem('aiclinic:setup-complete', 'true')
  }, [])

  const resetSetup = useCallback(() => {
    const fresh = createDefaultSetup()
    setDraft(fresh)
    setStepState(0)
    setCompleted(false)
    persistDraft(fresh)
    localStorage.removeItem('aiclinic:setup-complete')
  }, [])

  const value = useMemo(
    () => ({
      draft,
      step,
      completed,
      setStep,
      updateOrganization,
      setBranches,
      setStaff,
      setServices,
      completeSetup,
      resetSetup,
    }),
    [
      draft,
      step,
      completed,
      setStep,
      updateOrganization,
      setBranches,
      setStaff,
      setServices,
      completeSetup,
      resetSetup,
    ],
  )

  return <SetupContext.Provider value={value}>{children}</SetupContext.Provider>
}

export function useSetup() {
  const ctx = useContext(SetupContext)
  if (!ctx) throw new Error('useSetup must be used within SetupProvider')
  return ctx
}

export function isSetupComplete(): boolean {
  if (typeof window === 'undefined') return false
  return localStorage.getItem('aiclinic:setup-complete') === 'true'
}
