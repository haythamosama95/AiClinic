import type { BranchDraft, OrganizationDraft, ServiceDraft, StaffDraft } from '@/data/settings'

export type StepErrors = Record<string, string>

const NATIONAL_PHONE_LENGTH = 10
const BRANCH_CODE_MAX_LENGTH = 20
const BRANCH_CODE_PATTERN = /^[A-Z0-9]+$/
const USERNAME_PATTERN = /^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$/

function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase()
}

function validateNationalPhone(raw: string): string | null {
  const trimmed = raw.trim()
  if (!trimmed) return 'Mobile number is required'
  if (!/^\d+$/.test(trimmed)) return 'Phone must contain numbers only'
  if (trimmed.length !== NATIONAL_PHONE_LENGTH) return 'Enter a valid 10-digit mobile number'
  return null
}

function validateBranchCode(raw: string): string | null {
  const trimmed = raw.trim()
  if (!trimmed) return 'Branch code is required'
  const normalized = trimmed.toUpperCase()
  if (normalized.length > BRANCH_CODE_MAX_LENGTH) {
    return `Branch code must be ${BRANCH_CODE_MAX_LENGTH} characters or fewer`
  }
  if (!BRANCH_CODE_PATTERN.test(normalized)) return 'Use letters and numbers only'
  return null
}

function isValidMapsUrl(raw: string): boolean {
  const trimmed = raw.trim()
  if (!trimmed) return false

  let uri: URL
  try {
    uri = trimmed.includes('://') ? new URL(trimmed) : new URL(`https://${trimmed}`)
  } catch {
    return false
  }

  if (!uri.hostname || uri.hostname.includes(' ')) return false
  if (trimmed.includes('://') && uri.protocol !== 'http:' && uri.protocol !== 'https:') return false
  return uri.hostname.includes('.')
}

function validateMapsUrl(raw: string): string | null {
  const trimmed = raw.trim()
  if (!trimmed) return 'Map location is required'
  if (!isValidMapsUrl(trimmed)) return 'Enter a valid website or maps link'
  return null
}

function validateStaffUsername(raw: string): string | null {
  const normalized = normalizeUsername(raw)
  if (!normalized) return 'Username is required'
  if (normalized.includes('@')) return 'Enter a valid username'
  if (normalized.length < 3 || normalized.length > 32) return 'Enter a valid username'
  if (!USERNAME_PATTERN.test(normalized)) {
    return 'Username may use letters, numbers, underscore, and hyphen'
  }
  return null
}

function validateInitialPassword(raw: string): string | null {
  if (!raw) return 'Password is required'
  if (raw.length < 8) return 'Password must be at least 8 characters'
  if (!/[A-Za-z]/.test(raw)) return 'Password must contain at least one letter'
  return null
}

function validateServiceName(raw: string): string | null {
  const trimmed = raw.trim()
  if (!trimmed) return 'Service name is required'
  if (trimmed.length > 200) return 'Service name cannot exceed 200 characters'
  return null
}

function validateServicePrice(price: number | null): string | null {
  if (price === null || Number.isNaN(price) || !Number.isFinite(price)) {
    return 'Enter a valid price'
  }
  if (price < 0) return 'Price must be zero or greater'
  const cents = Math.round(price * 100)
  if (Math.abs(cents / 100 - price) > 0.001) {
    return 'Enter a valid price with at most two decimal places'
  }
  return null
}

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
    Object.assign(errors, validateSingleBranch(branch, index, branches))
  })

  return errors
}

export function validateSingleBranch(
  branch: BranchDraft,
  index: number,
  allBranches?: BranchDraft[],
): StepErrors {
  const errors: StepErrors = {}
  const prefix = `branch-${index}`

  if (!branch.name.trim()) errors[`${prefix}-name`] = 'Branch name is required'

  const codeError = validateBranchCode(branch.code)
  if (codeError) {
    errors[`${prefix}-code`] = codeError
  } else if (allBranches) {
    const normalizedCode = branch.code.trim().toUpperCase()
    const duplicate = allBranches.some(
      (other, otherIndex) =>
        otherIndex !== index && other.code.trim().toUpperCase() === normalizedCode,
    )
    if (duplicate) errors[`${prefix}-code`] = 'Branch code must be unique'
  }

  const mobileError = validateNationalPhone(branch.mobile)
  if (mobileError) errors[`${prefix}-mobile`] = mobileError

  const mapError = validateMapsUrl(branch.mapLocation)
  if (mapError) errors[`${prefix}-map`] = mapError

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

  const seenUsernames = new Set<string>()

  staff.forEach((member, index) => {
    const prefix = `staff-${index}`
    if (!member.name.trim()) errors[`${prefix}-name`] = 'Name is required'

    const mobileError = validateNationalPhone(member.mobile)
    if (mobileError) errors[`${prefix}-mobile`] = mobileError

    const usernameError = validateStaffUsername(member.username)
    if (usernameError) {
      errors[`${prefix}-username`] = usernameError
    } else {
      const normalizedUsername = normalizeUsername(member.username)
      if (seenUsernames.has(normalizedUsername)) {
        errors[`${prefix}-username`] = 'Usernames must be unique'
      } else {
        seenUsernames.add(normalizedUsername)
      }
    }

    const passwordError = validateInitialPassword(member.password)
    if (passwordError) errors[`${prefix}-password`] = passwordError

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

  const seenNames = new Set<string>()

  services.forEach((service, index) => {
    const prefix = `service-${index}`
    const nameError = validateServiceName(service.name)
    if (nameError) {
      errors[`${prefix}-name`] = nameError
    } else {
      const normalizedName = service.name.trim().toLowerCase()
      if (seenNames.has(normalizedName)) {
        errors[`${prefix}-name`] = 'Service names must be unique'
      } else {
        seenNames.add(normalizedName)
      }
    }

    const priceError = validateServicePrice(service.price)
    if (priceError) errors[`${prefix}-price`] = priceError
  })

  return errors
}

export function hasErrors(errors: StepErrors): boolean {
  return Object.keys(errors).length > 0
}
