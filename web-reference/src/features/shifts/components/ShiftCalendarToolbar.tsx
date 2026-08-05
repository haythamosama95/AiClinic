import { ChevronLeft, ChevronRight, Copy, Plus } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import type { CalendarView } from '../types'

type ShiftCalendarToolbarProps = {
  title: string
  view: CalendarView
  onViewChange: (view: CalendarView) => void
  onNavigate: (delta: number) => void
  onToday: () => void
  onCreateShift: () => void
  onCopySchedule: () => void
}

export function ShiftCalendarToolbar({
  title,
  view,
  onViewChange,
  onNavigate,
  onToday,
  onCreateShift,
  onCopySchedule,
}: ShiftCalendarToolbarProps) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border-default bg-surface-default px-4 py-3">
      <div className="flex items-center gap-2">
        <IconButton
          icon={<ChevronLeft size={16} />}
          label="Previous period"
          size="sm"
          onClick={() => onNavigate(-1)}
        />
        <IconButton
          icon={<ChevronRight size={16} />}
          label="Next period"
          size="sm"
          onClick={() => onNavigate(1)}
        />
        <h3 className="shift-heading text-body-strong text-text-primary">{title}</h3>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <SegmentedControl
          value={view}
          onChange={(v) => onViewChange(v as CalendarView)}
          options={[
            { value: 'week', label: 'Week' },
            { value: 'month', label: 'Month' },
          ]}
          aria-label="Calendar view"
          size="sm"
        />
        <Button variant="secondary" size="sm" onClick={onToday}>
          Today
        </Button>
        <Button
          variant="secondary"
          size="sm"
          leadingIcon={<Copy size={14} />}
          onClick={onCopySchedule}
        >
          Copy schedule
        </Button>
        <Button
          variant="primary"
          size="sm"
          leadingIcon={<Plus size={14} />}
          onClick={onCreateShift}
        >
          Create shift
        </Button>
      </div>
    </div>
  )
}
