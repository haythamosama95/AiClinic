import { useCallback, useMemo, useState } from 'react'
import { Save, X } from 'lucide-react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { RolePermissionsMatrix } from './RolePermissionsMatrix'
import {
  canTogglePermissionGrant,
  cloneRoleGrants,
  createDefaultRoleGrants,
  roleGrantsEqual,
  type PermissionKey,
} from '../permission-matrix'
import type { StaffRole } from '../types'

export function RolesTab() {
  const [savedGrants, setSavedGrants] = useState(createDefaultRoleGrants)
  const [draftGrants, setDraftGrants] = useState(createDefaultRoleGrants)

  const hasChanges = useMemo(
    () => !roleGrantsEqual(savedGrants, draftGrants),
    [savedGrants, draftGrants],
  )

  const toggleGrant = useCallback((role: StaffRole, key: PermissionKey) => {
    setDraftGrants((prev) => {
      const next = cloneRoleGrants(prev)
      const granted = next[role].has(key)
      const nextGranted = !granted

      if (!canTogglePermissionGrant(role, key, nextGranted)) {
        return prev
      }

      if (nextGranted) {
        next[role].add(key)
      } else {
        next[role].delete(key)
      }

      return next
    })
  }, [])

  const discard = () => {
    setDraftGrants(cloneRoleGrants(savedGrants))
  }

  const save = () => {
    setSavedGrants(cloneRoleGrants(draftGrants))
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22 }}
      className="space-y-6"
    >
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-2xl space-y-1">
          <h3 className="font-[family-name:var(--font-display)] text-h3 text-text-primary">
            Roles & permissions
          </h3>
          <p className="text-body-sm text-text-secondary">
            Built-in roles and their access grants. Assign a role when you create or edit a
            staff account.
          </p>
        </div>
        <div className="flex shrink-0 gap-2">
          {hasChanges ? (
            <Button variant="secondary" size="sm" leadingIcon={<X size={14} />} onClick={discard}>
              Discard
            </Button>
          ) : null}
          <Button
            size="sm"
            leadingIcon={<Save size={14} />}
            onClick={save}
            disabled={!hasChanges}
          >
            Save changes
          </Button>
        </div>
      </div>

      <RolePermissionsMatrix
        grants={draftGrants}
        savedGrants={savedGrants}
        onToggle={toggleGrant}
      />
    </motion.div>
  )
}
