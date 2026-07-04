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

type CommandBarContextValue = {
  open: boolean
  openCommandBar: () => void
  closeCommandBar: () => void
  toggleCommandBar: () => void
  registerTrigger: (el: HTMLElement | null) => void
  focusTrigger: () => void
}

const CommandBarContext = createContext<CommandBarContextValue | null>(null)

export function CommandBarProvider({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false)
  const triggerRef = useRef<HTMLElement | null>(null)

  const openCommandBar = useCallback(() => setOpen(true), [])
  const closeCommandBar = useCallback(() => setOpen(false), [])
  const toggleCommandBar = useCallback(() => setOpen((prev) => !prev), [])

  const registerTrigger = useCallback((el: HTMLElement | null) => {
    triggerRef.current = el
  }, [])

  const focusTrigger = useCallback(() => {
    triggerRef.current?.focus()
  }, [])

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        toggleCommandBar()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [toggleCommandBar])

  const value = useMemo(
    () => ({
      open,
      openCommandBar,
      closeCommandBar,
      toggleCommandBar,
      registerTrigger,
      focusTrigger,
    }),
    [open, openCommandBar, closeCommandBar, toggleCommandBar, registerTrigger, focusTrigger],
  )

  return <CommandBarContext.Provider value={value}>{children}</CommandBarContext.Provider>
}

export function useCommandBar() {
  const ctx = useContext(CommandBarContext)
  if (!ctx) throw new Error('useCommandBar must be used within CommandBarProvider')
  return ctx
}
