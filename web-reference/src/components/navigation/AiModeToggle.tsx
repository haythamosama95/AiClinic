import { Sparkles } from 'lucide-react'
import { cn } from '@/lib/cn'
import { useAiMode } from '@/providers/AiModeProvider'

export type AiModeToggleProps = {
  className?: string
  showLabel?: boolean
}

export function AiModeToggle({ className, showLabel = true }: AiModeToggleProps) {
  const { aiMode, toggleAiMode } = useAiMode()

  return (
    <button
      type="button"
      onClick={toggleAiMode}
      aria-pressed={aiMode}
      aria-label={aiMode ? 'Switch to standard mode' : 'Switch to AI mode'}
      className={cn(
        'focus-ring inline-flex items-center gap-2 rounded-md border px-3 py-1.5 text-body-strong transition-colors duration-[var(--duration-base)]',
        aiMode
          ? 'border-border-ai bg-surface-ai text-text-ai focus-ring-ai'
          : 'border-border-default bg-surface-default text-text-primary hover:bg-surface-hover',
        className,
      )}
    >
      <Sparkles
        size={16}
        strokeWidth={1.5}
        className={cn(
          'shrink-0 transition-colors duration-[var(--duration-base)]',
          aiMode ? 'text-text-ai' : 'text-icon-default',
        )}
      />
      {showLabel ? (
        <span>{aiMode ? 'AI mode' : 'Standard'}</span>
      ) : null}
    </button>
  )
}
