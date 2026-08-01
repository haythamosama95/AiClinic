import {
  Calendar,
  CheckCircle2,
  Clock,
  LogIn,
  Stethoscope,
  UserX,
  XCircle,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { AppointmentStatus } from '../types'
import { STATUS_LABELS } from '../types'

const STATUS_CONFIG: Record<
  AppointmentStatus,
  { bg: string; text: string; Icon: LucideIcon }
> = {
  scheduled: { bg: 'bg-surface-ai', text: 'text-text-ai', Icon: Calendar },
  arrived: { bg: 'bg-status-warning-surface', text: 'text-status-warning-fg', Icon: LogIn },
  checked_in: { bg: 'bg-surface-selected', text: 'text-text-link', Icon: Clock },
  in_progress: { bg: 'bg-status-info-surface', text: 'text-status-info-fg', Icon: Stethoscope },
  completed: { bg: 'bg-status-success-surface', text: 'text-status-success-fg', Icon: CheckCircle2 },
  cancelled: { bg: 'bg-surface-muted', text: 'text-text-secondary', Icon: XCircle },
  no_show: { bg: 'bg-status-danger-surface', text: 'text-status-danger-fg', Icon: UserX },
}

type StatusBadgeProps = {
  status: AppointmentStatus
  size?: 'sm' | 'md'
}

export function StatusBadge({ status, size = 'sm' }: StatusBadgeProps) {
  const { bg, text, Icon } = STATUS_CONFIG[status]
  const sizeClasses = size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-2.5 py-1 text-sm'
  const iconSize = size === 'sm' ? 'h-3 w-3' : 'h-3.5 w-3.5'

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-md font-medium ${bg} ${text} ${sizeClasses}`}
      aria-label={`Status: ${STATUS_LABELS[status]}`}
    >
      <Icon className={iconSize} aria-hidden="true" />
      {STATUS_LABELS[status]}
    </span>
  )
}
