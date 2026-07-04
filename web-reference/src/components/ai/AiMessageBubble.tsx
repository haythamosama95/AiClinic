import { Copy, Sparkles } from 'lucide-react'
import type { ReactNode } from 'react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'

export type AiMessageRole = 'user' | 'assistant'

export type AiMessageBubbleProps = {
  role: AiMessageRole
  children: ReactNode
  timestamp?: string
  onCopy?: () => void
  className?: string
}

export function AiMessageBubble({
  role,
  children,
  timestamp,
  onCopy,
  className,
}: AiMessageBubbleProps) {
  const isUser = role === 'user'

  return (
    <div
      className={cn(
        'flex',
        isUser ? 'justify-end' : 'justify-start',
        className,
      )}
    >
      <div
        className={cn(
          'group relative max-w-[85%] rounded-lg px-4 py-3',
          isUser
            ? 'bg-surface-muted text-text-primary'
            : 'border border-border-ai bg-surface-ai text-text-primary',
        )}
      >
        {!isUser ? (
          <div className="mb-2 flex items-center gap-1.5 text-caption text-text-ai">
            <Sparkles size={12} aria-hidden />
            <span>AI assistant</span>
          </div>
        ) : null}
        <div className="text-body whitespace-pre-wrap">{children}</div>
        {timestamp ? (
          <time className="mt-2 block text-caption tabular-nums text-text-tertiary">
            {timestamp}
          </time>
        ) : null}
        {onCopy && !isUser ? (
          <Button
            variant="ghost"
            size="sm"
            className="absolute end-2 top-2 opacity-0 transition-opacity group-hover:opacity-100"
            leadingIcon={<Copy size={14} />}
            onClick={onCopy}
            aria-label="Copy message"
          >
            Copy
          </Button>
        ) : null}
      </div>
    </div>
  )
}
