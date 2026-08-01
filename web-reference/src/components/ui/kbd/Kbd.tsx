import { cn } from '@/lib/cn'

export function Kbd({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <kbd
      className={cn(
        'inline-flex min-h-5 items-center rounded-sm border border-border-subtle bg-surface-sunken px-1.5 py-0.5 text-mono text-text-secondary',
        className,
      )}
    >
      {children}
    </kbd>
  )
}
