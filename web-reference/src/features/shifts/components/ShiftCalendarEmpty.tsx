import { EmptyState } from '@/components/empty-state/EmptyState'

type ShiftCalendarEmptyProps = {
  onCreateShift: () => void
}

export function ShiftCalendarEmpty({ onCreateShift }: ShiftCalendarEmptyProps) {
  return (
    <div className="rounded-lg border border-dashed border-border-default bg-surface-sunken">
      <EmptyState
        variant="first-run"
        title="No shifts scheduled"
        description="Create your first shift to start building the weekly coverage plan."
        action={{ label: 'Create shift', onClick: onCreateShift }}
      />
    </div>
  )
}
