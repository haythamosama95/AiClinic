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
import { loadDevConfig, resetPlatform } from '@/lib/dev-api'
import { resolveSupabaseAdminFromDevConfig } from '@/lib/supabase-admin'
import {
  canDecreaseTextScale,
  canIncreaseTextScale,
  rootFontSizePx,
} from '@/lib/text-scale'
import { mintAatFromSupabase } from '@/lib/mint-aat'
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
  statusMessage: string | null
  errorMessage: string | null
  busyAction: 'reset' | 'mint' | null
  mintAat: () => Promise<void>
  resetAll: () => Promise<void>
  clearMessages: () => void
  textScaleLevel: number
  increaseTextSize: () => void
  decreaseTextSize: () => void
  canIncreaseTextSize: boolean
  canDecreaseTextSize: boolean
}

const SessionContext = createContext<SessionContextValue | null>(null)

export function SessionProvider({ children }: { children: ReactNode }) {
  const [activeSection, setActiveSection] = useState<NavSection>('stage-1')
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
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [busyAction, setBusyAction] = useState<'reset' | 'mint' | null>(null)
  const [textScaleLevel, setTextScaleLevel] = useState(0)
  const startupMintDone = useRef(false)

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
        setErrorMessage(error.message)
      })
  }, [])

  const clearMessages = useCallback(() => {
    setStatusMessage(null)
    setErrorMessage(null)
  }, [])

  const runMint = useCallback(
    async (source: 'manual' | 'auto' | 'reset'): Promise<boolean> => {
      if (!operatorBearer) {
        if (source === 'manual') {
          setErrorMessage(
            'Operator bearer not loaded. Open Secrets or check ai-platform/.dev.vars.',
          )
        }
        return false
      }

      if (!supabaseAdminUsername || !supabaseAdminPassword) {
        if (source === 'manual') {
          setErrorMessage(
            'Supabase admin credentials not loaded. Open Secrets or set VITE_BOOTSTRAP_ADMIN_* in .env.local.',
          )
        }
        return false
      }

      setBusyAction('mint')
      try {
        const { token, aatVer } = await mintAatFromSupabase(operatorBearer, {
          username: supabaseAdminUsername,
          password: supabaseAdminPassword,
        })
        setAat(token)
        setAatRevealed(true)
        if (source === 'manual') {
          setStatusMessage(
            `Minted AAT (ver=${aatVer}) and synced platform enrollment + token_contract.`,
          )
        } else if (source === 'auto') {
          setStatusMessage(`Minted clinic AAT (ver=${aatVer}).`)
        }
        return true
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Mint failed'
        if (source !== 'reset') {
          setErrorMessage(message)
        }
        return false
      } finally {
        setBusyAction(null)
      }
    },
    [operatorBearer, supabaseAdminUsername, supabaseAdminPassword],
  )

  const mintAat = useCallback(async () => {
    clearMessages()
    await runMint('manual')
  }, [clearMessages, runMint])

  const resetAll = useCallback(async () => {
    clearMessages()
    setBusyAction('reset')
    try {
      const result = await resetPlatform()
      setAat('')
      const minted = await runMint('reset')
      if (minted) {
        setStatusMessage(
          `${result.steps.join(' · ')} · Minted fresh clinic AAT after reset.`,
        )
      } else {
        setErrorMessage(
          'Platform reset completed, but clinic AAT mint failed. Use Secrets to retry.',
        )
        setStatusMessage(result.steps.join(' · '))
      }
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Reset failed')
    } finally {
      setBusyAction(null)
    }
  }, [clearMessages, runMint])

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
      statusMessage,
      errorMessage,
      busyAction,
      mintAat,
      resetAll,
      clearMessages,
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
      statusMessage,
      errorMessage,
      busyAction,
      mintAat,
      resetAll,
      clearMessages,
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
