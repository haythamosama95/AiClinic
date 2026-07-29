import { AlertTriangle, ChevronDown, Footprints, UserRound } from 'lucide-react'
import { useState } from 'react'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { Button } from '@/components/actions/Button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { cn } from '@/lib/cn'
import {
  nextStatuses,
  queueStatusColor,
  queueStatusLabel,
} from '@/features/queue/queue-status'
import type { QueueAppointment, QueueAppointmentStatus } from '@/features/queue/types'

export type QueueAppointmentRowProps = {
  appointment: QueueAppointment
  onStatusChange: (id: string, newStatus: QueueAppointmentStatus) => void
  onNotify?: (id: string) => void
  onAssignDoctor?: (id: string) => void
  className?: string
}

export function QueueAppointmentRow({
  appointment,
  onStatusChange,
  onNotify,
  onAssignDoctor,
  className,
}: QueueAppointmentRowProps) {
  const [menuOpen, setMenuOpen] = useState(false)
  const transitions = nextStatuses(appointment.status)
  const hasActions = transitions.length > 0 || onNotify || onAssignDoctor

  return (
    <tr
      className={cn(
        'group border-b border-border-subtle transition-colors hover:bg-surface-hover',
        appointment.isUrgent && 'bg-status-warning-surface/30',
        className,
      )}
    >
      <td className="whitespace-nowrap px-4 py-3 align-middle">
        <div className="flex flex-col">
          <span className="font-mono text-body-sm font-medium tabular-nums text-text-primary">
            {appointment.timeLabel}
          </span>
          <span className="font-mono text-caption tabular-nums text-text-tertiary">
            {appointment.time}
          </span>
        </div>
      </td>

      <td className="px-4 py-3 align-middle">
        <div className="flex min-w-0 items-center gap-3">
          <Avatar name={appointment.patientName} size="sm" />
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-1.5">
              <p className="truncate text-body-strong text-text-primary">
                {appointment.patientName}
              </p>
              {appointment.isUrgent ? (
                <Badge color="warning" variant="soft" size="sm">
                  <AlertTriangle size={11} aria-hidden className="shrink-0" />
                  Urgent
                </Badge>
              ) : null}
              {appointment.visitType === 'walk_in' ? (
                <Badge color="teal" variant="outline" size="sm">
                  <Footprints size={11} aria-hidden className="shrink-0" />
                  Walk-in
                </Badge>
              ) : null}
            </div>
            <p className="truncate font-mono text-caption tabular-nums text-text-tertiary">
              {appointment.patientMrn}
            </p>
          </div>
        </div>
      </td>

      <td className="px-4 py-3 align-middle">
        <Badge
          color={appointment.visitType === 'walk_in' ? 'teal' : 'neutral'}
          variant="soft"
          size="sm"
        >
          {appointment.visitType === 'walk_in' ? 'Walk-in' : 'Appointment'}
        </Badge>
      </td>

      <td className="px-4 py-3 align-middle">
        <p className="max-w-[10rem] truncate text-body-sm text-text-secondary">
          {appointment.preferredDoctorName ?? (
            <span className="text-text-tertiary">Any doctor</span>
          )}
        </p>
      </td>

      <td className="px-4 py-3 align-middle">
        <Badge color={queueStatusColor(appointment.status)} variant="soft" size="sm">
          {queueStatusLabel(appointment.status)}
        </Badge>
      </td>

      <td className="px-4 py-3 align-middle">
        {hasActions ? (
          <DropdownMenu open={menuOpen} onOpenChange={setMenuOpen}>
            <DropdownMenuTrigger asChild>
              <Button
                variant="secondary"
                size="sm"
                trailingIcon={<ChevronDown size={14} />}
                aria-label={`Update status for ${appointment.patientName}`}
              >
                Update
              </Button>
            </DropdownMenuTrigger>
            {menuOpen ? (
              <DropdownMenuContent align="end">
                {transitions.map((status) => (
                  <DropdownMenuItem
                    key={status}
                    onSelect={() => {
                      onStatusChange(appointment.id, status)
                      setMenuOpen(false)
                    }}
                  >
                    Mark as {queueStatusLabel(status)}
                  </DropdownMenuItem>
                ))}
                {transitions.length > 0 && (onNotify || onAssignDoctor) ? (
                  <DropdownMenuSeparator />
                ) : null}
                {onNotify ? (
                  <DropdownMenuItem
                    onSelect={() => {
                      onNotify(appointment.id)
                      setMenuOpen(false)
                    }}
                  >
                    Notify patient
                  </DropdownMenuItem>
                ) : null}
                {onAssignDoctor ? (
                  <DropdownMenuItem
                    onSelect={() => {
                      onAssignDoctor(appointment.id)
                      setMenuOpen(false)
                    }}
                    icon={<UserRound size={14} aria-hidden />}
                  >
                    Assign doctor
                  </DropdownMenuItem>
                ) : null}
              </DropdownMenuContent>
            ) : null}
          </DropdownMenu>
        ) : (
          <span className="text-caption text-text-tertiary">—</span>
        )}
      </td>
    </tr>
  )
}
