import { Sparkles, X } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'

export type AiSuggestionProps = {
  message: string
  onAccept?: () => void
  onDismiss?: () => void
  className?: string
}

export function AiSuggestion({
  message,
  onAccept,
  onDismiss,
  className,
}: AiSuggestionProps) {
  return (
    <div
      className={cn(
        'flex items-start gap-3 rounded-lg border border-border-ai bg-surface-ai px-4 py-3',
        className,
      )}
      role="note"
      aria-label="AI suggestion"
    >
      <Sparkles size={16} className="mt-0.5 shrink-0 text-text-ai" aria-hidden />
      <div className="min-w-0 flex-1">
        <p className="text-body-sm text-text-primary">{message}</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {onAccept ? (
            <Button variant="ai" size="sm" onClick={onAccept}>
              Use suggestion
            </Button>
          ) : null}
          {onDismiss ? (
            <Button variant="ghost" size="sm" onClick={onDismiss}>
              Dismiss
            </Button>
          ) : null}
        </div>
      </div>
      {onDismiss ? (
        <IconButton
          icon={<X size={14} />}
          label="Dismiss suggestion"
          size="sm"
          variant="ghost"
          onClick={onDismiss}
        />
      ) : null}
    </div>
  )
}
