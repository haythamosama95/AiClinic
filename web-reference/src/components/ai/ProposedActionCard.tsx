import { Check, Pencil, Sparkles, X, XCircle } from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { Button } from '@/components/actions/Button'
import { Badge } from '@/components/badge'
import { Card } from '@/components/card/Card'
import { Spinner } from '@/components/ui/spinner/Spinner'
import { cn } from '@/lib/cn'

export type ProposedActionState =
  | 'proposed'
  | 'editing'
  | 'submitting'
  | 'approved'
  | 'rejected'
  | 'failed'

export type ProposedActionCardProps = {
  title: string
  summary: string
  fields?: ReactNode
  state?: ProposedActionState
  errorMessage?: string
  onApprove?: () => void
  onEdit?: () => void
  onDismiss?: () => void
  className?: string
}

export function ProposedActionCard({
  title,
  summary,
  fields,
  state: stateProp,
  errorMessage,
  onApprove,
  onEdit,
  onDismiss,
  className,
}: ProposedActionCardProps) {
  const [internalState, setInternalState] = useState<ProposedActionState>('proposed')
  const state = stateProp ?? internalState

  const handleApprove = () => {
    if (!stateProp) setInternalState('submitting')
    onApprove?.()
    if (!stateProp) {
      window.setTimeout(() => setInternalState('approved'), 1200)
    }
  }

  const handleReject = () => {
    if (!stateProp) setInternalState('rejected')
    onDismiss?.()
  }

  const handleEdit = () => {
    if (!stateProp) setInternalState('editing')
    onEdit?.()
  }

  return (
    <Card variant="ai" className={cn('overflow-hidden', className)}>
      <div className="space-y-4 p-5">
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-2">
            <Sparkles size={16} className="text-text-ai" aria-hidden />
            <span className="text-overline text-text-ai">Proposed by AI</span>
          </div>
          {state === 'approved' ? (
            <Badge color="success" variant="soft">
              Approved
            </Badge>
          ) : null}
          {state === 'rejected' ? (
            <Badge color="neutral" variant="soft">
              Dismissed
            </Badge>
          ) : null}
          {state === 'failed' ? (
            <Badge color="danger" variant="soft">
              Failed
            </Badge>
          ) : null}
        </div>

        <div>
          <h4 className="text-body-strong text-text-primary">{title}</h4>
          <p className="mt-1 text-body-sm text-text-secondary">{summary}</p>
        </div>

        {fields && (state === 'proposed' || state === 'editing' || state === 'failed') ? (
          <div
            className={cn(
              'rounded-md border border-border-subtle bg-surface-default p-4',
              state === 'editing' && 'ring-2 ring-border-focus',
            )}
          >
            {fields}
          </div>
        ) : null}

        {state === 'failed' && errorMessage ? (
          <div className="flex items-start gap-2 rounded-md border border-status-danger-border bg-status-danger-surface px-3 py-2 text-body-sm text-status-danger-fg">
            <XCircle size={16} className="mt-0.5 shrink-0" aria-hidden />
            {errorMessage}
          </div>
        ) : null}

        {state === 'submitting' ? (
          <div className="flex items-center gap-2 text-body-sm text-text-ai">
            <Spinner size="sm" />
            Submitting for approval…
          </div>
        ) : null}

        {state === 'approved' ? (
          <p className="text-body-sm text-status-success-fg">
            Action recorded. Check the updated record in your workspace.
          </p>
        ) : null}

        {(state === 'proposed' || state === 'editing' || state === 'failed') && (
          <div className="flex flex-wrap gap-2 border-t border-border-subtle pt-4">
            <Button
              variant="ai"
              size="sm"
              leadingIcon={<Check size={16} />}
              onClick={handleApprove}
            >
              Approve
            </Button>
            <Button
              variant="secondary"
              size="sm"
              leadingIcon={<Pencil size={16} />}
              onClick={handleEdit}
            >
              Edit
            </Button>
            <Button
              variant="ghost"
              size="sm"
              leadingIcon={<X size={16} />}
              onClick={handleReject}
            >
              Dismiss
            </Button>
          </div>
        )}

        <p className="text-caption text-text-tertiary">
          AI never executes actions directly. Approve to run the validated backend path.
        </p>
      </div>
    </Card>
  )
}
