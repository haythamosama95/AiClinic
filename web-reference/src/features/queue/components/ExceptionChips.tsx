import { AlertCircle, ClipboardList, CreditCard, Smartphone } from 'lucide-react'
import type { AppointmentExceptions } from '../types'

type ExceptionChipsProps = {
  exceptions?: AppointmentExceptions
}

const CHIP_CONFIG = [
  {
    key: 'copayDue' as const,
    label: 'Copay due',
    Icon: CreditCard,
    className: 'bg-status-warning-surface text-status-warning-fg',
  },
  {
    key: 'formsIncomplete' as const,
    label: 'Forms incomplete',
    Icon: ClipboardList,
    className: 'bg-status-danger-surface text-status-danger-fg',
  },
  {
    key: 'selfCheckInPending' as const,
    label: 'Self check-in',
    Icon: Smartphone,
    className: 'bg-status-info-surface text-status-info-fg',
  },
  {
    key: 'insuranceIssue' as const,
    label: 'Insurance',
    Icon: AlertCircle,
    className: 'bg-status-danger-surface text-status-danger-fg',
  },
]

export function ExceptionChips({ exceptions }: ExceptionChipsProps) {
  if (!exceptions) return null

  const active = CHIP_CONFIG.filter((chip) => exceptions[chip.key])
  if (active.length === 0) return null

  return (
    <div className="mt-1 flex flex-wrap gap-1" role="list" aria-label="Appointment exceptions">
      {active.map(({ key, label, Icon, className }) => (
        <span
          key={key}
          role="listitem"
          className={`inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-semibold ${className}`}
        >
          <Icon className="h-2.5 w-2.5" aria-hidden="true" />
          {label}
        </span>
      ))}
    </div>
  )
}
