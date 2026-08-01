import { useMemo, useState } from 'react'
import {
  ExternalLink,
  MapPin,
  MoreHorizontal,
  Pencil,
  Phone,
  Plus,
  Power,
  SearchX,
  Trash2,
} from 'lucide-react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { Badge } from '@/components/badge'
import { ConfirmationDialog } from '@/components/dialog/Dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { BranchFormDialog } from './BranchFormDialog'
import { FilterMenuPanel } from './FilterMenuPanel'
import { ListControlBar } from './ListControlBar'
import { emptyWorkingSchedule, formatWorkingHoursSummary } from '../working-schedule'
import { branchToFormValues } from '../forms/BranchFormFields'
import {
  BRANCH_SORT_OPTIONS,
  DEFAULT_BRANCH_CONTROLS,
  filterAndSortBranches,
  type BranchListControls,
  type BranchStatusFilter,
} from '../utils/branch-list-controls'
import type { BranchFormValues, BranchRecord } from '../types'

export type BranchesTabProps = {
  branches: BranchRecord[]
  onAdd: (values: BranchFormValues) => void
  onUpdate: (id: string, values: BranchFormValues) => void
  onRemove: (id: string) => void
  onToggleActive: (id: string, isActive: boolean) => void
}

const STATUS_OPTIONS = [
  { value: 'all', label: 'All statuses' },
  { value: 'active', label: 'Active only' },
  { value: 'inactive', label: 'Inactive only' },
]

export function BranchesTab({
  branches,
  onAdd,
  onUpdate,
  onRemove,
  onToggleActive,
}: BranchesTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingBranch, setEditingBranch] = useState<BranchRecord | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<BranchRecord | null>(null)
  const [controls, setControls] = useState<BranchListControls>(DEFAULT_BRANCH_CONTROLS)

  const filtered = useMemo(
    () => filterAndSortBranches(branches, controls),
    [branches, controls],
  )

  const activeFilters = useMemo(() => {
    const chips: { id: string; label: string; onRemove: () => void }[] = []
    if (controls.status !== 'all') {
      chips.push({
        id: 'status',
        label: controls.status === 'active' ? 'Active only' : 'Inactive only',
        onRemove: () => setControls((c) => ({ ...c, status: 'all' })),
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
  }, [controls.search, controls.status])

  const filterActiveCount = controls.status !== 'all' ? 1 : 0

  const clearAll = () => setControls(DEFAULT_BRANCH_CONTROLS)

  const openCreate = () => {
    setEditingBranch(null)
    setDialogOpen(true)
  }

  const openEdit = (branch: BranchRecord) => {
    setEditingBranch(branch)
    setDialogOpen(true)
  }

  const handleSubmit = (values: BranchFormValues) => {
    if (editingBranch) {
      onUpdate(editingBranch.id, values)
    } else {
      onAdd(values)
    }
    setDialogOpen(false)
    setEditingBranch(null)
  }

  const hasBranches = branches.length > 0
  const hasResults = filtered.length > 0
  const isFiltered =
    controls.search !== '' || controls.status !== 'all' || controls.sort !== 'name-asc'

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
              Branches
            </h3>
            <p className="text-body-sm text-text-secondary">
              Every location your clinic operates. Staff and services are assigned per branch.
            </p>
          </div>
          <Button leadingIcon={<Plus size={16} />} onClick={openCreate}>
            Add branch
          </Button>
        </div>

        {hasBranches ? (
          <ListControlBar
            searchPlaceholder="Search by name, code, address, or phone…"
            searchAriaLabel="Search branches"
            search={controls.search}
            onSearchChange={(search) => setControls((c) => ({ ...c, search }))}
            sortValue={controls.sort}
            defaultSortValue={DEFAULT_BRANCH_CONTROLS.sort}
            sortOptions={[...BRANCH_SORT_OPTIONS]}
            onSortChange={(sort) =>
              setControls((c) => ({ ...c, sort: sort as BranchListControls['sort'] }))
            }
            sortAriaLabel="Sort branches"
            filterActiveCount={filterActiveCount}
            filterMenu={
              <FilterMenuPanel
                sections={[
                  {
                    id: 'status',
                    label: 'Status',
                    value: controls.status,
                    options: STATUS_OPTIONS,
                    onChange: (status) =>
                      setControls((c) => ({
                        ...c,
                        status: status as BranchStatusFilter,
                      })),
                  },
                ]}
              />
            }
            activeFilters={activeFilters}
            onClearAll={isFiltered ? clearAll : undefined}
          />
        ) : null}

        {!hasBranches ? (
          <div className="rounded-2xl border border-dashed border-border-default bg-surface-sunken/50 px-6 py-16 text-center">
            <MapPin size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
            <p className="mt-4 text-body-strong text-text-primary">No branches yet</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Add your first location to start assigning staff and services.
            </p>
            <Button className="mt-6" leadingIcon={<Plus size={16} />} onClick={openCreate}>
              Add branch
            </Button>
          </div>
        ) : !hasResults ? (
          <div className="rounded-2xl border border-border-subtle bg-surface-default px-6 py-14 text-center shadow-elevation-1">
            <SearchX size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
            <p className="mt-4 text-body-strong text-text-primary">No branches match</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Try a different search term or clear your filters.
            </p>
            <Button className="mt-6" variant="secondary" onClick={clearAll}>
              Clear filters
            </Button>
          </div>
        ) : (
          <div className="grid gap-4 lg:grid-cols-2">
            {filtered.map((branch, index) => (
              <motion.article
                key={branch.id}
                layout
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.22, delay: Math.min(index * 0.03, 0.15) }}
                className="group relative overflow-hidden rounded-2xl border border-border-subtle bg-surface-default shadow-elevation-1 transition-shadow hover:shadow-elevation-2"
              >
                <div
                  aria-hidden
                  className="absolute inset-x-0 top-0 h-1 bg-[linear-gradient(90deg,var(--color-teal-500),var(--color-violet-500))] opacity-80"
                />

                <div className="flex items-start justify-between gap-3 p-5 pb-3">
                  <div className="min-w-0 space-y-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <h4 className="truncate font-[family-name:var(--font-display)] text-body-strong text-text-primary">
                        {branch.name}
                      </h4>
                      {branch.code ? (
                        <Badge color="neutral" variant="soft" size="sm">
                          {branch.code}
                        </Badge>
                      ) : null}
                      <Badge
                        color={branch.isActive ? 'success' : 'warning'}
                        variant="soft"
                        size="sm"
                      >
                        {branch.isActive ? 'Active' : 'Inactive'}
                      </Badge>
                    </div>
                    <p className="text-body-sm text-text-secondary">{branch.address}</p>
                  </div>

                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <IconButton label="Branch actions" icon={<MoreHorizontal size={18} />} />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onSelect={() => openEdit(branch)} icon={<Pencil size={14} />}>
                        Edit
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        onSelect={() => onToggleActive(branch.id, !branch.isActive)}
                        icon={<Power size={14} />}
                      >
                        {branch.isActive ? 'Deactivate' : 'Activate'}
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        destructive
                        onSelect={() => setDeleteTarget(branch)}
                        icon={<Trash2 size={14} />}
                      >
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>

                <div className="space-y-2 border-t border-border-subtle px-5 py-4">
                  <div className="flex items-center gap-2 text-body-sm text-text-secondary">
                    <Phone size={14} className="shrink-0 text-icon-muted" />
                    <span className="tabular-nums">+{branch.phone}</span>
                  </div>
                  <div className="flex items-center gap-2 text-body-sm text-text-secondary">
                    <MapPin size={14} className="shrink-0 text-icon-muted" />
                    <span>{formatWorkingHoursSummary(branch.workingSchedule)}</span>
                  </div>
                  {branch.mapsUrl ? (
                    <a
                      href={
                        branch.mapsUrl.startsWith('http')
                          ? branch.mapsUrl
                          : `https://${branch.mapsUrl}`
                      }
                      target="_blank"
                      rel="noopener noreferrer"
                      className="focus-ring inline-flex items-center gap-1.5 text-body-sm text-text-link hover:underline"
                    >
                      View on maps
                      <ExternalLink size={12} />
                    </a>
                  ) : null}
                </div>
              </motion.article>
            ))}
          </div>
        )}
      </motion.div>

      <BranchFormDialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open)
          if (!open) setEditingBranch(null)
        }}
        mode={editingBranch ? 'edit' : 'create'}
        initialValues={
          editingBranch
            ? branchToFormValues(editingBranch)
            : {
              name: '',
              code: '',
              address: '',
              phone: '',
              mapsUrl: '',
              workingSchedule: emptyWorkingSchedule(),
            }
        }
        onSubmit={handleSubmit}
      />

      <ConfirmationDialog
        open={Boolean(deleteTarget)}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="Delete branch?"
        description={
          deleteTarget
            ? `${deleteTarget.name} will be removed from settings. Historical records linked to this branch are kept for audit.`
            : ''
        }
        confirmLabel="Delete branch"
        onConfirm={() => {
          if (deleteTarget) onRemove(deleteTarget.id)
          setDeleteTarget(null)
        }}
      />
    </>
  )
}
