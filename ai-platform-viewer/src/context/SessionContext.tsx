import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { ToastItem } from '@/components/ToastStack'
import { loadDevConfig } from '@/lib/dev-api'
import {
  importIssuerPrivateKey,
  mintIssuerToken,
  type IssuerKeyMaterial,
  type IssuerTokenClaims,
} from '@/lib/issuer-token'
import { resolveSupabaseAdminFromDevConfig } from '@/lib/supabase-admin'
import {
  canDecreaseTextScale,
  canIncreaseTextScale,
  rootFontSizePx,
  TEXT_SCALE_DEFAULT_LEVEL,
} from '@/lib/text-scale'
import { pathForSection, sectionFromPath } from '@/lib/routes'
import type { NavSection } from '@/types'

interface SessionContextValue {
  activeSection: NavSection
  setActiveSection: (section: NavSection) => void
  issuerKey: IssuerKeyMaterial | null
  issuerKeySource: string
  mintIssuerTokenForRequest: (claims?: IssuerTokenClaims) => Promise<string>
  supabaseAdminUsername: string
  supabaseAdminPassword: string
  supabaseAdminSource: string
  supabaseAdminUsernameRevealed: boolean
  supabaseAdminPasswordRevealed: boolean
  setSupabaseAdminUsernameRevealed: (revealed: boolean) => void
  setSupabaseAdminPasswordRevealed: (revealed: boolean) => void
  toasts: ToastItem[]
  dismissToast: (id: string) => void
  notifySuccess: (message: string) => void
  notifyError: (message: string) => void
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
  const [issuerKey, setIssuerKey] = useState<IssuerKeyMaterial | null>(null)
  const [issuerKeySource, setIssuerKeySource] = useState('')
  const [supabaseAdminUsername, setSupabaseAdminUsername] = useState('')
  const [supabaseAdminPassword, setSupabaseAdminPassword] = useState('')
  const [supabaseAdminSource, setSupabaseAdminSource] = useState('')
  const [supabaseAdminUsernameRevealed, setSupabaseAdminUsernameRevealed] =
    useState(false)
  const [supabaseAdminPasswordRevealed, setSupabaseAdminPasswordRevealed] =
    useState(false)
  const [toasts, setToasts] = useState<ToastItem[]>([])
  const [textScaleLevel, setTextScaleLevel] = useState(TEXT_SCALE_DEFAULT_LEVEL)

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
      .then(async (config) => {
        setIssuerKeySource(config.devVarsPath)
        const kid = config.testIssuerKid?.trim()
        const pkcs8 = config.testIssuerPrivateKeyPkcs8?.trim()
        if (kid && pkcs8) {
          setIssuerKey(await importIssuerPrivateKey(kid, pkcs8))
        } else {
          setIssuerKey(null)
        }

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

  const mintIssuerTokenForRequest = useCallback(
    async (claims: IssuerTokenClaims = {}): Promise<string> => {
      if (!issuerKey) {
        throw new Error(
          'Test issuer key not loaded. Check TEST_ISSUER_KID and TEST_ISSUER_PRIVATE_KEY_PKCS8 in ai-platform/.dev.vars.',
        )
      }
      return mintIssuerToken(issuerKey, claims)
    },
    [issuerKey],
  )

  const value = useMemo<SessionContextValue>(
    () => ({
      activeSection,
      setActiveSection,
      issuerKey,
      issuerKeySource,
      mintIssuerTokenForRequest,
      supabaseAdminUsername,
      supabaseAdminPassword,
      supabaseAdminSource,
      supabaseAdminUsernameRevealed,
      supabaseAdminPasswordRevealed,
      setSupabaseAdminUsernameRevealed,
      setSupabaseAdminPasswordRevealed,
      toasts,
      dismissToast,
      notifySuccess,
      notifyError,
      textScaleLevel,
      increaseTextSize,
      decreaseTextSize,
      canIncreaseTextSize: canIncreaseTextScale(textScaleLevel),
      canDecreaseTextSize: canDecreaseTextScale(textScaleLevel),
    }),
    [
      activeSection,
      issuerKey,
      issuerKeySource,
      mintIssuerTokenForRequest,
      supabaseAdminUsername,
      supabaseAdminPassword,
      supabaseAdminSource,
      supabaseAdminUsernameRevealed,
      supabaseAdminPasswordRevealed,
      toasts,
      dismissToast,
      notifySuccess,
      notifyError,
      textScaleLevel,
      increaseTextSize,
      decreaseTextSize,
      setActiveSection,
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
