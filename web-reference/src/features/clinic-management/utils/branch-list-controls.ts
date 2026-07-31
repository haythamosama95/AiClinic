import type { BranchRecord } from '../types'

export type BranchStatusFilter = 'all' | 'active' | 'inactive'
export type BranchSortKey = 'name-asc' | 'name-desc' | 'code-asc' | 'status'

export type BranchListControls = {
  search: string
  status: BranchStatusFilter
  sort: BranchSortKey
}

export const BRANCH_SORT_OPTIONS = [
  { value: 'name-asc', label: 'Name A–Z' },
  { value: 'name-desc', label: 'Name Z–A' },
  { value: 'code-asc', label: 'Code A–Z' },
  { value: 'status', label: 'Active first' },
] as const

export function filterAndSortBranches(
  branches: BranchRecord[],
  controls: BranchListControls,
): BranchRecord[] {
  let rows = [...branches]
  const q = controls.search.trim().toLowerCase()

  if (q) {
    rows = rows.filter(
      (b) =>
        b.name.toLowerCase().includes(q) ||
        b.code.toLowerCase().includes(q) ||
        b.address.toLowerCase().includes(q) ||
        b.phone.includes(q),
    )
  }

  if (controls.status === 'active') {
    rows = rows.filter((b) => b.isActive)
  } else if (controls.status === 'inactive') {
    rows = rows.filter((b) => !b.isActive)
  }

  switch (controls.sort) {
    case 'name-desc':
      rows.sort((a, b) => b.name.localeCompare(a.name))
      break
    case 'code-asc':
      rows.sort((a, b) => a.code.localeCompare(b.code))
      break
    case 'status':
      rows.sort((a, b) => Number(b.isActive) - Number(a.isActive) || a.name.localeCompare(b.name))
      break
    default:
      rows.sort((a, b) => a.name.localeCompare(b.name))
  }

  return rows
}

export const DEFAULT_BRANCH_CONTROLS: BranchListControls = {
  search: '',
  status: 'all',
  sort: 'name-asc',
}
