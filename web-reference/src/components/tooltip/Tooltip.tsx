import {
  Provider,
  Root,
  Trigger,
  Portal,
  Content,
  Arrow,
  type TooltipProps as RadixTooltipProps,
} from '@radix-ui/react-tooltip'
import { type ReactNode } from 'react'
import { cn } from '@/lib/cn'
import { resolveTransition } from '@/lib/motion'
import { motion } from 'motion/react'

export type TooltipProps = RadixTooltipProps & {
  content: ReactNode
  children: ReactNode
  side?: 'top' | 'right' | 'bottom' | 'left'
  align?: 'start' | 'center' | 'end'
  className?: string
  showArrow?: boolean
  disabled?: boolean
}

export function TooltipProvider({ children }: { children: ReactNode }) {
  return (
    <Provider delayDuration={400} skipDelayDuration={0}>
      {children}
    </Provider>
  )
}

export function Tooltip({
  content,
  children,
  side = 'top',
  align = 'center',
  className,
  showArrow = true,
  disabled = false,
  ...props
}: TooltipProps) {
  if (disabled) {
    return <>{children}</>
  }

  return (
    <Root {...props}>
      <Trigger asChild>{children}</Trigger>
      <Portal>
        <Content
          side={side}
          align={align}
          sideOffset={6}
          collisionPadding={8}
          className={cn(
            'z-[var(--z-tooltip)] max-w-xs rounded-lg border border-border-subtle',
            'bg-surface-raised px-3 py-2 text-body-sm text-text-primary shadow-elevation-2',
            'focus:outline-none',
            className,
          )}
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.98 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={resolveTransition({ duration: 'fast', ease: 'out' })}
          >
            {content}
          </motion.div>
          {showArrow ? (
            <Arrow className="fill-surface-raised" width={10} height={5} />
          ) : null}
        </Content>
      </Portal>
    </Root>
  )
}
