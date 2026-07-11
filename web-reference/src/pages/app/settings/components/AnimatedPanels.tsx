import { AnimatePresence, motion } from 'motion/react'
import type { ReactNode } from 'react'
import { motionPresets, resolveTransition } from '@/lib/motion'

export type StepPanelProps = {
  stepKey: string
  direction: number
  children: ReactNode
}

export function StepPanel({ stepKey, direction, children }: StepPanelProps) {
  const preset = motionPresets['slide-inline']
  const transition = resolveTransition(preset)

  return (
    <AnimatePresence mode="wait" custom={direction}>
      <motion.div
        key={stepKey}
        custom={direction}
        initial={{
          opacity: 0,
          x: direction >= 0 ? 24 : -24,
        }}
        animate={{ opacity: 1, x: 0 }}
        exit={{
          opacity: 0,
          x: direction >= 0 ? -24 : 24,
        }}
        transition={transition}
      >
        {children}
      </motion.div>
    </AnimatePresence>
  )
}

export type ScreenPanelProps = {
  screenKey: string
  children: ReactNode
}

export function ScreenPanel({ screenKey, children }: ScreenPanelProps) {
  const transition = resolveTransition(motionPresets['fade-scale'])

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={screenKey}
        initial={{ opacity: 0, scale: 0.98 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.98 }}
        transition={transition}
      >
        {children}
      </motion.div>
    </AnimatePresence>
  )
}
