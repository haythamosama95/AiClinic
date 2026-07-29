import { ChevronDown } from 'lucide-react'
import { useState } from 'react'
import { Avatar } from '@/components/avatar/Avatar'
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
  nextStatuses,
  queueStatusColor,
  queueStatusLabel,
} from '@/features/queue/queue-status'
import type { QueueAppointment, QueueAppointmentStatus } from '@/features/queue/types'

export type DeskScheduleRowProps = {
  appointment: QueueAppointment
  isNow: boolean
  onStatusChange: (id: string, status: QueueAppointmentStatus) => void
}

export function DeskScheduleRow({ appointment, isNow, onStatusChange }: DeskScheduleRowProps) {
  const [open, setOpen] = useState(false)
  const transitions = nextStatuses(appointment.status)

  return (
    <div
      className={cn(
        'grid grid-cols-[4.5rem_1fr_auto] items-center gap-3 border-b border-border-subtle px-4 py-2.5 last:border-b-0',
        isNow && 'bg-surface-selected/60',
      )}
    >
      <div className="text-end">
        <p className="font-mono text-body-sm font-medium tabular-nums text-text-primary">
          {appointment.time}
        </p>
        <p className="font-mono text-[10px] uppercase tabular-nums text-text-tertiary">
          {appointment.timeLabel.split(' ')[1]?.toLowerCase() ?? ''}
        </p>
      </div>

      <div className="flex min-w-0 items-center gap-3">
        <Avatar name={appointment.patientName} size="sm" />
        <div className="min-w-0">
          <p className="truncate text-body-strong text-text-primary">{appointment.patientName}</p>
          <p className="truncate text-caption text-text-tertiary">
            {appointment.preferredDoctorName ?? 'Any doctor'}
            {appointment.visitType === 'walk_in' ? ' · Walk-in' : ''}
          </p>
        </div>
      </div>

      <div className="flex items-center gap-2">
        <Badge color={queueStatusColor(appointment.status)} variant="soft" size="sm">
          {queueStatusLabel(appointment.status)}
        </Badge>
        {transitions.length > 0 ? (
          <DropdownMenu open={open} onOpenChange={setOpen}>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="sm" trailingIcon={<ChevronDown size={14} />}>
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
  )
}
