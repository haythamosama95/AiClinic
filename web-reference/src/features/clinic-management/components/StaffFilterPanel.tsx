import { Button } from '@/components/actions/Button'
import { FormField } from '@/components/ui/form-field/FormField'
import { Select } from '@/components/ui/select/Select'
import type { FilterMenuOption } from './FilterMenuPanel'

export type StaffFilterPanelProps = {
  role: string
  branchId: string
  roleOptions: FilterMenuOption[]
  branchOptions: FilterMenuOption[]
  onRoleChange: (value: string) => void
  onBranchChange: (value: string) => void
  onClearAll: () => void
}

export function StaffFilterPanel({
  role,
  branchId,
  roleOptions,
  branchOptions,
  onRoleChange,
  onBranchChange,
  onClearAll,
}: StaffFilterPanelProps) {
  const hasActiveFilters = role !== 'all' || branchId !== 'all'

  return (
    <div className="w-[min(18rem,calc(100vw-2rem))] space-y-4 p-4">
      <p className="text-overline text-text-tertiary">Filters</p>

      <div className="space-y-3 rounded-xl border border-border-subtle bg-surface-sunken/40 p-3">
        <FormField id="staff-filter-role" label="Role">
          <Select
            id="staff-filter-role"
            value={role}
            options={roleOptions}
            placeholder="All roles"
            onValueChange={onRoleChange}
          />
        </FormField>

        <FormField id="staff-filter-branch" label="Branch">
          <Select
            id="staff-filter-branch"
            value={branchId}
            options={branchOptions}
            placeholder="All branches"
            onValueChange={onBranchChange}
          />
        </FormField>
      </div>

      {hasActiveFilters ? (
        <Button variant="secondary" size="sm" className="w-full" onClick={onClearAll}>
          Clear filters
        </Button>
      ) : null}
    </div>
  )
}
