import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'

export type Direction = 'ltr' | 'rtl'
export type Locale = 'en' | 'ar'

type DirectionContextValue = {
  direction: Direction
  locale: Locale
  setDirection: (direction: Direction) => void
  setLocale: (locale: Locale) => void
  toggleDirection: () => void
}

const DirectionContext = createContext<DirectionContextValue | null>(null)

const STORAGE_KEY = 'aiclinic-direction'
const LOCALE_KEY = 'aiclinic-locale'

function getInitialDirection(): Direction {
  if (typeof window === 'undefined') return 'ltr'
  const stored = localStorage.getItem(STORAGE_KEY) as Direction | null
  return stored === 'rtl' ? 'rtl' : 'ltr'
}

function getInitialLocale(): Locale {
  if (typeof window === 'undefined') return 'en'
  const stored = localStorage.getItem(LOCALE_KEY) as Locale | null
  return stored === 'ar' ? 'ar' : 'en'
}

export function DirectionProvider({ children }: { children: ReactNode }) {
  const [direction, setDirectionState] = useState<Direction>(getInitialDirection)
  const [locale, setLocaleState] = useState<Locale>(getInitialLocale)

  const setDirection = useCallback((next: Direction) => {
    setDirectionState(next)
    localStorage.setItem(STORAGE_KEY, next)
    setLocaleState(next === 'rtl' ? 'ar' : 'en')
    localStorage.setItem(LOCALE_KEY, next === 'rtl' ? 'ar' : 'en')
  }, [])

  const setLocale = useCallback((next: Locale) => {
    setLocaleState(next)
    localStorage.setItem(LOCALE_KEY, next)
    const dir: Direction = next === 'ar' ? 'rtl' : 'ltr'
    setDirectionState(dir)
    localStorage.setItem(STORAGE_KEY, dir)
  }, [])

  const toggleDirection = useCallback(() => {
    setDirection(direction === 'ltr' ? 'rtl' : 'ltr')
  }, [direction, setDirection])

  useEffect(() => {
    const root = document.documentElement
    root.dir = direction
    root.lang = locale
    root.style.setProperty(
      '--motion-inline-start',
      direction === 'rtl' ? '-12px' : '12px',
    )
    root.style.setProperty(
      '--motion-drawer-offset',
      direction === 'rtl' ? '-100%' : '100%',
    )
  }, [direction, locale])

  const value = useMemo(
    () => ({ direction, locale, setDirection, setLocale, toggleDirection }),
    [direction, locale, setDirection, setLocale, toggleDirection],
  )

  return (
    <DirectionContext.Provider value={value}>{children}</DirectionContext.Provider>
  )
}

export function useDirection() {
  const ctx = useContext(DirectionContext)
  if (!ctx) throw new Error('useDirection must be used within DirectionProvider')
  return ctx
}
