import { motion, useReducedMotion } from 'motion/react'
import { cn } from '@/lib/cn'

export type SignalVariant = 'standard' | 'ai'
export type SignalOrientation = 'horizontal' | 'vertical'
export type SignalSize = 'default' | 'hero'

export type SignalProps = {
  variant?: SignalVariant
  orientation?: SignalOrientation
  size?: SignalSize
  /** AI thinking pulse — only for AI variant */
  thinking?: boolean
  active?: boolean
  className?: string
  'aria-hidden'?: boolean
}

export function Signal({
  variant = 'standard',
  orientation = 'horizontal',
  size = 'default',
  thinking = false,
  active = true,
  className,
  'aria-hidden': ariaHidden = true,
}: SignalProps) {
  const prefersReducedMotion = useReducedMotion()
  const color = variant === 'ai' ? 'var(--signal-color-ai)' : 'var(--signal-color)'
  const thickness =
    size === 'hero' ? 'var(--signal-thickness-hero)' : 'var(--signal-thickness)'

  const isHorizontal = orientation === 'horizontal'

  return (
    <motion.span
      role="presentation"
      aria-hidden={ariaHidden}
      className={cn('block shrink-0', className)}
      style={{
        backgroundColor: color,
        borderRadius: 'var(--signal-radius)',
        boxShadow: active && !prefersReducedMotion ? 'var(--signal-glow)' : undefined,
        width: isHorizontal ? '100%' : thickness,
        height: isHorizontal ? thickness : '100%',
        minWidth: isHorizontal ? undefined : thickness,
        minHeight: isHorizontal ? thickness : undefined,
        transformOrigin: isHorizontal ? 'left center' : 'center top',
      }}
      animate={
        thinking && variant === 'ai' && !prefersReducedMotion
          ? {
            opacity: [0.5, 1, 0.5],
            boxShadow: [
              '0 0 0 transparent',
              `0 0 12px color-mix(in srgb, ${color} 45%, transparent)`,
              '0 0 0 transparent',
            ],
          }
          : undefined
      }
      transition={
        thinking && !prefersReducedMotion
          ? { duration: 1.2, repeat: Infinity, ease: 'linear' }
          : undefined
      }
    />
  )
}
