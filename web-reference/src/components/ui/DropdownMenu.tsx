import * as DropdownMenuPrimitive from '@radix-ui/react-dropdown-menu'
import { motion, AnimatePresence } from 'motion/react'
import type { ReactNode } from 'react'
import { motionPresets, resolveTransition } from '@/lib/motion'
import { cn } from '@/lib/cn'

export const DropdownMenu = DropdownMenuPrimitive.Root
export const DropdownMenuTrigger = DropdownMenuPrimitive.Trigger

type DropdownMenuContentProps = {
  children: ReactNode
  className?: string
  align?: 'start' | 'center' | 'end'
  sideOffset?: number
}

export function DropdownMenuContent({
  children,
  className,
  align = 'start',
  sideOffset = 4,
}: DropdownMenuContentProps) {
  const preset = motionPresets['fade-scale']

  return (
    <DropdownMenuPrimitive.Portal>
      <DropdownMenuPrimitive.Content
        align={align}
        sideOffset={sideOffset}
        asChild
        onCloseAutoFocus={(e) => e.preventDefault()}
      >
        <motion.div
          initial="hidden"
          animate="visible"
          exit="hidden"
          variants={preset.variants}
          transition={resolveTransition({
            duration: preset.duration,
            ease: preset.ease,
          })}
          className={cn(
            'z-[var(--z-dropdown)] min-w-[10rem] overflow-hidden rounded-lg border border-border-default bg-surface-raised p-1 shadow-elevation-2',
            className,
          )}
        >
          {children}
        </motion.div>
      </DropdownMenuPrimitive.Content>
    </DropdownMenuPrimitive.Portal>
  )
}

type DropdownMenuItemProps = {
  children: ReactNode
  onSelect?: () => void
  disabled?: boolean
  destructive?: boolean
  className?: string
  icon?: ReactNode
}

export function DropdownMenuItem({
  children,
  onSelect,
  disabled,
  destructive,
  className,
  icon,
}: DropdownMenuItemProps) {
  return (
    <DropdownMenuPrimitive.Item
      disabled={disabled}
      onSelect={onSelect}
      className={cn(
        'focus-ring flex cursor-pointer select-none items-center gap-2 rounded-md px-2 py-1.5 text-body outline-none transition-colors',
        'data-[highlighted]:bg-surface-hover data-[disabled]:pointer-events-none data-[disabled]:text-text-disabled',
        destructive
          ? 'text-status-danger-fg data-[highlighted]:bg-status-danger-surface'
          : 'text-text-primary',
        className,
      )}
    >
      {icon ? <span className="shrink-0 text-icon-default">{icon}</span> : null}
      {children}
    </DropdownMenuPrimitive.Item>
  )
}

export function DropdownMenuSeparator() {
  return <DropdownMenuPrimitive.Separator className="my-1 h-px bg-border-subtle" />
}

export function DropdownMenuLabel({ children }: { children: ReactNode }) {
  return (
    <DropdownMenuPrimitive.Label className="px-2 py-1.5 text-overline text-text-tertiary">
      {children}
    </DropdownMenuPrimitive.Label>
  )
}

/** Wraps content with AnimatePresence for exit animations */
export function DropdownMenuAnimated({ open, children }: { open: boolean; children: ReactNode }) {
  return <AnimatePresence>{open ? children : null}</AnimatePresence>
}
