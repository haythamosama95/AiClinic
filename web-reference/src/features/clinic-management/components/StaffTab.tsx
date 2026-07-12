import { useMemo, useState } from 'react'
import { motion } from 'motion/react'
import {
  MoreHorizontal,
  Pencil,
  Plus,
  SearchX,
  Trash2,
  UserRound,
} from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { ConfirmationDialog } from '@/components/dialog/Dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { ROLE_LABELS, STAFF_ROLES } from '../constants'
import { StaffFormDialog } from './StaffFormDialog'
import { StaffFilterPanel } from './StaffFilterPanel'
import { ListControlBar } from './ListControlBar'
import { emptyStaffFormValues, staffToFormValues } from '../forms/StaffFormFields'
import {
  DEFAULT_STAFF_CONTROLS,
  filterAndSortStaff,
  STAFF_SORT_OPTIONS,
  type StaffListControls,
  type StaffRoleFilter,
} from '../utils/staff-list-controls'
import type { BranchRecord, StaffFormValues, StaffRecord, StaffRole } from '../types'

export type StaffTabProps = {
  staff: StaffRecord[]
  branches: BranchRecord[]
  onAdd: (values: StaffFormValues) => void
  onUpdate: (id: string, values: StaffFormValues) => void
  onRemove: (id: string) => void
}

function branchNames(branchIds: string[], branches: BranchRecord[]): string {
  const names = branchIds
    .map((id) => branches.find((b) => b.id === id)?.name)
    .filter(Boolean)
  if (names.length === 0) return 'No branches'
  if (names.length <= 2) return names.join(', ')
  return `${names.slice(0, 2).join(', ')} +${names.length - 2}`
}

export function StaffTab({ staff, branches, onAdd, onUpdate, onRemove }: StaffTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingStaff, setEditingStaff] = useState<StaffRecord | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<StaffRecord | null>(null)
  const [controls, setControls] = useState<StaffListControls>(DEFAULT_STAFF_CONTROLS)

  const filtered = useMemo(
    () => filterAndSortStaff(staff, branches, controls),
    [staff, branches, controls],
  )

  const activeFilters = useMemo(() => {
    const chips: { id: string; label: string; onRemove: () => void }[] = []

    const filterParts: string[] = []
    if (controls.role !== 'all') {
      filterParts.push(ROLE_LABELS[controls.role as StaffRole])
    }
    if (controls.branchId !== 'all') {
      const branch = branches.find((b) => b.id === controls.branchId)
      filterParts.push(branch?.name ?? 'Branch')
    }
    if (filterParts.length > 0) {
      chips.push({
        id: 'filters',
        label: filterParts.join(' · '),
        onRemove: () => setControls((c) => ({ ...c, role: 'all', branchId: 'all' })),
      })
    }

    if (controls.search) {
      chips.push({
        id: 'search',
        label: `Search: ${controls.search}`,
        onRemove: () => setControls((c) => ({ ...c, search: '' })),
      })
    }
    return chips
  }, [controls.search, controls.role, controls.branchId, branches])

  const filterActiveCount =
    controls.role !== 'all' || controls.branchId !== 'all' ? 1 : 0

  const clearFilters = () =>
    setControls((c) => ({ ...c, role: 'all', branchId: 'all' }))

  const clearAll = () => setControls(DEFAULT_STAFF_CONTROLS)

  const openCreate = () => {
    setEditingStaff(null)
    setDialogOpen(true)
  }

  const openEdit = (member: StaffRecord) => {
    setEditingStaff(member)
    setDialogOpen(true)
  }

  const handleSubmit = (values: StaffFormValues) => {
    if (editingStaff) {
      onUpdate(editingStaff.id, values)
    } else {
      onAdd(values)
    }
    setDialogOpen(false)
    setEditingStaff(null)
  }

  const hasStaff = staff.length > 0
  const hasResults = filtered.length > 0
  const isFiltered =
    controls.search !== '' ||
    controls.role !== 'all' ||
    controls.branchId !== 'all' ||
    controls.sort !== 'name-asc'

  const branchFilterOptions = [
    { value: 'all', label: 'All branches' },
    ...branches.map((b) => ({
      value: b.id,
      label: b.code ? `${b.name} (${b.code})` : b.name,
    })),
  ]

  const roleFilterOptions = [
    { value: 'all', label: 'All roles' },
    ...STAFF_ROLES.map((r) => ({ value: r.value, label: r.label })),
  ]

  return (
    <>
      <motion.div
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.22 }}
        className="space-y-6"
      >
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-xl space-y-1">
            <h3 className="font-[family-name:var(--font-display)] text-h3 text-text-primary">
              Staff
            </h3>
            <p className="text-body-sm text-text-secondary">
              People who sign in to AiClinic. Each account has a role and branch assignments.
            </p>
          </div>
          <Button leadingIcon={<Plus size={16} />} onClick={openCreate}>
            Add staff member
          </Button>
        </div>

        {hasStaff ? (
          <ListControlBar
            searchPlaceholder="Search by name, username, phone, or role…"
            searchAriaLabel="Search staff"
            search={controls.search}
            onSearchChange={(search) => setControls((c) => ({ ...c, search }))}
            sortValue={controls.sort}
            defaultSortValue={DEFAULT_STAFF_CONTROLS.sort}
            sortOptions={[...STAFF_SORT_OPTIONS]}
            onSortChange={(sort) =>
              setControls((c) => ({ ...c, sort: sort as StaffListControls['sort'] }))
            }
            sortAriaLabel="Sort staff"
            filterActiveCount={filterActiveCount}
            filterMenu={
              <StaffFilterPanel
                role={controls.role}
                branchId={controls.branchId}
                roleOptions={roleFilterOptions}
                branchOptions={branchFilterOptions}
                onRoleChange={(role) =>
                  setControls((c) => ({ ...c, role: role as StaffRoleFilter }))
                }
                onBranchChange={(branchId) => setControls((c) => ({ ...c, branchId }))}
                onClearAll={clearFilters}
              />
            }
            activeFilters={activeFilters}
            onClearAll={isFiltered ? clearAll : undefined}
          />
        ) : null}

        {!hasStaff ? (
          <div className="rounded-2xl border border-dashed border-border-default bg-surface-sunken/50 px-6 py-16 text-center">
            <UserRound size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
            <p className="mt-4 text-body-strong text-text-primary">No staff accounts yet</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Create accounts for administrators, clinicians, and front-desk staff.
            </p>
            <Button className="mt-6" leadingIcon={<Plus size={16} />} onClick={openCreate}>
              Add staff member
            </Button>
          </div>
        ) : !hasResults ? (
          <div className="rounded-2xl border border-border-subtle bg-surface-default px-6 py-14 text-center shadow-elevation-1">
            <SearchX size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
            <p className="mt-4 text-body-strong text-text-primary">No staff match</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Try a different search term or clear your filters.
            </p>
            <Button className="mt-6" variant="secondary" onClick={clearAll}>
              Clear filters
            </Button>
          </div>
        ) : (
          <div className="overflow-hidden rounded-2xl border border-border-subtle bg-surface-default shadow-elevation-1">
            <ul className="divide-y divide-border-subtle">
              {filtered.map((member, index) => (
                <motion.li
                  key={member.id}
                  layout
                  initial={{ opacity: 0, x: -6 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.2, delay: Math.min(index * 0.025, 0.12) }}
                  className="flex items-center gap-4 px-5 py-4 transition-colors hover:bg-surface-hover/50"
                >
                  <Avatar name={member.fullName} size="md" />

                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="truncate text-body-strong text-text-primary">
                        {member.fullName}
                      </p>
                      <Badge color="teal" variant="soft" size="sm">
                        {ROLE_LABELS[member.role]}
                      </Badge>
                    </div>
                    <p className="mt-0.5 truncate text-body-sm text-text-secondary">
                      @{member.username} · {branchNames(member.branchIds, branches)}
                    </p>
                  </div>

                  <div className="hidden items-center gap-6 sm:flex">
                    <div className="text-end">
                      <p className="text-caption text-text-tertiary">Phone</p>
                      <p className="tabular-nums text-body-sm text-text-secondary">
                        +{member.phone}
                      </p>
                    </div>
                  </div>

                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <IconButton
                        label={`Actions for ${member.fullName}`}
                        icon={<MoreHorizontal size={18} />}
                      />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onSelect={() => openEdit(member)} icon={<Pencil size={14} />}>
                        Edit
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        destructive
                        onSelect={() => setDeleteTarget(member)}
                        icon={<Trash2 size={14} />}
                      >
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </motion.li>
              ))}
            </ul>
          </div>
        )}
      </motion.div>

      <StaffFormDialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open)
          if (!open) setEditingStaff(null)
        }}
        mode={editingStaff ? 'edit' : 'create'}
        branches={branches}
        initialValues={editingStaff ? staffToFormValues(editingStaff) : emptyStaffFormValues()}
        onSubmit={handleSubmit}
      />

      <ConfirmationDialog
        open={Boolean(deleteTarget)}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="Delete staff account?"
        description={
          deleteTarget
            ? `${deleteTarget.fullName} will lose access to AiClinic. This cannot be undone.`
            : ''
        }
        confirmLabel="Delete account"
        onConfirm={() => {
          if (deleteTarget) onRemove(deleteTarget.id)
          setDeleteTarget(null)
        }}
      />
    </>
  )
}
