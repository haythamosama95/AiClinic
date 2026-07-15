import * as PopoverPrimitive from '@radix-ui/react-popover'
import { motion } from 'motion/react'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition } from '@/lib/motion'

export function Popover({
  open,
  onOpenChange,
  trigger,
  children,
  align = 'start',
  className,
  contentClassName,
  modal = false,
}: {
  open?: boolean
  onOpenChange?: (open: boolean) => void
  trigger: React.ReactNode
  children: React.ReactNode
  modal?: boolean
  align?: 'start' | 'center' | 'end'
  className?: string
  contentClassName?: string
}) {
  return (
    <PopoverPrimitive.Root open={open} onOpenChange={onOpenChange} modal={modal}>
      <PopoverPrimitive.Trigger asChild className={className}>
        {trigger}
      </PopoverPrimitive.Trigger>
      <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
          align={align}
          sideOffset={4}
          asChild
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.98 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.98 }}
            transition={resolveTransition(motionPresets['fade-scale'])}
            className={cn(
              'z-[var(--z-popover)] rounded-lg border border-border-default bg-surface-raised shadow-elevation-2 outline-none',
              contentClassName,
            )}
          >
            {children}
          </motion.div>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  )
}
