import type { Transition, Variants } from 'motion/react'

export const durations = {
  instant: 'var(--duration-instant)',
  fast: 'var(--duration-fast)',
  quick: 'var(--duration-quick)',
  base: 'var(--duration-base)',
  slow: 'var(--duration-slow)',
  deliberate: 'var(--duration-deliberate)',
} as const

/** Millisecond values for Motion — CSS vars are not parseable at runtime */
export const durationMs = {
  instant: 80,
  fast: 120,
  quick: 160,
  base: 220,
  slow: 320,
  deliberate: 480,
} as const

export const easings = {
  standard: 'var(--ease-standard)',
  out: 'var(--ease-out)',
  in: 'var(--ease-in)',
  inOut: 'var(--ease-in-out)',
  emphasized: 'var(--ease-emphasized)',
  linear: 'var(--ease-linear)',
} as const

export type MotionPreset =
  | 'fade'
  | 'fade-scale'
  | 'slide-up'
  | 'slide-inline'
  | 'modal'
  | 'drawer'
  | 'command'
  | 'collapse'
  | 'tab'
  | 'nav'
  | 'row-enter'

function transition(
  duration: keyof typeof durationMs,
  ease: keyof typeof easings,
): Transition {
  return { duration: durationMs[duration] / 1000, ease: cssEase(easings[ease]) }
}

function cssEase(value: string): [number, number, number, number] {
  const match = value.match(/cubic-bezier\(([^)]+)\)/)
  if (!match) return [0.2, 0, 0, 1]
  const parts = match[1].split(',').map((n) => Number.parseFloat(n.trim()))
  return [parts[0], parts[1], parts[2], parts[3]]
}

export function getReducedMotion(): boolean {
  if (typeof window === 'undefined') return false
  return (
    window.matchMedia('(prefers-reduced-motion: reduce)').matches ||
    document.documentElement.dataset.reducedMotion === 'true'
  )
}

export function resolveTransition(
  preset: { duration: keyof typeof durations; ease: keyof typeof easings },
  reduced?: boolean,
): Transition {
  const isReduced = reduced ?? getReducedMotion()
  if (isReduced) {
    return {
      duration: preset.ease === 'in' ? 0 : durationMs.fast / 1000,
      ease: cssEase(easings.standard),
    }
  }
  return transition(preset.duration, preset.ease)
}

export const motionPresets: Record<
  MotionPreset,
  { duration: keyof typeof durations; ease: keyof typeof easings; variants: Variants }
> = {
  fade: {
    duration: 'base',
    ease: 'standard',
    variants: {
      hidden: { opacity: 0 },
      visible: { opacity: 1 },
    },
  },
  'fade-scale': {
    duration: 'quick',
    ease: 'out',
    variants: {
      hidden: { opacity: 0, scale: 0.98 },
      visible: { opacity: 1, scale: 1 },
    },
  },
  'slide-up': {
    duration: 'base',
    ease: 'out',
    variants: {
      hidden: { opacity: 0, y: 8 },
      visible: { opacity: 1, y: 0 },
    },
  },
  'slide-inline': {
    duration: 'base',
    ease: 'out',
    variants: {
      hidden: { opacity: 0, x: 'var(--motion-inline-start, 12px)' },
      visible: { opacity: 1, x: 0 },
    },
  },
  modal: {
    duration: 'base',
    ease: 'out',
    variants: {
      hidden: { opacity: 0, scale: 0.97, y: 8 },
      visible: { opacity: 1, scale: 1, y: 0 },
      exit: { opacity: 0, scale: 0.98, y: 4 },
    },
  },
  drawer: {
    duration: 'slow',
    ease: 'standard',
    variants: {
      hidden: { x: 'var(--motion-drawer-offset, 100%)' },
      visible: { x: 0 },
    },
  },
  command: {
    duration: 'quick',
    ease: 'emphasized',
    variants: {
      hidden: { opacity: 0, scale: 0.96, y: 10 },
      visible: { opacity: 1, scale: 1, y: 0 },
    },
  },
  collapse: {
    duration: 'quick',
    ease: 'standard',
    variants: {
      hidden: { opacity: 0, height: 0 },
      visible: { opacity: 1, height: 'auto' },
    },
  },
  tab: {
    duration: 'quick',
    ease: 'inOut',
    variants: {
      hidden: { scaleX: 0 },
      visible: { scaleX: 1 },
    },
  },
  nav: {
    duration: 'quick',
    ease: 'inOut',
    variants: {
      hidden: { opacity: 0.6 },
      visible: { opacity: 1 },
    },
  },
  'row-enter': {
    duration: 'base',
    ease: 'out',
    variants: {
      hidden: { opacity: 0, y: 6 },
      visible: { opacity: 1, y: 0 },
    },
  },
}

export function staggerChildren(stepMs = 20) {
  return {
    visible: {
      transition: {
        staggerChildren: stepMs / 1000,
        delayChildren: 0,
        when: 'beforeChildren' as const,
      },
    },
    hidden: {},
  }
}

export const buttonPress = {
  whileTap: getReducedMotion() ? {} : { scale: 0.98 },
  transition: resolveTransition({ duration: 'fast', ease: 'out' }),
}
