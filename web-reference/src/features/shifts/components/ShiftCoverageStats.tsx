import { Badge } from '@/components/badge'
import type { ShiftCoverageSummary } from '../types'

type ShiftCoverageStatsProps = {
  coverage: ShiftCoverageSummary
  accentClass: string
}

export function ShiftCoverageStats({ coverage, accentClass }: ShiftCoverageStatsProps) {
  const fillPercent =
    coverage.totalSlots > 0
      ? Math.round((coverage.filledSlots / coverage.totalSlots) * 100)
      : 0

  return (
    <div className={`${accentClass} grid grid-cols-2 gap-3 sm:grid-cols-4`}>
      <div className="flex items-center gap-3 rounded-lg border border-border-subtle bg-surface-default p-3">
        <div
          className="shift-coverage-ring shrink-0"
          style={{ '--fill': fillPercent } as React.CSSProperties}
          aria-hidden
        />
        <div>
          <p className="shift-mono text-body-strong text-text-primary">{fillPercent}%</p>
          <p className="text-caption text-text-tertiary">Coverage</p>
        </div>
      </div>

      <StatCard label="Filled slots" value={`${coverage.filledSlots}/${coverage.totalSlots}`} />
      <StatCard
        label="Understaffed"
        value={String(coverage.understaffedShifts)}
        badge={coverage.understaffedShifts > 0 ? { color: 'warning' as const, label: 'Gap' } : undefined}
      />
      <StatCard
        label="Unassigned staff"
        value={String(coverage.unassignedStaff)}
        badge={coverage.unassignedStaff > 0 ? { color: 'info' as const, label: 'Open' } : undefined}
      />
    </div>
  )
}

function StatCard({
  label,
  value,
  badge,
}: {
  label: string
  value: string
  badge?: { color: 'warning' | 'info'; label: string }
}) {
  return (
    <div className="rounded-lg border border-border-subtle bg-surface-default p-3">
      <div className="flex items-center justify-between gap-2">
        <p className="shift-mono text-body-strong text-text-primary">{value}</p>
        {badge ? (
          <Badge color={badge.color} variant="soft" size="sm">
            {badge.label}
          </Badge>
        ) : null}
      </div>
      <p className="mt-0.5 text-caption text-text-tertiary">{label}</p>
    </div>
  )
}
