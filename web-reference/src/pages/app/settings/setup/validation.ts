import type { BranchDraft, OrganizationDraft, ServiceDraft, StaffDraft } from '@/data/settings'

export type StepErrors = Record<string, string>

export function validateOrganization(org: OrganizationDraft): StepErrors {
  const errors: StepErrors = {}
  if (!org.name.trim()) errors.name = 'Organization name is required'
  if (!org.timezone) errors.timezone = 'Select a timezone'
  if (!org.currency) errors.currency = 'Select a currency'
  return errors
}

export function validateBranches(branches: BranchDraft[]): StepErrors {
  const errors: StepErrors = {}
  if (branches.length === 0) {
    errors._form = 'Add at least one branch'
    return errors
  }

  branches.forEach((branch, index) => {
    Object.assign(errors, validateSingleBranch(branch, index))
  })

  return errors
}

export function validateSingleBranch(branch: BranchDraft, index: number): StepErrors {
  const errors: StepErrors = {}
  const prefix = `branch-${index}`

  if (!branch.name.trim()) errors[`${prefix}-name`] = 'Branch name is required'
  if (!branch.code.trim()) errors[`${prefix}-code`] = 'Branch code is required'
  if (!branch.mobile.trim()) errors[`${prefix}-mobile`] = 'Mobile number is required'
  if (!branch.mapLocation.trim()) errors[`${prefix}-map`] = 'Map location is required'

  const hasOpenDay = branch.workingDays.some((d) => d.enabled)
  if (!hasOpenDay) errors[`${prefix}-hours`] = 'Enable at least one working day'

  branch.workingDays.forEach((day) => {
    if (!day.enabled) return
    if (day.openTime >= day.closeTime) {
      errors[`${prefix}-${day.day}-time`] = 'Closing time must be after opening'
    }
  })

  return errors
}

export function validateStaff(staff: StaffDraft[], branchCount: number): StepErrors {
  const errors: StepErrors = {}
  if (staff.length === 0) {
    errors._form = 'Add at least one staff member'
    return errors
  }

  staff.forEach((member, index) => {
    const prefix = `staff-${index}`
    if (!member.name.trim()) errors[`${prefix}-name`] = 'Name is required'
    if (!member.mobile.trim()) errors[`${prefix}-mobile`] = 'Mobile is required'
    if (!member.username.trim()) errors[`${prefix}-username`] = 'Username is required'
    if (member.password.length < 6) errors[`${prefix}-password`] = 'Password must be at least 6 characters'
    if (!member.role) errors[`${prefix}-role`] = 'Select a role'
    if (branchCount > 0 && member.branchIds.length === 0) {
      errors[`${prefix}-branches`] = 'Assign at least one branch'
    }
  })

  return errors
}

export function validateServices(services: ServiceDraft[]): StepErrors {
  const errors: StepErrors = {}
  if (services.length === 0) {
    errors._form = 'Add at least one service'
    return errors
  }

  services.forEach((service, index) => {
    const prefix = `service-${index}`
    if (!service.name.trim()) errors[`${prefix}-name`] = 'Service name is required'
    if (service.price === null || service.price < 0) {
      errors[`${prefix}-price`] = 'Enter a valid price'
    }
  })

  return errors
}

export function hasErrors(errors: StepErrors): boolean {
  return Object.keys(errors).length > 0
}
