import { type HTMLAttributes, type ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type KbdProps = HTMLAttributes<HTMLElement> & {
  children?: ReactNode
  /** Convenience for single-key hints */
  keys?: string[]
}

export function Kbd({ children, keys, className, ...props }: KbdProps) {
  const content =
    children ??
    keys?.map((key, index) => (
      <span key={`${key}-${index}`} className="inline-flex items-center gap-0.5">
        {index > 0 ? <span className="text-text-tertiary" aria-hidden>+</span> : null}
        <kbd className={kbdClass}>{key}</kbd>
      </span>
    ))

  return (
    <span
      className={cn('inline-flex items-center gap-1', className)}
      {...props}
    >
      {content}
    </span>
  )
}

const kbdClass = cn(
  'inline-flex min-w-5 items-center justify-center rounded-sm border border-border-default',
  'bg-surface-sunken px-1.5 py-0.5 font-mono text-caption text-text-secondary',
)

export function KbdKey({
  children,
  className,
  ...props
}: HTMLAttributes<HTMLElement>) {
  return (
    <kbd className={cn(kbdClass, className)} {...props}>
      {children}
    </kbd>
  )
}
