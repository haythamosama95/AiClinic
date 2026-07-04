import { Languages } from 'lucide-react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { useDensity, type Density } from '@/providers/DensityProvider'
import { useDirection, type Direction, type Locale } from '@/providers/DirectionProvider'

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
      </div>
    </div>
  )
}
