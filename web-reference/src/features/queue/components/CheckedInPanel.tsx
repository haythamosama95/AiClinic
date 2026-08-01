import { useMemo, useState } from 'react'
import { AlertCircle } from 'lucide-react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { cn } from '@/lib/cn'
import type { Appointment, CheckedInSortMode } from '../types'
import { formatDuration, formatTime, getWaitMinutes } from '../utils'
import { FlowPulse } from './FlowPulse'

type CheckedInPanelProps = {
  patients: Appointment[]
  now: number
  embedded?: boolean
  className?: string
}

const SORT_OPTIONS: { value: CheckedInSortMode; label: string }[] = [
  { value: 'longest_wait', label: 'Longest wait' },
  { value: 'next_in_order', label: 'Next in order' },
]

function waitSeverity(maxWait: number): number {
  if (maxWait <= 10) return 0.2
  if (maxWait <= 20) return 0.45
  if (maxWait <= 30) return 0.7
  return 0.95
}

export function CheckedInPanel({ patients, now, embedded = false, className }: CheckedInPanelProps) {
  const [sort, setSort] = useState<CheckedInSortMode>('longest_wait')

  const sortedPatients = useMemo(() => {
    const list = [...patients]
    if (sort === 'next_in_order') {
      return list.sort(
        (a, b) => new Date(a.scheduledTime).getTime() - new Date(b.scheduledTime).getTime(),
      )
    }
    return list.sort((a, b) => getWaitMinutes(b, now) - getWaitMinutes(a, now))
  }, [patients, sort, now])

  const maxWait =
    sortedPatients.length > 0
      ? Math.max(...sortedPatients.map((p) => getWaitMinutes(p, now)))
      : 0

  const sortHint =
    sort === 'longest_wait' ? 'Longest wait first' : 'Earliest appointment first'

  return (
    <section
      className={cn(
        embedded ? '' : 'rounded-xl border border-border-default bg-surface-default',
        className,
      )}
      aria-labelledby="checked-in-panel-title"
    >
      <header
        className={cn(
          'shrink-0 px-4 py-3',
          !embedded && 'border-b border-border-default',
        )}
      >
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h2 id="checked-in-panel-title" className="queue-heading text-sm font-semibold text-text-primary">
              Checked in — waiting
            </h2>
            <p className="text-xs text-text-secondary">{sortHint}</p>
          </div>
          <SegmentedControl
            aria-label="Sort checked-in patients"
            options={SORT_OPTIONS}
            value={sort}
            onChange={setSort}
            size="sm"
          />
        </div>
      </header>

      <div className="shrink-0 px-4 pt-3">
        <FlowPulse severity={waitSeverity(maxWait)} patientCount={sortedPatients.length} />
      </div>

      <div
        className={cn(
          embedded
            ? 'max-h-[min(60vh,28rem)] overflow-y-auto'
            : 'min-h-0 flex-1 overflow-y-auto',
        )}
      >
        {sortedPatients.length === 0 ? (
          <p className="px-4 pb-4 text-sm text-text-secondary">No patients currently waiting</p>
        ) : (
          <ul className="divide-y divide-border-subtle">
            {sortedPatients.map((patient, index) => {
              const wait = getWaitMinutes(patient, now)
              const isWarning = wait > 20 && wait <= 30
              const isCritical = wait > 30

              return (
                <li
                  key={patient.id}
                  className={`px-4 py-3 ${
                    isCritical
                      ? 'bg-status-danger-surface/50'
                      : isWarning
                        ? 'bg-status-warning-surface/50'
                        : ''
                  }`}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="font-medium text-text-primary">{patient.patientName}</p>
                      <p className="text-xs text-text-secondary">
                        {patient.preferredDoctorName ?? 'Any provider'}
                      </p>
                    </div>
                    <span className="queue-mono rounded-md bg-surface-sunken px-2 py-1 text-xs font-semibold text-text-secondary">
                      #{index + 1}
                    </span>
                  </div>

                  <div className="mt-2 flex items-center justify-between">
                    <span
                      className={`queue-mono text-lg font-semibold ${
                        isCritical
                          ? 'text-status-danger-fg'
                          : isWarning
                            ? 'text-status-warning-fg'
                            : 'text-action-primary'
                      }`}
                    >
                      {formatDuration(wait)}
                    </span>
                    {(isWarning || isCritical) && (
                      <span className="inline-flex items-center gap-1 text-xs font-medium text-status-danger-fg">
                        <AlertCircle className="h-3.5 w-3.5" aria-hidden="true" />
                        {isCritical ? 'Critical wait' : 'Long wait'}
                      </span>
                    )}
                  </div>

                  <div className="mt-1 flex gap-3 text-xs text-text-secondary">
                    <span>Appt {formatTime(patient.scheduledTime)}</span>
                    {patient.arrivedAt && <span>Arr {formatTime(patient.arrivedAt)}</span>}
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </div>
    </section>
  )
}
