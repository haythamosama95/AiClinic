import { useState } from 'react'
import { Pencil, Save, X } from 'lucide-react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { ClinicHero } from './ClinicHero'
import {
  OrganizationFormFields,
  validateOrganization,
} from '../forms/OrganizationFormFields'
import type { OrganizationProfile } from '../types'

export type OrganizationTabProps = {
  organization: OrganizationProfile
  onSave: (next: OrganizationProfile) => void
  branchCount: number
  staffCount: number
  activeBranchCount: number
}

export function OrganizationTab({
  organization,
  onSave,
  branchCount,
  staffCount,
  activeBranchCount,
}: OrganizationTabProps) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(organization)
  const [errors, setErrors] = useState<Partial<Record<keyof OrganizationProfile, string>>>({})

  const startEdit = () => {
    setDraft(organization)
    setErrors({})
    setEditing(true)
  }

  const cancel = () => {
    setDraft(organization)
    setErrors({})
    setEditing(false)
  }

  const save = () => {
    const nextErrors = validateOrganization(draft)
    if (Object.keys(nextErrors).length > 0) {
      setErrors(nextErrors)
      return
    }
    onSave(draft)
    setEditing(false)
    setErrors({})
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22 }}
      className="space-y-6"
    >
      <ClinicHero
        organization={organization}
        branchCount={branchCount}
        staffCount={staffCount}
        activeBranchCount={activeBranchCount}
      />

      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-xl space-y-1">
          <h3 className="font-[family-name:var(--font-display)] text-h3 text-text-primary">
            Organization profile
          </h3>
          <p className="text-body-sm text-text-secondary">
            Clinic-wide defaults for billing, scheduling, and branding. Branch settings
            override per location.
          </p>
        </div>
        <div className="flex shrink-0 gap-2">
          {editing ? (
            <>
              <Button variant="secondary" size="sm" leadingIcon={<X size={14} />} onClick={cancel}>
                Cancel
              </Button>
              <Button size="sm" leadingIcon={<Save size={14} />} onClick={save}>
                Save changes
              </Button>
            </>
          ) : (
            <Button
              variant="secondary"
              size="sm"
              leadingIcon={<Pencil size={14} />}
              onClick={startEdit}
            >
              Edit organization
            </Button>
          )}
        </div>
      </div>

      <div className="rounded-2xl border border-border-subtle bg-surface-default p-6 shadow-elevation-1 sm:p-8">
        <OrganizationFormFields
          values={editing ? draft : organization}
          onChange={(patch) => setDraft((prev) => ({ ...prev, ...patch }))}
          disabled={!editing}
          errors={editing ? errors : {}}
        />
      </div>
    </motion.div>
  )
}
