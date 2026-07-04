import { Languages, Moon, Sparkles, Sun } from 'lucide-react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { useAiMode } from '@/providers/AiModeProvider'
import { useDensity, type Density } from '@/providers/DensityProvider'
import { useDirection } from '@/providers/DirectionProvider'
import { useTheme } from '@/providers/ThemeProvider'

const DENSITY_OPTIONS: { value: Density; label: string }[] = [
  { value: 'compact', label: 'Compact' },
  { value: 'default', label: 'Default' },
  { value: 'comfortable', label: 'Comfortable' },
]

export function ShowcaseToolbar() {
  const { theme, toggleTheme } = useTheme()
  const { direction, locale, toggleDirection, setLocale } = useDirection()
  const { density, setDensity } = useDensity()
  const { aiMode, toggleAiMode } = useAiMode()

  return (
    <div className="flex flex-wrap items-center gap-2">
      <button
        type="button"
        onClick={toggleTheme}
        className="focus-ring inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-default px-3 py-2 text-body-strong text-text-primary transition-colors hover:bg-surface-hover"
        aria-label={theme === 'light' ? 'Switch to dark theme' : 'Switch to light theme'}
      >
        {theme === 'light' ? <Moon size={16} strokeWidth={1.5} /> : <Sun size={16} strokeWidth={1.5} />}
        <span className="hidden sm:inline">{theme === 'light' ? 'Dark' : 'Light'}</span>
      </button>

      <button
        type="button"
        onClick={toggleDirection}
        className="focus-ring inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-default px-3 py-2 text-body-strong text-text-primary transition-colors hover:bg-surface-hover"
        aria-label={direction === 'ltr' ? 'Switch to RTL' : 'Switch to LTR'}
      >
        <Languages size={16} strokeWidth={1.5} />
        <span className="hidden sm:inline">{direction === 'ltr' ? 'RTL' : 'LTR'}</span>
      </button>

      <button
        type="button"
        onClick={() => setLocale(locale === 'en' ? 'ar' : 'en')}
        className="focus-ring inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-default px-3 py-2 text-body-strong text-text-primary transition-colors hover:bg-surface-hover"
        aria-label={locale === 'en' ? 'Switch to Arabic' : 'Switch to English'}
      >
        <span>{locale === 'en' ? 'EN' : 'AR'}</span>
      </button>

      <SegmentedControl
        aria-label="Density"
        size="sm"
        value={density}
        onChange={setDensity}
        options={DENSITY_OPTIONS.map((o) => ({ value: o.value, label: o.label }))}
        className="hidden md:inline-flex"
      />

      <button
        type="button"
        onClick={toggleAiMode}
        aria-pressed={aiMode}
        className="focus-ring inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-default px-3 py-2 text-body-strong text-text-primary transition-colors hover:bg-surface-hover data-[pressed=true]:border-border-ai data-[pressed=true]:bg-surface-ai data-[pressed=true]:text-text-ai"
        data-pressed={aiMode || undefined}
        aria-label={aiMode ? 'Disable AI mode' : 'Enable AI mode'}
      >
        <Sparkles size={16} strokeWidth={1.5} />
        <span className="hidden sm:inline">{aiMode ? 'AI on' : 'AI off'}</span>
      </button>
    </div>
  )
}
