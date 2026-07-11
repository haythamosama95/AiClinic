import { useMemo } from 'react'
import { Check, X } from 'lucide-react'
import { Tooltip } from '@/components/tooltip/Tooltip'
import { cn } from '@/lib/cn'
import { ROLE_LABELS, STAFF_ROLES } from '../constants'
import {
  categoryLabel,
  isPermissionGrantedInMap,
  permissionCategoryGroups,
  permissionLabel,
  type PermissionKey,
  type RoleGrantsMap,
} from '../permission-matrix'
import { ROLE_ACCENTS, ROLE_SUMMARIES } from '../role-theme'
import type { StaffRole } from '../types'

export type RolePermissionsMatrixProps = {
  grants: RoleGrantsMap
  savedGrants: RoleGrantsMap
  onToggle: (role: StaffRole, key: PermissionKey) => void
}

function GrantIndicator({ granted }: { granted: boolean }) {
  return (
    <span
      className={cn(
        'inline-flex size-5 items-center justify-center rounded-md border',
        granted
          ? 'border-transparent bg-action-primary text-action-primary-fg'
          : 'border-border-default bg-transparent text-icon-muted',
      )}
      aria-hidden
    >
      {granted ? <Check size={13} strokeWidth={2.5} /> : <X size={12} strokeWidth={2} />}
    </span>
  )
}

function GrantToggle({
  role,
  permissionKey,
  granted,
  dirty,
  onToggle,
}: {
  role: StaffRole
  permissionKey: PermissionKey
  granted: boolean
  dirty: boolean
  onToggle: () => void
}) {
  const label = `${granted ? 'Revoke' : 'Grant'} ${permissionLabel(permissionKey)} for ${ROLE_LABELS[role]}`

  return (
    <button
      type="button"
      onClick={onToggle}
      aria-label={label}
      aria-pressed={granted}
      className={cn(
        'focus-ring rounded-md p-1 transition-colors',
        dirty && 'bg-[color-mix(in_srgb,var(--color-teal-500)_12%,transparent)]',
        'hover:bg-surface-hover',
      )}
    >
      <GrantIndicator granted={granted} />
    </button>
  )
}

function MatrixColumnHeaders() {
  return (
    <div className="overflow-hidden rounded-xl border border-border-subtle bg-surface-default">
      <div className="flex min-w-[44rem]">
        <div className="min-w-[12rem] flex-[2.5] border-e border-border-subtle px-4 py-3">
          <span className="text-caption font-medium uppercase tracking-widest text-text-tertiary">
            Permission
          </span>
        </div>
        {STAFF_ROLES.map(({ value }) => (
          <div
            key={value}
            className="min-w-[6.5rem] flex-1 border-s border-border-subtle/70 px-2 py-0 text-center first:border-s-0"
          >
            <div className="overflow-hidden rounded-t-lg">
              <div aria-hidden className={cn('h-1 bg-gradient-to-r', ROLE_ACCENTS[value])} />
              <div className="px-2 py-3">
                <Tooltip content={ROLE_SUMMARIES[value]} side="bottom">
                  <button
                    type="button"
                    className="focus-ring mx-auto block max-w-full rounded-md px-1 text-center"
                  >
                    <span className="font-[family-name:var(--font-display)] text-body-sm font-semibold text-text-primary">
                      {ROLE_LABELS[value]}
                    </span>
                  </button>
                </Tooltip>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function CategoryCard({
  category,
  permissionKeys,
  grants,
  savedGrants,
  onToggle,
}: {
  category: string
  permissionKeys: PermissionKey[]
  grants: RoleGrantsMap
  savedGrants: RoleGrantsMap
  onToggle: (role: StaffRole, key: PermissionKey) => void
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-subtle bg-surface-default">
      <div className="border-b border-border-subtle px-4 py-3">
        <h4 className="font-[family-name:var(--font-display)] text-body-sm font-semibold text-text-primary">
          {categoryLabel(category)}
        </h4>
      </div>
      <div className="min-w-[44rem]">
        {permissionKeys.map((key, index) => (
          <div
            key={key}
            className={cn(
              'flex items-stretch',
              index < permissionKeys.length - 1 && 'border-b border-border-subtle/80',
            )}
          >
            <div className="flex min-w-[12rem] flex-[2.5] items-center border-e border-border-subtle px-4 py-3">
              <p className="text-body-sm font-medium text-text-primary">
                {permissionLabel(key)}
              </p>
            </div>
            {STAFF_ROLES.map(({ value }) => {
              const granted = isPermissionGrantedInMap(grants, value, key)
              const dirty =
                isPermissionGrantedInMap(grants, value, key) !==
                isPermissionGrantedInMap(savedGrants, value, key)

              return (
                <div
                  key={`${key}-${value}`}
                  className="flex min-w-[6.5rem] flex-1 items-center justify-center border-s border-border-subtle/70 px-2 py-3"
                >
                  <GrantToggle
                    role={value}
                    permissionKey={key}
                    granted={granted}
                    dirty={dirty}
                    onToggle={() => onToggle(value, key)}
                  />
                </div>
              )
            })}
          </div>
        ))}
      </div>
    </div>
  )
}

export function RolePermissionsMatrix({
  grants,
  savedGrants,
  onToggle,
}: RolePermissionsMatrixProps) {
  const groups = useMemo(() => permissionCategoryGroups(), [])

  return (
    <div className="space-y-4">
      <div className="overflow-x-auto">
        <MatrixColumnHeaders />
      </div>

      <div className="space-y-4">
        {groups.map((group) => (
          <div key={group.category} className="overflow-x-auto">
            <CategoryCard
              category={group.category}
              permissionKeys={group.permissionKeys}
              grants={grants}
              savedGrants={savedGrants}
              onToggle={onToggle}
            />
          </div>
        ))}
      </div>
    </div>
  )
}
