import { Signal } from '@/primitives/Signal'
import { cn } from '@/lib/cn'

export type ThinkingIndicatorProps = {
  label?: string
  className?: string
}

export function ThinkingIndicator({
  label = 'Thinking…',
  className,
}: ThinkingIndicatorProps) {
  return (
    <div
      role="status"
      aria-live="polite"
      className={cn('flex items-center gap-3', className)}
    >
      <div className="w-16">
        <Signal variant="ai" orientation="horizontal" thinking aria-hidden={false} />
      </div>
      <span className="text-body-sm text-text-ai motion-reduce:opacity-100">{label}</span>
    </div>
  )
}
