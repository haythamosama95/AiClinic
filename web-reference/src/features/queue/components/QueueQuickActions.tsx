import { BellRing, Footprints, Printer, UserCheck } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { SplitButton } from '@/components/actions/SplitButton'
import { cn } from '@/lib/cn'

export type QueueQuickActionsProps = {
  onAddWalkIn: () => void
  onCheckInNext: () => void
  onBroadcast?: () => void
  onPrintQueueSlip?: () => void
  className?: string
  /** Pin actions to the bottom of the viewport */
  sticky?: boolean
}

export function QueueQuickActions({
  onAddWalkIn,
  onCheckInNext,
  onBroadcast,
  onPrintQueueSlip,
  className,
  sticky = true,
}: QueueQuickActionsProps) {
  return (
    <div
      className={cn(
        'flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border-subtle bg-surface-default/95 p-3 shadow-elevation-1 backdrop-blur-md',
        sticky && 'sticky bottom-4 z-[var(--z-sticky)]',
        className,
      )}
      role="toolbar"
      aria-label="Queue quick actions"
    >
      <div className="flex flex-wrap items-center gap-2">
        <SplitButton
          label="Add walk-in"
          variant="primary"
          onPrimaryAction={onAddWalkIn}
          items={[
            {
              id: 'walk-in-urgent',
              label: 'Urgent walk-in',
              onSelect: onAddWalkIn,
            },
          ]}
          className="shrink-0"
        />
        <Button
          variant="secondary"
          leadingIcon={<UserCheck size={16} />}
          onClick={onCheckInNext}
        >
          Check in next
        </Button>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Button
          variant="ghost"
          size="sm"
          leadingIcon={<BellRing size={15} />}
          onClick={onBroadcast}
        >
          Broadcast to doctors
        </Button>
        <Button
          variant="ghost"
          size="sm"
          leadingIcon={<Printer size={15} />}
          onClick={onPrintQueueSlip}
        >
          Print queue slip
        </Button>
        <span className="hidden items-center gap-1.5 text-caption text-text-tertiary sm:inline-flex">
          <Footprints size={13} aria-hidden />
          Reception desk
        </span>
      </div>
    </div>
  )
}
