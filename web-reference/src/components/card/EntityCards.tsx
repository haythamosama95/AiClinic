import { Calendar, MoreHorizontal, Phone } from 'lucide-react'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { cn } from '@/lib/cn'
import { Card } from './Card'

export function PatientCard({
  name,
  mrn,
  phone,
  tags,
  className,
}: {
  name: string
  mrn: string
  phone: string
  tags?: string[]
  className?: string
}) {
  return (
    <Card
      variant="interactive"
      className={cn('p-4', className)}
      role="article"
      aria-label={`Patient ${name}`}
    >
      <div className="flex items-start gap-3">
        <Avatar name={name} size="lg" />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <div>
              <p className="text-body-strong text-text-primary">{name}</p>
              <p className="text-caption text-text-secondary tabular-nums">MRN · {mrn}</p>
            </div>
            <IconButton
              icon={<MoreHorizontal size={16} />}
              label="Patient actions"
              size="sm"
            />
          </div>
          <p className="mt-2 flex items-center gap-1.5 text-body-sm text-text-secondary">
            <Phone size={14} className="shrink-0 text-icon-muted" aria-hidden />
            <span className="tabular-nums">{phone}</span>
          </p>
          {tags && tags.length > 0 ? (
            <div className="mt-3 flex flex-wrap gap-1.5">
              {tags.map((tag) => (
                <Badge key={tag} size="sm" color="neutral" variant="soft">
                  {tag}
                </Badge>
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </Card>
  )
}

export function AppointmentCard({
  time,
  patient,
  doctor,
  status,
  branch,
  className,
}: {
  time: string
  patient: string
  doctor: string
  status: 'confirmed' | 'pending' | 'cancelled'
  branch: string
  className?: string
}) {
  const statusColor =
    status === 'confirmed' ? 'success' : status === 'pending' ? 'warning' : 'danger'

  return (
    <Card variant="flat" className={cn('p-4', className)} role="article">
      <div className="flex items-start justify-between gap-3">
        <div className="flex gap-3">
          <div className="flex size-10 shrink-0 flex-col items-center justify-center rounded-md bg-surface-selected text-text-link">
            <Calendar size={14} aria-hidden />
            <span className="text-caption tabular-nums">{time.split(' ')[0]}</span>
          </div>
          <div>
            <p className="text-body-strong text-text-primary">{patient}</p>
            <p className="text-body-sm text-text-secondary">{doctor}</p>
            <p className="text-caption text-text-tertiary">{branch}</p>
          </div>
        </div>
        <Badge color={statusColor} variant="soft">
          {status}
        </Badge>
      </div>
    </Card>
  )
}

export function InvoiceCard({
  number,
  patient,
  amount,
  status,
  date,
  className,
}: {
  number: string
  patient: string
  amount: number
  status: 'paid' | 'pending' | 'overdue'
  date: string
  className?: string
}) {
  const statusColor =
    status === 'paid' ? 'success' : status === 'pending' ? 'warning' : 'danger'

  return (
    <Card variant="flat" className={cn('p-4', className)} role="article">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-mono text-text-primary">{number}</p>
          <p className="text-body-sm text-text-secondary">{patient}</p>
          <p className="text-caption text-text-tertiary tabular-nums">{date}</p>
        </div>
        <div className="text-end">
          <MoneyDisplay amount={amount} emphasis className="text-body-strong" />
          <Badge color={statusColor} variant="soft" className="mt-1">
            {status}
          </Badge>
        </div>
      </div>
    </Card>
  )
}

export function ServiceCard({
  name,
  price,
  globalStatus,
  branchSummary,
  className,
}: {
  name: string
  price: number
  globalStatus: 'active' | 'inactive'
  branchSummary: string
  className?: string
}) {
  return (
    <Card variant="raised" className={cn('p-4', className)} role="article">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-body-strong text-text-primary">{name}</p>
          <MoneyDisplay amount={price} className="mt-1 text-body-sm" />
          <p className="mt-2 text-caption text-text-secondary">{branchSummary}</p>
        </div>
        <Badge color={globalStatus === 'active' ? 'success' : 'neutral'} variant="soft">
          {globalStatus}
        </Badge>
      </div>
      <div className="mt-4">
        <Button variant="ghost" size="sm">
          View branches
        </Button>
      </div>
    </Card>
  )
}
