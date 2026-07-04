import { useState } from 'react'
import { motion } from 'motion/react'
import { ShowcaseToolbar } from '@/components/showcase/ShowcaseToolbar'
import { contrastRatio, formatContrast, meetsAA } from '@/lib/contrast'
import {
  motionPresets,
  resolveTransition,
  staggerChildren,
  type MotionPreset,
} from '@/lib/motion'
import { cn } from '@/lib/cn'
import { Signal } from '@/primitives/Signal'
import { useDirection } from '@/providers/DirectionProvider'
import { useTheme } from '@/providers/ThemeProvider'

const COLOR_PAIRS = [
  { label: 'Primary text', fg: '#1A2029', bg: '#FAFBFC', darkFg: '#E6EBF2', darkBg: '#0E1116' },
  { label: 'Secondary text', fg: '#55606D', bg: '#FAFBFC', darkFg: '#A9B4C0', darkBg: '#0E1116' },
  { label: 'Action primary', fg: '#FFFFFF', bg: '#0B7075', darkFg: '#0E1116', darkBg: '#0E8A8F' },
  { label: 'AI action', fg: '#FFFFFF', bg: '#573FD1', darkFg: '#0E1116', darkBg: '#6A54E6' },
  { label: 'Success', fg: '#0F5E34', bg: '#E7F6ED', darkFg: '#5FD495', darkBg: '#0E2A1B' },
  { label: 'Warning', fg: '#855009', bg: '#FBF1DF', darkFg: '#E9B45A', darkBg: '#2E2109' },
  { label: 'Danger', fg: '#9A2828', bg: '#FBECEC', darkFg: '#F08A8A', darkBg: '#2E1414' },
  { label: 'Info', fg: '#164FAB', bg: '#E8F0FE', darkFg: '#7FB0FB', darkBg: '#0F1F3A' },
] as const

const SPACING_TOKENS = [
  '0', 'px', '0.5', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16', '20', '24',
] as const

const RADIUS_TOKENS = ['sm', 'md', 'lg', 'xl', '2xl', 'full'] as const

const ELEVATION_TOKENS = ['0', '1', '2', '3'] as const

const MOTION_PRESET_LIST: MotionPreset[] = [
  'fade',
  'fade-scale',
  'slide-up',
  'slide-inline',
  'modal',
  'command',
  'row-enter',
]

function Section({
  id,
  title,
  description,
  children,
}: {
  id: string
  title: string
  description?: string
  children: React.ReactNode
}) {
  return (
    <section id={id} className="scroll-mt-8">
      <div className="mb-6 border-b border-border-subtle pb-4">
        <h2 className="text-h2 text-text-primary">{title}</h2>
        {description ? (
          <p className="mt-1 text-body text-text-secondary">{description}</p>
        ) : null}
      </div>
      {children}
    </section>
  )
}

function Swatch({
  label,
  className,
  style,
}: {
  label: string
  className?: string
  style?: React.CSSProperties
}) {
  return (
    <div className="flex flex-col gap-2">
      <div
        className={cn('h-14 rounded-lg border border-border-subtle', className)}
        style={style}
      />
      <span className="text-caption text-text-tertiary">{label}</span>
    </div>
  )
}

function ColorSection() {
  const { theme } = useTheme()

  return (
    <Section
      id="colors"
      title="Color"
      description="Semantic pairs with WCAG 2.2 AA contrast verification in both themes."
    >
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {COLOR_PAIRS.map((pair) => {
          const fg = theme === 'light' ? pair.fg : pair.darkFg
          const bg = theme === 'light' ? pair.bg : pair.darkBg
          const ratio = contrastRatio(fg, bg)
          const pass = meetsAA(ratio)
          return (
            <div
              key={pair.label}
              className="overflow-hidden rounded-lg border border-border-default shadow-elevation-1"
            >
              <div
                className="flex h-20 items-center justify-center px-4 text-body-strong"
                style={{ backgroundColor: bg, color: fg }}
              >
                {pair.label}
              </div>
              <div className="flex items-center justify-between bg-surface-default px-3 py-2">
                <span className="text-caption text-text-tertiary">
                  {formatContrast(ratio)}
                </span>
                <span
                  className={cn(
                    'text-caption font-medium',
                    pass ? 'text-status-success-fg' : 'text-status-danger-fg',
                  )}
                >
                  {pass ? 'AA ✓' : 'Fail'}
                </span>
              </div>
            </div>
          )
        })}
      </div>

      <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Swatch label="Canvas" className="bg-surface-canvas" />
        <Swatch label="Default" className="bg-surface-default" />
        <Swatch label="Raised" className="bg-surface-raised shadow-elevation-1" />
        <Swatch label="Sunken" className="bg-surface-sunken" />
        <Swatch label="Muted" className="bg-surface-muted" />
        <Swatch label="Selected" className="bg-surface-selected" />
        <Swatch label="AI surface" className="bg-surface-ai" />
        <Swatch label="Action primary" className="bg-action-primary" />
      </div>
    </Section>
  )
}

function TypographySection() {
  const { locale } = useDirection()
  const isArabic = locale === 'ar'

  const samples = isArabic
    ? {
      display: 'نظام العيادة',
      h1: 'سجل المرضى',
      body: 'تسجيل مريض جديد وإدارة المواعيد والفواتير.',
      mono: 'INV-2026-00482',
      data: '١٬٢٥٠٫٠٠ ج.م',
    }
    : {
      display: 'Clinic Console',
      h1: 'Patient Registry',
      body: 'Register patients, manage appointments, and issue invoices.',
      mono: 'INV-2026-00482',
      data: 'EGP 1,250.00',
    }

  return (
    <Section
      id="typography"
      title="Typography"
      description="Inter + Geist for Latin; IBM Plex Sans Arabic on :lang(ar). Tabular nums for data."
    >
      <div className="space-y-6 rounded-lg border border-border-default bg-surface-default p-6">
        <div>
          <p className="text-overline text-text-tertiary mb-2">Display LG</p>
          <p className="text-display-lg text-text-primary">{samples.display}</p>
        </div>
        <div>
          <p className="text-overline text-text-tertiary mb-2">H1</p>
          <p className="text-h1 text-text-primary">{samples.h1}</p>
        </div>
        <div>
          <p className="text-overline text-text-tertiary mb-2">Body</p>
          <p className="text-body text-text-secondary">{samples.body}</p>
        </div>
        <div>
          <p className="text-overline text-text-tertiary mb-2">Mono / IDs</p>
          <p className="text-mono text-text-primary">{samples.mono}</p>
        </div>
        <div>
          <p className="text-overline text-text-tertiary mb-2">Tabular data</p>
          <div className="flex gap-8 tabular-nums text-h2 text-text-primary">
            <span>{samples.data}</span>
            <span>{isArabic ? '٣٦' : '36'}</span>
            <span>{isArabic ? '١٤:٣٠' : '14:30'}</span>
          </div>
        </div>
      </div>

      <div className="mt-6 grid gap-3 sm:grid-cols-2">
        {(
          [
            ['text-display-lg', '32/40'],
            ['text-display', '28/36'],
            ['text-h1', '24/32'],
            ['text-h2', '20/28'],
            ['text-h3', '18/26'],
            ['text-title', '16/24'],
            ['text-body-lg', '15/24'],
            ['text-body', '14/22'],
            ['text-body-sm', '13/20'],
            ['text-caption', '12/16'],
            ['text-overline', '11/16'],
            ['text-mono', '13/20'],
          ] as const
        ).map(([token, size]) => (
          <div
            key={token}
            className="flex items-baseline justify-between rounded-md border border-border-subtle px-4 py-3"
          >
            <span className={cn(token, 'text-text-primary')}>Aa</span>
            <span className="text-caption text-text-tertiary">
              {token.replace('text-', '')} · {size}
            </span>
          </div>
        ))}
      </div>
    </Section>
  )
}

function SpacingSection() {
  return (
    <Section
      id="spacing"
      title="Spacing, Radius & Elevation"
      description="4px base unit. Elevation is border + soft shadow — kept cheap for low-end hardware."
    >
      <h3 className="text-h3 text-text-primary mb-4">Spacing</h3>
      <div className="flex flex-wrap items-end gap-4">
        {SPACING_TOKENS.map((token) => (
          <div key={token} className="flex flex-col items-center gap-2">
            <div
              className="bg-action-primary rounded-sm"
              style={{ width: `var(--space-${token.replace('.', '-')})`, height: 24 }}
            />
            <span className="text-caption text-text-tertiary">space-{token}</span>
          </div>
        ))}
      </div>

      <h3 className="text-h3 text-text-primary mt-10 mb-4">Radius</h3>
      <div className="grid gap-4 sm:grid-cols-3 lg:grid-cols-6">
        {RADIUS_TOKENS.map((token) => (
          <div key={token} className="flex flex-col items-center gap-2">
            <div
              className="h-16 w-full border-2 border-action-primary bg-surface-muted"
              style={{ borderRadius: `var(--radius-${token})` }}
            />
            <span className="text-caption text-text-tertiary">radius-{token}</span>
          </div>
        ))}
      </div>

      <h3 className="text-h3 text-text-primary mt-10 mb-4">Elevation</h3>
      <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
        {ELEVATION_TOKENS.map((token) => (
          <div
            key={token}
            className="flex h-24 items-center justify-center rounded-lg border border-border-subtle bg-surface-default text-body-strong text-text-secondary"
            style={{ boxShadow: `var(--elevation-${token})` }}
          >
            elevation-{token}
          </div>
        ))}
      </div>
    </Section>
  )
}

function MotionPlayground() {
  const [activePreset, setActivePreset] = useState<MotionPreset>('fade-scale')
  const [key, setKey] = useState(0)
  const preset = motionPresets[activePreset]

  const replay = () => setKey((k) => k + 1)

  return (
    <Section
      id="motion"
      title="Motion"
      description="Presets from 03-motion. Respects prefers-reduced-motion."
    >
      <div className="flex flex-wrap gap-2 mb-6">
        {MOTION_PRESET_LIST.map((name) => (
          <button
            key={name}
            type="button"
            onClick={() => {
              setActivePreset(name)
              replay()
            }}
            className={cn(
              'focus-ring rounded-md px-3 py-1.5 text-body-sm transition-colors',
              activePreset === name
                ? 'bg-surface-selected text-text-primary'
                : 'bg-surface-muted text-text-secondary hover:bg-surface-hover',
            )}
          >
            motion-{name}
          </button>
        ))}
        <button
          type="button"
          onClick={replay}
          className="focus-ring rounded-md border border-border-default px-3 py-1.5 text-body-sm text-text-primary hover:bg-surface-hover"
        >
          Replay
        </button>
      </div>

      <div className="relative flex h-48 items-center justify-center overflow-hidden rounded-lg border border-border-default bg-surface-sunken">
        <motion.div
          key={`${activePreset}-${key}`}
          initial="hidden"
          animate="visible"
          variants={preset.variants}
          transition={resolveTransition({
            duration: preset.duration,
            ease: preset.ease,
          })}
          className="flex h-24 w-48 items-center justify-center rounded-lg bg-surface-default shadow-elevation-2 text-body-strong text-text-primary"
        >
          {activePreset}
        </motion.div>
      </div>

      <div className="mt-6">
        <p className="text-overline text-text-tertiary mb-3">Staggered row enter (≤5)</p>
        <motion.ul
          className="space-y-2"
          initial="hidden"
          animate="visible"
          variants={staggerChildren(20)}
        >
          {[1, 2, 3, 4, 5].map((n) => (
            <motion.li
              key={n}
              variants={motionPresets['row-enter'].variants}
              transition={resolveTransition({
                duration: 'base',
                ease: 'out',
              })}
              className="rounded-md border border-border-subtle bg-surface-default px-4 py-2 text-body text-text-secondary"
            >
              Row {n}
            </motion.li>
          ))}
        </motion.ul>
      </div>
    </Section>
  )
}

function SignalSection() {
  const [aiThinking, setAiThinking] = useState(false)

  return (
    <Section
      id="signal"
      title="The Signal"
      description="Signature primitive — active nav, Command Bar focus, AI thinking pulse."
    >
      <div className="grid gap-8 lg:grid-cols-2">
        <div className="rounded-lg border border-border-default bg-surface-default p-6">
          <p className="text-overline text-text-tertiary mb-4">Standard (teal)</p>
          <div className="relative ps-4">
            <Signal orientation="vertical" className="absolute inset-y-2 start-0 w-[2px]" />
            <p className="text-body-strong text-text-primary ps-2">Active navigation item</p>
            <p className="text-caption text-text-tertiary ps-2 mt-1">Patients</p>
          </div>
          <div className="mt-6">
            <p className="text-caption text-text-tertiary mb-2">Horizontal · hero</p>
            <Signal size="hero" className="max-w-xs" />
          </div>
        </div>

        <div className="rounded-lg border border-border-ai bg-surface-ai p-6">
          <p className="text-overline text-text-ai mb-4">AI (violet)</p>
          <div className="space-y-4">
            <Signal variant="ai" thinking={aiThinking} className="max-w-full" />
            <p className="text-body text-text-ai">
              AI is drafting a proposed action…
            </p>
            <button
              type="button"
              onClick={() => setAiThinking((v) => !v)}
              className="focus-ring-ai rounded-md bg-action-ai px-4 py-2 text-body-strong text-action-ai-fg hover:bg-action-ai-hover"
            >
              {aiThinking ? 'Stop pulse' : 'Start thinking pulse'}
            </button>
          </div>
        </div>
      </div>
    </Section>
  )
}

export function FoundationsContent() {
  return (
    <>
      <nav aria-label="Foundation sections" className="flex flex-wrap gap-2">
        {['colors', 'typography', 'spacing', 'motion', 'signal'].map((id) => (
          <a
            key={id}
            href={`#${id}`}
            className="focus-ring rounded-md px-3 py-1.5 text-body-sm text-text-link hover:bg-surface-hover capitalize"
          >
            {id}
          </a>
        ))}
      </nav>

      <ColorSection />
      <TypographySection />
      <SpacingSection />
      <MotionPlayground />
      <SignalSection />
    </>
  )
}

export function FoundationsPage({ embedded = false }: { embedded?: boolean }) {
  if (embedded) {
    return <FoundationsContent />
  }

  return (
    <div className="min-h-dvh bg-surface-canvas">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:m-4 focus:rounded-md focus:bg-action-primary focus:px-4 focus:py-2 focus:text-action-primary-fg"
      >
        Skip to content
      </a>

      <header className="sticky top-0 z-sticky border-b border-border-subtle bg-surface-default/95 backdrop-blur-sm">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-4 px-6 py-4">
          <div>
            <p className="text-overline text-text-tertiary">Milestone 1</p>
            <h1 className="text-h1 text-text-primary">Foundations</h1>
          </div>
          <ShowcaseToolbar />
        </div>
      </header>

      <main id="main" className="mx-auto max-w-5xl space-y-16 px-6 py-10">
        <p className="text-body-lg text-text-secondary max-w-2xl">
          Calm Clinical Precision — the design system foundation for AiClinic. Tokens, typography,
          motion, and The Signal.
        </p>

        <FoundationsContent />
      </main>

      <footer className="border-t border-border-subtle py-6 text-center text-caption text-text-tertiary">
        AiClinic Design System · web-reference · presentation only
      </footer>
    </div>
  )
}
