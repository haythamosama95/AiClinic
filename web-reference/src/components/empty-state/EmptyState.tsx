import {
  FileQuestion,
  FolderOpen,
  Lock,
  SearchX,
  type LucideIcon,
} from 'lucide-react'
import type { ReactNode } from 'react'
import { Button } from '@/components/actions/Button'
import { Kbd } from '@/components/kbd'
import { cn } from '@/lib/cn'

export type EmptyStateVariant = 'first-run' | 'no-results' | 'no-access' | 'error'

const variantConfig: Record<
  EmptyStateVariant,
  { icon: LucideIcon; defaultTitle: string; defaultDescription: string }
> = {
  'first-run': {
    icon: FolderOpen,
    defaultTitle: 'Get started',
    defaultDescription: 'Add your first record to begin.',
  },
  'no-results': {
    icon: SearchX,
    defaultTitle: 'No matches',
    defaultDescription: 'Try adjusting your filters or search terms.',
  },
  'no-access': {
    icon: Lock,
    defaultTitle: 'No access',
    defaultDescription: 'You do not have permission to view this content.',
  },
  error: {
    icon: FileQuestion,
    defaultTitle: 'Something went wrong',
    defaultDescription: 'We could not load this content.',
  },
}

export type EmptyStateProps = {
  variant?: EmptyStateVariant
  title?: string
  description?: string
  action?: { label: string; onClick: () => void }
  secondaryAction?: ReactNode
  shortcutHint?: string[]
  className?: string
}

export function EmptyState({
  variant = 'first-run',
  title,
  description,
  action,
  secondaryAction,
  shortcutHint,
  className,
}: EmptyStateProps) {
  const config = variantConfig[variant]
  const Icon = config.icon

  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center px-6 py-12 text-center',
        className,
      )}
    >
      <div className="mb-4 flex size-12 items-center justify-center rounded-full bg-surface-muted text-icon-muted">
        <Icon size={24} strokeWidth={1.5} aria-hidden />
      </div>
      <h3 className="text-h3 text-text-primary">{title ?? config.defaultTitle}</h3>
      <p className="mt-2 max-w-sm text-body text-text-secondary">
        {description ?? config.defaultDescription}
      </p>
      {action ? (
        <Button variant="primary" className="mt-6" onClick={action.onClick}>
          {action.label}
        </Button>
      ) : null}
      {secondaryAction ? <div className="mt-3">{secondaryAction}</div> : null}
      {shortcutHint ? (
        <p className="mt-4 flex items-center gap-1 text-caption text-text-tertiary">
          Press <Kbd keys={shortcutHint} />
        </p>
      ) : null}
    </div>
  )
}
