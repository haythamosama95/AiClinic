import { Bell, ChevronDown } from 'lucide-react'
import { useState } from 'react'
import { Badge } from '@/components/badge'
import { Button } from '@/components/actions/Button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { cn } from '@/lib/cn'
import {
  formatWaitDuration,
  nextStatuses,
  queueStatusLabel,
} from '@/features/queue/queue-status'
import {
  isOverdueWait,
  waitBarPercent,
} from '@/features/queue/desk/desk-helpers'
import type { QueueAppointment, QueueAppointmentStatus } from '@/features/queue/types'

export type DeskWaitingRowProps = {
  appointment: QueueAppointment
  waitMinutes: number
  maxWait: number
  onStatusChange: (id: string, status: QueueAppointmentStatus) => void
  onNotify?: (id: string) => void
}

export function DeskWaitingRow({
  appointment,
  waitMinutes,
  maxWait,
  onStatusChange,
  onNotify,
}: DeskWaitingRowProps) {
  const [open, setOpen] = useState(false)
  const transitions = nextStatuses(appointment.status)
  const overdue = isOverdueWait(waitMinutes)
  const barWidth = waitBarPercent(waitMinutes, Math.max(maxWait, 20))

  return (
    <div
      className={cn(
        'space-y-2 border-b border-border-subtle px-4 py-3 last:border-b-0',
        overdue && 'bg-status-warning-surface/20',
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <p className="truncate text-body-strong text-text-primary">
              {appointment.patientName}
            </p>
            {appointment.isUrgent ? (
              <Badge color="warning" variant="soft" size="sm">
                Urgent
              </Badge>
            ) : null}
          </div>
          <p className="text-caption text-text-tertiary">
            {appointment.preferredDoctorName ?? 'No preference'}
          </p>
        </div>

        <p
          className={cn(
            'shrink-0 font-mono text-body-strong tabular-nums',
            overdue ? 'text-status-warning-fg' : 'text-text-primary',
          )}
        >
          {formatWaitDuration(waitMinutes)}
        </p>
      </div>

      <div className="h-1 overflow-hidden rounded-full bg-surface-muted">
        <div
          className={cn(
            'h-full rounded-full transition-[width] duration-300',
            overdue ? 'bg-status-warning-fg' : 'bg-action-primary',
          )}
          style={{ width: `${barWidth}%` }}
          role="progressbar"
          aria-valuenow={waitMinutes}
          aria-valuemin={0}
          aria-valuemax={Math.max(maxWait, 20)}
          aria-label={`Wait time ${formatWaitDuration(waitMinutes)}`}
        />
      </div>

      <div className="flex items-center justify-between gap-2">
        <Badge color={overdue ? 'warning' : 'neutral'} variant="soft" size="sm">
          {queueStatusLabel(appointment.status)}
        </Badge>

        <div className="flex items-center gap-1">
          {onNotify ? (
            <Button
              variant="ghost"
              size="sm"
              leadingIcon={<Bell size={14} />}
              onClick={() => onNotify(appointment.id)}
            >
              Notify
            </Button>
          ) : null}
          {transitions.length > 0 ? (
            <DropdownMenu open={open} onOpenChange={setOpen}>
              <DropdownMenuTrigger asChild>
                <Button variant="secondary" size="sm" trailingIcon={<ChevronDown size={14} />}>
                  Move
                </Button>
              </DropdownMenuTrigger>
              {open ? (
                <DropdownMenuContent align="end">
                  {transitions.map((status) => (
                    <DropdownMenuItem
                      key={status}
                      onSelect={() => {
                        onStatusChange(appointment.id, status)
                        setOpen(false)
                      }}
                    >
                      {queueStatusLabel(status)}
                    </DropdownMenuItem>
                  ))}
                </DropdownMenuContent>
              ) : null}
            </DropdownMenu>
          ) : null}
        </div>
      </div>
    </div>
  )
}
