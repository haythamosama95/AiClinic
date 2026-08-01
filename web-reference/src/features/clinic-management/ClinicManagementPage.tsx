import { useState } from 'react'
import { Building2, MapPin, Settings, Shield, Stethoscope, Users } from 'lucide-react'
import { PageHeader } from '@/components/layout/PageHeader'
import { Tabs } from '@/components/navigation/Tabs'
import { OrganizationTab } from './components/OrganizationTab'
import { BranchesTab } from './components/BranchesTab'
import { StaffTab } from './components/StaffTab'
import { RolesTab } from './components/RolesTab'
import { ServicesTab } from './components/ServicesTab'
import { ClinicSettingsTab } from './components/ClinicSettingsTab'
import { useClinicManagementState } from './useClinicManagementState'
import type { BranchFormValues, StaffFormValues, StaffRole } from './types'
import type { ServiceFormValues } from './forms/ServiceFormFields'

const TAB_ITEMS = [
  { id: 'organization', label: 'Organization' },
  { id: 'branches', label: 'Branches' },
  { id: 'staff', label: 'Staff' },
  { id: 'roles', label: 'Roles' },
  { id: 'services', label: 'Services' },
  { id: 'settings', label: 'Settings' },
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

  const handleAddService = (values: ServiceFormValues) => {
    state.addService({
      id: newId('service'),
      name: values.name.trim(),
      price: values.price,
      allBranches: values.allBranches,
      branchIds: values.branchIds,
    })
  }

  const handleUpdateService = (id: string, values: ServiceFormValues) => {
    state.updateService(id, {
      name: values.name.trim(),
      price: values.price,
      allBranches: values.allBranches,
      branchIds: values.branchIds,
    })
  }

  const tabIcon = (id: TabId) => {
    switch (id) {
      case 'organization':
        return <Building2 size={15} strokeWidth={1.75} />
      case 'branches':
        return <MapPin size={15} strokeWidth={1.75} />
      case 'staff':
        return <Users size={15} strokeWidth={1.75} />
      case 'roles':
        return <Shield size={15} strokeWidth={1.75} />
      case 'services':
        return <Stethoscope size={15} strokeWidth={1.75} />
      case 'settings':
        return <Settings size={15} strokeWidth={1.75} />
    }
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
              {tabIcon(item.id)}
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

      {tab === 'services' ? (
        <ServicesTab
          services={state.services}
          branches={state.branches}
          organization={state.organization}
          onAdd={handleAddService}
          onUpdate={handleUpdateService}
          onRemove={state.removeService}
        />
      ) : null}

      {tab === 'settings' ? <ClinicSettingsTab /> : null}
    </div>
  )
}
