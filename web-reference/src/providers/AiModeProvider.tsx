import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react'

type AiModeContextValue = {
  aiMode: boolean
  setAiMode: (enabled: boolean) => void
  toggleAiMode: () => void
}

const AiModeContext = createContext<AiModeContextValue | null>(null)

export function AiModeProvider({ children }: { children: ReactNode }) {
  const [aiMode, setAiModeState] = useState(false)

  const setAiMode = useCallback((enabled: boolean) => {
    setAiModeState(enabled)
  }, [])

  const toggleAiMode = useCallback(() => {
    setAiModeState((prev) => !prev)
  }, [])

  const value = useMemo(
    () => ({ aiMode, setAiMode, toggleAiMode }),
    [aiMode, setAiMode, toggleAiMode],
  )

  return <AiModeContext.Provider value={value}>{children}</AiModeContext.Provider>
}

export function useAiMode() {
  const ctx = useContext(AiModeContext)
  if (!ctx) throw new Error('useAiMode must be used within AiModeProvider')
  return ctx
}
