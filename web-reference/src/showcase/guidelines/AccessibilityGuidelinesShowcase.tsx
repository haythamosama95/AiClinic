import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Switch } from '@/components/ui/switch/Switch'
import { Kbd } from '@/components/kbd'
import { Signal } from '@/primitives/Signal'
import { ShowcaseSection } from '../ShowcasePrimitives'

const KEYBOARD_MAP = [
  { keys: ['⌘', 'K'], action: 'Open Command Bar' },
  { keys: ['/'], action: 'Focus page search' },
  { keys: ['Esc'], action: 'Close topmost overlay' },
  { keys: ['Tab'], action: 'Move focus forward' },
  { keys: ['Shift', 'Tab'], action: 'Move focus backward' },
  { keys: ['Enter'], action: 'Activate focused control' },
]

const CONTRAST_PAIRS = [
  { token: 'text-primary on surface-default', fg: 'text-text-primary', bg: 'bg-surface-default', ratio: '12.4:1' },
  { token: 'text-secondary on surface-default', fg: 'text-text-secondary', bg: 'bg-surface-default', ratio: '7.1:1' },
  { token: 'action-primary-fg on action-primary', fg: 'text-action-primary-fg', bg: 'bg-action-primary', ratio: '4.8:1' },
  { token: 'text-ai on surface-ai', fg: 'text-text-ai', bg: 'bg-surface-ai', ratio: '5.2:1' },
]

export function AccessibilityGuidelinesShowcase() {
  const [reducedMotion, setReducedMotion] = useState(
    () => document.documentElement.dataset.reducedMotion === 'true',
  )

  const toggleReducedMotion = (on: boolean) => {
    setReducedMotion(on)
    document.documentElement.dataset.reducedMotion = String(on)
  }

  return (
    <>
      <ShowcaseSection
        id="guidelines-focus"
        title="Visible focus"
        componentName="07 §2 Keyboard"
        description="Focus ring is always visible. Tab through this section to see focus-ring on interactive elements."
      >
        <div className="flex flex-wrap gap-3 rounded-lg border border-border-default bg-surface-default p-6">
          <Button variant="primary">Primary</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="ghost">Ghost</Button>
          <a href="#guidelines-contrast" className="focus-ring rounded-md px-3 py-2 text-body-sm text-text-link">
            Skip to contrast
          </a>
        </div>
      </ShowcaseSection>

      <ShowcaseSection
        id="guidelines-contrast"
        title="Contrast"
        componentName="07 §1 Color & contrast"
        description="Semantic token pairs verified for WCAG 2.2 AA in light and dark themes."
      >
        <div className="grid gap-3 sm:grid-cols-2">
          {CONTRAST_PAIRS.map((pair) => (
            <div
              key={pair.token}
              className={`flex items-center justify-between rounded-lg border border-border-subtle p-4 ${pair.bg}`}
            >
              <span className={`text-body-strong ${pair.fg}`}>{pair.token}</span>
              <span className="font-mono text-caption text-text-tertiary">{pair.ratio}</span>
            </div>
          ))}
        </div>
        <p className="mt-4 text-body-sm text-text-secondary">
          Status always pairs color with text and/or icon — never color alone.
        </p>
      </ShowcaseSection>

      <ShowcaseSection
        id="guidelines-keyboard"
        title="Keyboard map"
        componentName="07 §2 Shortcuts"
        description="Discoverable shortcuts that never replace mouse/touch paths."
      >
        <div className="overflow-hidden rounded-lg border border-border-default">
          <table className="w-full text-body-sm">
            <thead>
              <tr className="border-b border-border-subtle bg-surface-sunken text-start">
                <th className="px-4 py-2 font-medium text-text-secondary">Shortcut</th>
                <th className="px-4 py-2 font-medium text-text-secondary">Action</th>
              </tr>
            </thead>
            <tbody>
              {KEYBOARD_MAP.map((row) => (
                <tr key={row.action} className="border-b border-border-subtle last:border-0">
                  <td className="px-4 py-3">
                    <Kbd keys={row.keys} />
                  </td>
                  <td className="px-4 py-3 text-text-primary">{row.action}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </ShowcaseSection>

      <ShowcaseSection
        id="guidelines-reduced-motion"
        title="Reduced motion"
        componentName="07 §4 Motion"
        description="Honors OS setting plus manual override. Loops and shimmer stop under reduced motion."
      >
        <div className="flex flex-wrap items-center gap-6 rounded-lg border border-border-default bg-surface-default p-6">
          <label className="flex items-center gap-3">
            <Switch
              checked={reducedMotion}
              onCheckedChange={toggleReducedMotion}
              aria-label="Reduce motion"
            />
            <span className="text-body text-text-primary">Reduce motion</span>
          </label>
          <div className="flex items-center gap-4">
            <div className="text-center">
              <p className="mb-2 text-caption text-text-tertiary">Teal (deterministic)</p>
              <Signal variant="standard" active thinking={!reducedMotion} />
            </div>
            <div className="text-center">
              <p className="mb-2 text-caption text-text-tertiary">Violet (AI)</p>
              <Signal variant="ai" active thinking={!reducedMotion} />
            </div>
          </div>
        </div>
        <p className="mt-4 text-body-sm text-text-secondary">
          Under reduced motion: pulse stops, drawer blur disabled, skeleton shimmer static.
        </p>
      </ShowcaseSection>

      <ShowcaseSection
        id="guidelines-ai-a11y"
        title="AI accessibility"
        componentName="07 §6 AI-specific"
        description="AI distinction conveyed by label and text, not violet color alone."
      >
        <ul className="list-disc space-y-2 ps-5 text-body text-text-secondary">
          <li>Proposed Action Cards are fully keyboard operable with named Approve / Edit / Dismiss buttons.</li>
          <li>Streaming responses use polite live regions — not per-token announcements.</li>
          <li>&quot;Proposed by AI&quot; label is always visible on actionable AI output.</li>
          <li>Human approval is required before any write — never implied by AI copy alone.</li>
        </ul>
      </ShowcaseSection>

      <ShowcaseSection
        id="guidelines-i18n"
        title="Internationalization"
        componentName="07 §7 i18n"
        description="Use Dev controls above to verify EN/LTR and AR/RTL."
      >
        <ul className="list-disc space-y-2 ps-5 text-body text-text-secondary">
          <li>Logical properties mirror layout and directional icons in RTL.</li>
          <li>Arabic uses IBM Plex Sans Arabic with adjusted line-height.</li>
          <li>Components tolerate text expansion without clipping.</li>
          <li>Money and dates use locale-aware formatting with Western digits.</li>
        </ul>
      </ShowcaseSection>
    </>
  )
}
