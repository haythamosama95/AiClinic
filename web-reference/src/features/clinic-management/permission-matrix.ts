import type { StaffRole } from './types'

/** Permission keys aligned with `roles_permissions` seed (settings → Staff roles). */
export const PERMISSION_KEYS = [
  'settings.manage_staff',
  'settings.manage_branches',
  'settings.billing.manage',
  'patients.view',
  'patients.create',
  'patients.edit',
  'patients.delete',
  'appointments.create',
  'appointments.cancel',
  'appointments.read',
  'visits.create',
  'visits.edit_soap',
  'visits.upload_attachment',
  'invoices.view',
  'invoices.create',
  'invoices.apply_discount',
  'invoices.void',
  'payments.record',
  'payments.refund',
  'insurance.manage',
  'shifts.manage',
  'services.view',
  'services.manage',
  'analytics.view',
  'ai.access',
] as const

export type PermissionKey = (typeof PERMISSION_KEYS)[number]

export type PermissionCategoryGroup = {
  category: string
  permissionKeys: PermissionKey[]
}

/** Default seed grants per role (settings role catalog). */
const DEFAULT_ROLE_GRANTS: Record<StaffRole, ReadonlySet<PermissionKey>> = {
  administrator: new Set([
    'settings.manage_staff',
    'settings.manage_branches',
    'settings.billing.manage',
    'patients.view',
    'patients.create',
    'patients.edit',
    'patients.delete',
    'appointments.create',
    'appointments.cancel',
    'appointments.read',
    'visits.create',
    'visits.edit_soap',
    'visits.upload_attachment',
    'invoices.view',
    'invoices.create',
    'invoices.apply_discount',
    'invoices.void',
    'payments.record',
    'payments.refund',
    'insurance.manage',
    'shifts.manage',
    'services.view',
    'services.manage',
    'analytics.view',
    'ai.access',
  ]),
  doctor: new Set([
    'patients.view',
    'patients.create',
    'appointments.create',
    'appointments.cancel',
    'appointments.read',
    'visits.create',
    'visits.edit_soap',
    'visits.upload_attachment',
    'ai.access',
  ]),
  receptionist: new Set([
    'patients.view',
    'appointments.create',
    'appointments.cancel',
    'appointments.read',
    'invoices.view',
    'invoices.create',
    'payments.record',
  ]),
  lab_staff: new Set([
    'patients.view',
    'appointments.read',
    'visits.upload_attachment',
  ]),
}

export type RoleGrantsMap = Record<StaffRole, Set<PermissionKey>>

export function createDefaultRoleGrants(): RoleGrantsMap {
  return {
    administrator: new Set(DEFAULT_ROLE_GRANTS.administrator),
    doctor: new Set(DEFAULT_ROLE_GRANTS.doctor),
    receptionist: new Set(DEFAULT_ROLE_GRANTS.receptionist),
    lab_staff: new Set(DEFAULT_ROLE_GRANTS.lab_staff),
  }
}

export function cloneRoleGrants(grants: RoleGrantsMap): RoleGrantsMap {
  return {
    administrator: new Set(grants.administrator),
    doctor: new Set(grants.doctor),
    receptionist: new Set(grants.receptionist),
    lab_staff: new Set(grants.lab_staff),
  }
}

export function roleGrantsEqual(a: RoleGrantsMap, b: RoleGrantsMap): boolean {
  for (const role of Object.keys(a) as StaffRole[]) {
    const setA = a[role]
    const setB = b[role]
    if (setA.size !== setB.size) return false
    for (const key of setA) {
      if (!setB.has(key)) return false
    }
  }
  return true
}

export function isPermissionGrantedInMap(
  grants: RoleGrantsMap,
  role: StaffRole,
  key: PermissionKey,
): boolean {
  return grants[role].has(key)
}

/** `settings.billing.manage` can only be granted to administrators. */
export function canTogglePermissionGrant(
  role: StaffRole,
  key: PermissionKey,
  nextGranted: boolean,
): boolean {
  if (key === 'settings.billing.manage' && nextGranted && role !== 'administrator') {
    return false
  }
  return true
}

export function permissionCategory(key: PermissionKey): string {
  const dot = key.indexOf('.')
  return dot === -1 ? key : key.slice(0, dot)
}

export function categoryLabel(category: string): string {
  if (category === 'ai') return 'AI'
  if (!category) return category
  return category.charAt(0).toUpperCase() + category.slice(1)
}

export function permissionLabel(key: PermissionKey): string {
  const dot = key.indexOf('.')
  const action = dot === -1 ? key : key.slice(dot + 1)
  if (!action) return key
  return action
    .split('_')
    .map((word) => (word ? word.charAt(0).toUpperCase() + word.slice(1) : word))
    .join(' ')
}

export function isPermissionGranted(role: StaffRole, key: PermissionKey): boolean {
  return DEFAULT_ROLE_GRANTS[role].has(key)
}

export function permissionCategoryGroups(): PermissionCategoryGroup[] {
  const byCategory = new Map<string, PermissionKey[]>()

  for (const key of PERMISSION_KEYS) {
    const category = permissionCategory(key)
    const list = byCategory.get(category) ?? []
    list.push(key)
    byCategory.set(category, list)
  }

  return [...byCategory.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([category, permissionKeys]) => ({
      category,
      permissionKeys: [...permissionKeys].sort(),
    }))
}
