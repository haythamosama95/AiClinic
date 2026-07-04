import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'

export type Density = 'compact' | 'default' | 'comfortable'

type DensityContextValue = {
  density: Density
  setDensity: (density: Density) => void
}

const DensityContext = createContext<DensityContextValue | null>(null)

const STORAGE_KEY = 'aiclinic-density'

function getInitialDensity(): Density {
  if (typeof window === 'undefined') return 'default'
  const stored = localStorage.getItem(STORAGE_KEY) as Density | null
  if (stored === 'compact' || stored === 'default' || stored === 'comfortable') return stored
  return 'default'
}

export function DensityProvider({ children }: { children: ReactNode }) {
  const [density, setDensityState] = useState<Density>(getInitialDensity)

  const setDensity = useCallback((next: Density) => {
    setDensityState(next)
    localStorage.setItem(STORAGE_KEY, next)
  }, [])

  useEffect(() => {
    document.documentElement.dataset.density = density
  }, [density])

  const value = useMemo(() => ({ density, setDensity }), [density, setDensity])

  return <DensityContext.Provider value={value}>{children}</DensityContext.Provider>
}

export function useDensity() {
  const ctx = useContext(DensityContext)
  if (!ctx) throw new Error('useDensity must be used within DensityProvider')
  return ctx
}
