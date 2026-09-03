import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import type { ToastItem } from '@/components/ToastStack'
import { loadDevConfig, resetPlatform } from '@/lib/dev-api'
import { resolveSupabaseAdminFromDevConfig } from '@/lib/supabase-admin'
import {
  canDecreaseTextScale,
  canIncreaseTextScale,
  rootFontSizePx,
  TEXT_SCALE_DEFAULT_LEVEL,
} from '@/lib/text-scale'
import { mintAatFromSupabase } from '@/lib/mint-aat'
import {
  pathForSection,
  sectionFromPath,
} from '@/lib/routes'
import type { NavSection } from '@/types'

interface SessionContextValue {
  activeSection: NavSection
  setActiveSection: (section: NavSection) => void
  operatorBearer: string
  operatorSource: string
  supabaseAdminUsername: string
  supabaseAdminPassword: string
  supabaseAdminSource: string
  supabaseAdminUsernameRevealed: boolean
  supabaseAdminPasswordRevealed: boolean
  setSupabaseAdminUsernameRevealed: (revealed: boolean) => void
  setSupabaseAdminPasswordRevealed: (revealed: boolean) => void
  aat: string
  operatorRevealed: boolean
  aatRevealed: boolean
  setOperatorRevealed: (revealed: boolean) => void
  setAatRevealed: (revealed: boolean) => void
  toasts: ToastItem[]
  dismissToast: (id: string) => void
  notifySuccess: (message: string) => void
  notifyError: (message: string) => void
  busyAction: 'reset' | 'mint' | null
  mintAat: () => Promise<void>
  storeClinicAat: (token: string) => void
  resetAll: () => Promise<void>
  textScaleLevel: number
  increaseTextSize: () => void
  decreaseTextSize: () => void
  canIncreaseTextSize: boolean
  canDecreaseTextSize: boolean
}

const SessionContext = createContext<SessionContextValue | null>(null)

function createToastId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [activeSection, setActiveSectionState] = useState<NavSection>(() =>
    sectionFromPath(window.location.pathname),
  )
  const [operatorBearer, setOperatorBearer] = useState('')
  const [operatorSource, setOperatorSource] = useState('')
  const [supabaseAdminUsername, setSupabaseAdminUsername] = useState('')
  const [supabaseAdminPassword, setSupabaseAdminPassword] = useState('')
  const [supabaseAdminSource, setSupabaseAdminSource] = useState('')
  const [supabaseAdminUsernameRevealed, setSupabaseAdminUsernameRevealed] =
    useState(false)
  const [supabaseAdminPasswordRevealed, setSupabaseAdminPasswordRevealed] =
    useState(false)
  const [aat, setAat] = useState('')
  const [operatorRevealed, setOperatorRevealed] = useState(false)
  const [aatRevealed, setAatRevealed] = useState(false)
  const [toasts, setToasts] = useState<ToastItem[]>([])
  const [busyAction, setBusyAction] = useState<'reset' | 'mint' | null>(null)
  const [textScaleLevel, setTextScaleLevel] = useState(TEXT_SCALE_DEFAULT_LEVEL)
  const startupMintDone = useRef(false)
  const operationLock = useRef(false)

  const setActiveSection = useCallback((section: NavSection) => {
    const path = pathForSection(section)
    if (window.location.pathname !== path) {
      window.history.pushState(null, '', path)
    }
    setActiveSectionState(section)
  }, [])

  useEffect(() => {
    const expectedPath = pathForSection(
      sectionFromPath(window.location.pathname),
    )
    if (window.location.pathname !== expectedPath) {
      window.history.replaceState(null, '', expectedPath)
      setActiveSectionState(sectionFromPath(expectedPath))
    }
  }, [])

  useEffect(() => {
    const onPopState = () => {
      setActiveSectionState(sectionFromPath(window.location.pathname))
    }
    window.addEventListener('popstate', onPopState)
    return () => window.removeEventListener('popstate', onPopState)
  }, [])

  useEffect(() => {
    document.documentElement.style.fontSize = rootFontSizePx(textScaleLevel)
  }, [textScaleLevel])

  const increaseTextSize = useCallback(() => {
    setTextScaleLevel((level) =>
      canIncreaseTextScale(level) ? level + 1 : level,
    )
  }, [])

  const decreaseTextSize = useCallback(() => {
    setTextScaleLevel((level) =>
      canDecreaseTextScale(level) ? level - 1 : level,
    )
  }, [])

  useEffect(() => {
    loadDevConfig()
      .then((config) => {
        setOperatorBearer(config.operatorBearerToken)
        setOperatorSource(config.devVarsPath)
        const admin = resolveSupabaseAdminFromDevConfig(config)
        setSupabaseAdminUsername(admin.username)
        setSupabaseAdminPassword(admin.password)
        setSupabaseAdminSource(admin.source)
      })
      .catch((error: Error) => {
        setToasts((current) => [
          ...current,
          { id: createToastId(), message: error.message, variant: 'error' },
        ])
      })
  }, [])

  const dismissToast = useCallback((id: string) => {
    setToasts((current) => current.filter((toast) => toast.id !== id))
  }, [])

  const notifySuccess = useCallback((message: string) => {
    setToasts((current) => [
      ...current,
      { id: createToastId(), message, variant: 'ok' },
    ])
  }, [])

  const notifyError = useCallback((message: string) => {
    setToasts((current) => [
      ...current,
      { id: createToastId(), message, variant: 'error' },
    ])
  }, [])

  const runMint = useCallback(
    async (
      source: 'manual' | 'auto' | 'reset',
      options?: { manageBusy?: boolean },
    ): Promise<boolean> => {
      const manageBusy = options?.manageBusy ?? true

      if (!operatorBearer) {
        if (source === 'manual') {
          notifyError(
            'Operator bearer not loaded. Open Secrets or check ai-platform/.dev.vars.',
          )
        }
        return false
      }

      if (!supabaseAdminUsername || !supabaseAdminPassword) {
        if (source === 'manual') {
          notifyError(
            'Supabase admin credentials not loaded. Open Secrets or set VITE_BOOTSTRAP_ADMIN_* in .env.local.',
          )
        }
        return false
      }

      if (manageBusy) {
        if (operationLock.current) {
          if (source === 'manual') {
            notifyError('Another operation is already in progress.')
          }
          return false
        }
        operationLock.current = true
        setBusyAction('mint')
      }

      try {
        const { token, aatVer } = await mintAatFromSupabase(operatorBearer, {
          username: supabaseAdminUsername,
          password: supabaseAdminPassword,
        })
        setAat(token)
        setAatRevealed(true)
        if (source === 'manual') {
          notifySuccess(
            `Minted AAT (ver=${aatVer}) and synced platform enrollment + token_contract.`,
          )
        } else if (source === 'auto') {
          notifySuccess(`Minted clinic AAT (ver=${aatVer}).`)
        }
        return true
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Mint failed'
        if (source !== 'reset') {
          notifyError(message)
        }
        return false
      } finally {
        if (manageBusy) {
          operationLock.current = false
          setBusyAction(null)
        }
      }
    },
    [operatorBearer, supabaseAdminUsername, supabaseAdminPassword, notifyError, notifySuccess],
  )

  const mintAat = useCallback(async () => {
    await runMint('manual')
  }, [runMint])

  const storeClinicAat = useCallback((token: string) => {
    setAat(token)
    setAatRevealed(true)
  }, [])

  const resetAll = useCallback(async () => {
    if (operationLock.current) {
      notifyError('Another operation is already in progress.')
      return
    }

    operationLock.current = true
    setBusyAction('reset')
    try {
      const result = await resetPlatform()
      setAat('')
      const minted = await runMint('reset', { manageBusy: false })
      if (minted) {
        notifySuccess(
          `${result.steps.join(' · ')} · Minted fresh clinic AAT after reset.`,
        )
      } else {
        notifyError(
          'Platform reset completed, but clinic AAT mint failed. Use Secrets to retry.',
        )
        notifySuccess(result.steps.join(' · '))
      }
    } catch (error) {
      notifyError(error instanceof Error ? error.message : 'Reset failed')
    } finally {
      operationLock.current = false
      setBusyAction(null)
    }
  }, [notifyError, notifySuccess, runMint])

  useEffect(() => {
    if (
      !operatorBearer ||
      !supabaseAdminUsername ||
      !supabaseAdminPassword ||
      startupMintDone.current
    ) {
      return
    }

    startupMintDone.current = true
    void runMint('auto')
  }, [operatorBearer, supabaseAdminUsername, supabaseAdminPassword, runMint])

  const value = useMemo<SessionContextValue>(
    () => ({
      activeSection,
      setActiveSection,
      operatorBearer,
      operatorSource,
      supabaseAdminUsername,
      supabaseAdminPassword,
      supabaseAdminSource,
      supabaseAdminUsernameRevealed,
      supabaseAdminPasswordRevealed,
      setSupabaseAdminUsernameRevealed,
      setSupabaseAdminPasswordRevealed,
      aat,
      operatorRevealed,
      aatRevealed,
      setOperatorRevealed,
      setAatRevealed,
      toasts,
      dismissToast,
      notifySuccess,
      notifyError,
      busyAction,
      mintAat,
      storeClinicAat,
      resetAll,
      textScaleLevel,
      increaseTextSize,
      decreaseTextSize,
      canIncreaseTextSize: canIncreaseTextScale(textScaleLevel),
      canDecreaseTextSize: canDecreaseTextScale(textScaleLevel),
    }),
    [
      activeSection,
      operatorBearer,
      operatorSource,
      supabaseAdminUsername,
      supabaseAdminPassword,
      supabaseAdminSource,
      supabaseAdminUsernameRevealed,
      supabaseAdminPasswordRevealed,
      aat,
      operatorRevealed,
      aatRevealed,
      toasts,
      busyAction,
      mintAat,
      storeClinicAat,
      resetAll,
      dismissToast,
      notifySuccess,
      notifyError,
      textScaleLevel,
      increaseTextSize,
      decreaseTextSize,
    ],
  )

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  )
}

export function useSession(): SessionContextValue {
  const context = useContext(SessionContext)
  if (!context) {
    throw new Error('useSession must be used within SessionProvider')
  }
  return context
}
