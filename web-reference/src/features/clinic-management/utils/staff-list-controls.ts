import { ROLE_LABELS } from '../constants'
import type { BranchRecord, StaffRecord, StaffRole } from '../types'

export type StaffRoleFilter = 'all' | StaffRole
export type StaffBranchFilter = 'all' | string
export type StaffSortKey = 'name-asc' | 'name-desc' | 'role-asc' | 'branch-asc'

export type StaffListControls = {
  search: string
  role: StaffRoleFilter
  branchId: StaffBranchFilter
  sort: StaffSortKey
}

export const STAFF_SORT_OPTIONS = [
  { value: 'name-asc', label: 'Name A–Z' },
  { value: 'name-desc', label: 'Name Z–A' },
  { value: 'role-asc', label: 'Role A–Z' },
  { value: 'branch-asc', label: 'Branch A–Z' },
] as const

export function filterAndSortStaff(
  staff: StaffRecord[],
  branches: BranchRecord[],
  controls: StaffListControls,
): StaffRecord[] {
  let rows = [...staff]
  const q = controls.search.trim().toLowerCase()

  if (q) {
    rows = rows.filter(
      (s) =>
        s.fullName.toLowerCase().includes(q) ||
        s.username.toLowerCase().includes(q) ||
        s.phone.includes(q) ||
        ROLE_LABELS[s.role].toLowerCase().includes(q),
    )
  }

  if (controls.role !== 'all') {
    rows = rows.filter((s) => s.role === controls.role)
  }

  if (controls.branchId !== 'all') {
    rows = rows.filter((s) => s.branchIds.includes(controls.branchId))
  }

  const branchName = (id: string | null) =>
    branches.find((b) => b.id === id)?.name ?? ''

  switch (controls.sort) {
    case 'name-desc':
      rows.sort((a, b) => b.fullName.localeCompare(a.fullName))
      break
    case 'role-asc':
      rows.sort(
        (a, b) =>
          ROLE_LABELS[a.role].localeCompare(ROLE_LABELS[b.role]) ||
          a.fullName.localeCompare(b.fullName),
      )
      break
    case 'branch-asc':
      rows.sort(
        (a, b) =>
          branchName(a.primaryBranchId).localeCompare(branchName(b.primaryBranchId)) ||
          a.fullName.localeCompare(b.fullName),
      )
      break
    default:
      rows.sort((a, b) => a.fullName.localeCompare(b.fullName))
  }

  return rows
}

export const DEFAULT_STAFF_CONTROLS: StaffListControls = {
  search: '',
  role: 'all',
  branchId: 'all',
  sort: 'name-asc',
}
