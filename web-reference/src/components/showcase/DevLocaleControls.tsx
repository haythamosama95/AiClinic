import { Languages } from 'lucide-react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { Switch } from '@/components/ui/switch/Switch'
import { useDensity, type Density } from '@/providers/DensityProvider'
import { useDirection, type Direction, type Locale } from '@/providers/DirectionProvider'
import { useCallback, useEffect, useState } from 'react'

const DIRECTION_OPTIONS: { value: Direction; label: string }[] = [
  { value: 'ltr', label: 'LTR' },
  { value: 'rtl', label: 'RTL' },
]

const LOCALE_OPTIONS: { value: Locale; label: string }[] = [
  { value: 'en', label: 'EN' },
  { value: 'ar', label: 'AR' },
]

type DevDensity = 'compact' | 'comfortable'

const DENSITY_OPTIONS: { value: DevDensity; label: string }[] = [
  { value: 'compact', label: 'Compact' },
  { value: 'comfortable', label: 'Comfortable' },
]

function toDevDensity(density: Density): DevDensity {
  return density === 'compact' ? 'compact' : 'comfortable'
}

export function DevLocaleControls() {
  const { direction, locale, setDirection, setLocale } = useDirection()
  const { density, setDensity } = useDensity()
  const [reducedMotion, setReducedMotion] = useState(
    () => document.documentElement.dataset.reducedMotion === 'true',
  )

  const toggleReducedMotion = useCallback((on: boolean) => {
    setReducedMotion(on)
    document.documentElement.dataset.reducedMotion = String(on)
  }, [])

  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    const sync = () => {
      if (mq.matches) toggleReducedMotion(true)
    }
    sync()
    mq.addEventListener('change', sync)
    return () => mq.removeEventListener('change', sync)
  }, [toggleReducedMotion])

  return (
    <div className="flex flex-wrap items-center gap-4 rounded-lg border border-border-default bg-surface-default p-4">
      <div className="flex min-w-0 items-center gap-2">
        <Languages size={16} strokeWidth={1.5} className="shrink-0 text-icon-muted" aria-hidden />
        <p className="text-body-sm text-text-secondary">Preview theming</p>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <SegmentedControl
          aria-label="Shell density"
          size="sm"
          value={toDevDensity(density)}
          onChange={setDensity}
          options={DENSITY_OPTIONS}
        />
        <SegmentedControl
          aria-label="Text direction"
          size="sm"
          value={direction}
          onChange={setDirection}
          options={DIRECTION_OPTIONS}
        />
        <SegmentedControl
          aria-label="Language"
          size="sm"
          value={locale}
          onChange={setLocale}
          options={LOCALE_OPTIONS}
        />
        <label className="flex items-center gap-2 border-s border-border-subtle ps-3">
          <Switch
            checked={reducedMotion}
            onCheckedChange={toggleReducedMotion}
            aria-label="Reduce motion"
          />
          <span className="text-caption text-text-secondary">Reduce motion</span>
        </label>
      </div>
    </div>
  )
}
