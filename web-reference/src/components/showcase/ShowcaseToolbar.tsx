import { Languages, Moon, Sun } from 'lucide-react'
import { useTheme } from '@/providers/ThemeProvider'
import { useDirection } from '@/providers/DirectionProvider'

export function ShowcaseToolbar() {
  const { theme, toggleTheme } = useTheme()
  const { direction, toggleDirection } = useDirection()

  return (
    <div className="flex flex-wrap items-center gap-2">
      <button
        type="button"
        onClick={toggleTheme}
        className="focus-ring inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-default px-3 py-2 text-body-strong text-text-primary transition-colors hover:bg-surface-hover"
        aria-label={theme === 'light' ? 'Switch to dark theme' : 'Switch to light theme'}
      >
        {theme === 'light' ? <Moon size={16} strokeWidth={1.5} /> : <Sun size={16} strokeWidth={1.5} />}
        <span>{theme === 'light' ? 'Dark' : 'Light'}</span>
      </button>
      <button
        type="button"
        onClick={toggleDirection}
        className="focus-ring inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-default px-3 py-2 text-body-strong text-text-primary transition-colors hover:bg-surface-hover"
        aria-label={direction === 'ltr' ? 'Switch to RTL' : 'Switch to LTR'}
      >
        <Languages size={16} strokeWidth={1.5} />
        <span>{direction === 'ltr' ? 'العربية' : 'English'}</span>
      </button>
    </div>
  )
}
