import { useState } from 'react'
import { Building2, MapPin, Shield, Users } from 'lucide-react'
import { PageHeader } from '@/components/layout/PageHeader'
import { Tabs } from '@/components/navigation/Tabs'
import { OrganizationTab } from './components/OrganizationTab'
import { BranchesTab } from './components/BranchesTab'
import { StaffTab } from './components/StaffTab'
import { RolesTab } from './components/RolesTab'
import { useClinicManagementState } from './useClinicManagementState'
import type { BranchFormValues, StaffFormValues, StaffRole } from './types'

const TAB_ITEMS = [
  { id: 'organization', label: 'Organization' },
  { id: 'branches', label: 'Branches' },
  { id: 'staff', label: 'Staff' },
  { id: 'roles', label: 'Roles' },
] as const

type TabId = (typeof TAB_ITEMS)[number]['id']

function newId(prefix: string): string {
  return `${prefix}-${crypto.randomUUID().slice(0, 8)}`
}

export function ClinicManagementPage() {
  const [tab, setTab] = useState<TabId>('organization')
  const state = useClinicManagementState()

  const activeBranches = state.branches.filter((b) => b.isActive).length

  const handleAddBranch = (values: BranchFormValues) => {
    state.addBranch({
      id: newId('branch'),
      ...values,
      isActive: true,
    })
  }

  const handleUpdateBranch = (id: string, values: BranchFormValues) => {
    state.updateBranch(id, values)
  }

  const handleAddStaff = (values: StaffFormValues) => {
    if (!values.role) return
    state.addStaff({
      id: newId('staff'),
      fullName: values.fullName.trim(),
      phone: values.phone,
      username: values.username.trim(),
      role: values.role as StaffRole,
      branchIds: values.branchIds,
      primaryBranchId: values.primaryBranchId,
      isActive: true,
    })
  }

  const handleUpdateStaff = (id: string, values: StaffFormValues) => {
    if (!values.role) return
    state.updateStaff(id, {
      fullName: values.fullName.trim(),
      phone: values.phone,
      username: values.username.trim(),
      role: values.role as StaffRole,
      branchIds: values.branchIds,
      primaryBranchId: values.primaryBranchId,
    })
  }

  return (
    <div className="space-y-8 pb-8">
      <PageHeader
        title="Clinic Management"
        description="Organization identity, locations, team accounts, and access roles."
      />

      <Tabs
        items={TAB_ITEMS.map((item) => ({
          ...item,
          label: (
            <span className="inline-flex items-center gap-2">
              {item.id === 'organization' ? (
                <Building2 size={15} strokeWidth={1.75} />
              ) : item.id === 'branches' ? (
                <MapPin size={15} strokeWidth={1.75} />
              ) : item.id === 'staff' ? (
                <Users size={15} strokeWidth={1.75} />
              ) : (
                <Shield size={15} strokeWidth={1.75} />
              )}
              {item.label}
            </span>
          ),
        }))}
        value={tab}
        onChange={(id) => setTab(id as TabId)}
        aria-label="Clinic management sections"
      />

      {tab === 'organization' ? (
        <OrganizationTab
          organization={state.organization}
          onSave={state.updateOrganization}
          branchCount={state.branches.length}
          staffCount={state.staff.length}
          activeBranchCount={activeBranches}
        />
      ) : null}

      {tab === 'branches' ? (
        <BranchesTab
          branches={state.branches}
          onAdd={handleAddBranch}
          onUpdate={handleUpdateBranch}
          onRemove={state.removeBranch}
          onToggleActive={(id, isActive) => state.updateBranch(id, { isActive })}
        />
      ) : null}

      {tab === 'staff' ? (
        <StaffTab
          staff={state.staff}
          branches={state.branches}
          onAdd={handleAddStaff}
          onUpdate={handleUpdateStaff}
          onRemove={state.removeStaff}
        />
      ) : null}

      {tab === 'roles' ? <RolesTab /> : null}
    </div>
  )
}
