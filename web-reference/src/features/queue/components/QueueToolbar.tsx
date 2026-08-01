import { Check, Search, SlidersHorizontal } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { Popover } from '@/components/ui/popover/Popover'
import { cn } from '@/lib/cn'
import type { AppointmentStatus } from '../types'
import { STATUS_LABELS } from '../types'

const FILTER_STATUSES: AppointmentStatus[] = [
  'scheduled',
  'arrived',
  'checked_in',
  'in_progress',
  'completed',
  'cancelled',
  'no_show',
]

type QueueToolbarProps = {
  search: string
  onSearchChange: (value: string) => void
  statusFilters: Set<AppointmentStatus>
  onToggleStatus: (status: AppointmentStatus) => void
  onClearFilters: () => void
}

export function QueueToolbar({
  search,
  onSearchChange,
  statusFilters,
  onToggleStatus,
  onClearFilters,
}: QueueToolbarProps) {
  const activeCount = statusFilters.size

  return (
    <div className="flex items-center gap-3">
      <div className="relative min-w-[200px] flex-1">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-icon-muted"
          aria-hidden="true"
        />
        <input
          type="search"
          value={search}
          onChange={(e) => onSearchChange(e.target.value)}
          placeholder="Search patients…"
          className="focus-ring w-full rounded-lg border border-border-default bg-surface-default py-2.5 pl-9 pr-3 text-sm text-text-primary placeholder:text-text-placeholder focus:border-border-focus focus:outline-none"
          aria-label="Search patients by name"
        />
      </div>

      <Popover
        align="end"
        contentClassName="w-[min(16rem,calc(100vw-2rem))]"
        trigger={
          <Button
            type="button"
            variant="secondary"
            size="md"
            leadingIcon={<SlidersHorizontal size={15} />}
            className="shrink-0"
            aria-label={
              activeCount > 0
                ? `Status filter, ${activeCount} selected`
                : 'Filter by status'
            }
          >
            Status
            {activeCount > 0 ? (
              <span aria-hidden className="ms-0.5 text-text-secondary">
                · {activeCount}
              </span>
            ) : null}
          </Button>
        }
      >
        <div className="flex flex-col">
          <div className="p-2">
            <p className="px-2 py-1.5 text-overline text-text-tertiary">Status</p>
            <ul role="listbox" aria-label="Filter by status" aria-multiselectable="true">
              {FILTER_STATUSES.map((status) => {
                const selected = statusFilters.has(status)
                return (
                  <li key={status}>
                    <button
                      type="button"
                      role="option"
                      aria-selected={selected}
                      onClick={() => onToggleStatus(status)}
                      className={cn(
                        'focus-ring flex w-full items-center gap-2 rounded-md px-2 py-2 text-start text-body-sm transition-colors',
                        selected
                          ? 'bg-surface-selected font-medium text-text-primary'
                          : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary',
                      )}
                    >
                      <span className="flex size-4 shrink-0 items-center justify-center">
                        {selected ? (
                          <Check size={14} strokeWidth={2} className="text-action-primary" />
                        ) : null}
                      </span>
                      {STATUS_LABELS[status]}
                    </button>
                  </li>
                )
              })}
            </ul>
          </div>
          {activeCount > 0 ? (
            <div className="border-t border-border-subtle p-2">
              <Button
                type="button"
                variant="secondary"
                size="sm"
                className="w-full"
                onClick={onClearFilters}
              >
                Clear filters
              </Button>
            </div>
          ) : null}
        </div>
      </Popover>
    </div>
  )
}
