import { FormField } from '@/components/ui/form-field/FormField'
import { MultiSelect } from '@/components/ui/multi-select/MultiSelect'
import { PasswordInput } from '@/components/ui/password-input/PasswordInput'
import { Select } from '@/components/ui/select/Select'
import { TextInput } from '@/components/ui/text-input/TextInput'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import {
  STAFF_PASSWORD_HINT,
  STAFF_ROLES,
  STAFF_USERNAME_HINT,
} from '../constants'
import type { BranchRecord, StaffFormValues, StaffRole } from '../types'

export type StaffFormFieldsProps = {
  mode: 'create' | 'edit'
  values: StaffFormValues
  onChange: (patch: Partial<StaffFormValues>) => void
  branches: BranchRecord[]
  disabled?: boolean
  errors?: Partial<Record<keyof StaffFormValues, string>>
}

function branchLabel(branch: BranchRecord): string {
  return branch.code ? `${branch.name} (${branch.code})` : branch.name
}

export function StaffFormFields({
  mode,
  values,
  onChange,
  branches,
  disabled,
  errors = {},
}: StaffFormFieldsProps) {
  const activeBranches = branches.filter((b) => b.isActive)
  const branchOptions: ComboboxItem[] = activeBranches.map((b) => ({
    id: b.id,
    label: branchLabel(b),
  }))

  const selectedBranches = branchOptions.filter((o) => values.branchIds.includes(o.id))

  const primaryOptions = selectedBranches.map((b) => ({
    value: b.id,
    label: b.label,
  }))

  return (
    <div className="space-y-5">
      <div className="grid gap-5 sm:grid-cols-2">
        <FormField id="staff-name" label="Full name" required error={errors.fullName}>
          <TextInput
            id="staff-name"
            value={values.fullName}
            onChange={(e) => onChange({ fullName: e.target.value })}
            placeholder="Enter full name"
            disabled={disabled}
            invalid={Boolean(errors.fullName)}
          />
        </FormField>

        <FormField
          id="staff-phone"
          label={mode === 'create' ? 'Phone number' : 'Phone'}
          required={mode === 'create'}
          error={errors.phone}
        >
          <TextInput
            id="staff-phone"
            type="tel"
            inputMode="numeric"
            value={values.phone}
            onChange={(e) => onChange({ phone: e.target.value.replace(/\D/g, '') })}
            placeholder="Numbers only"
            disabled={disabled}
            invalid={Boolean(errors.phone)}
          />
        </FormField>

        {mode === 'create' ? (
          <>
            <FormField
              id="staff-username"
              label="Username"
              required
              hint={STAFF_USERNAME_HINT}
              error={errors.username}
            >
              <TextInput
                id="staff-username"
                value={values.username}
                onChange={(e) => onChange({ username: e.target.value })}
                placeholder="Staff username"
                disabled={disabled}
                invalid={Boolean(errors.username)}
              />
            </FormField>

            <FormField
              id="staff-password"
              label="Initial password"
              required
              hint={`${STAFF_PASSWORD_HINT} Shown once after creation so you can share it with the staff member.`}
              error={errors.password}
            >
              <PasswordInput
                id="staff-password"
                value={values.password}
                onChange={(e) => onChange({ password: e.target.value })}
                placeholder="••••••••"
                disabled={disabled}
                invalid={Boolean(errors.password)}
              />
            </FormField>
          </>
        ) : null}
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <FormField id="staff-role" label="Role" required error={errors.role}>
          <Select
            id="staff-role"
            value={values.role || undefined}
            onValueChange={(role) => onChange({ role: role as StaffRole })}
            options={STAFF_ROLES.map((r) => ({ value: r.value, label: r.label }))}
            placeholder="Select a role"
            disabled={disabled}
            invalid={Boolean(errors.role)}
          />
        </FormField>

        <FormField
          id="staff-branches"
          label="Branch assignments"
          required
          error={errors.branchIds as string | undefined}
        >
          {activeBranches.length === 0 ? (
            <p className="text-body-sm text-text-secondary">
              No active branches are available. Create or reactivate a branch first.
            </p>
          ) : (
            <MultiSelect
              id="staff-branches"
              options={branchOptions}
              value={selectedBranches}
              onValueChange={(items) => {
                const ids = items.map((i) => i.id)
                const primaryStillValid =
                  values.primaryBranchId && ids.includes(values.primaryBranchId)
                onChange({
                  branchIds: ids,
                  primaryBranchId: primaryStillValid
                    ? values.primaryBranchId
                    : ids[0] ?? null,
                })
              }}
              placeholder="Select branches"
              disabled={disabled}
              invalid={Boolean(errors.branchIds)}
            />
          )}
        </FormField>
      </div>

      {values.branchIds.length > 1 ? (
        <FormField id="staff-primary" label="Primary branch">
          <Select
            id="staff-primary"
            value={values.primaryBranchId ?? undefined}
            onValueChange={(id) => onChange({ primaryBranchId: id })}
            options={primaryOptions}
            disabled={disabled}
          />
        </FormField>
      ) : null}

      {mode === 'edit' ? (
        <div className="rounded-xl border border-border-subtle bg-surface-sunken/60 p-5">
          <h3 className="text-body-strong text-text-primary">Login credentials</h3>
          <div className="mt-4 grid gap-5 sm:grid-cols-2">
            <FormField
              id="staff-username-edit"
              label="Username"
              required
              hint={STAFF_USERNAME_HINT}
              error={errors.username}
            >
              <TextInput
                id="staff-username-edit"
                value={values.username}
                onChange={(e) => onChange({ username: e.target.value })}
                placeholder="Staff username"
                disabled={disabled}
                invalid={Boolean(errors.username)}
              />
            </FormField>

            <FormField
              id="staff-password-edit"
              label="New password"
              hint={`${STAFF_PASSWORD_HINT} Leave blank to keep the current password.`}
              error={errors.password}
            >
              <PasswordInput
                id="staff-password-edit"
                value={values.password}
                onChange={(e) => onChange({ password: e.target.value })}
                placeholder="••••••••"
                disabled={disabled}
                invalid={Boolean(errors.password)}
              />
            </FormField>
          </div>
        </div>
      ) : null}
    </div>
  )
}

function validateUsername(username: string): string | undefined {
  if (!username.trim()) return 'Username is required'
  if (username.length < 3 || username.length > 32) {
    return 'Username must be 3–32 characters'
  }
  if (!/^[a-zA-Z][a-zA-Z0-9._-]*$/.test(username)) {
    return 'Username format is invalid'
  }
  return undefined
}

function validatePassword(password: string, required: boolean): string | undefined {
  if (!password) return required ? 'Password is required' : undefined
  if (password.length < 8) return 'Password must be at least 8 characters'
  if (!/[A-Z]/.test(password)) return 'Password must include an uppercase letter'
  if (!/[a-z]/.test(password)) return 'Password must include a lowercase letter'
  if (!/\d/.test(password)) return 'Password must include a number'
  return undefined
}

export function validateStaff(
  values: StaffFormValues,
  mode: 'create' | 'edit',
): Partial<Record<keyof StaffFormValues, string>> {
  const errors: Partial<Record<keyof StaffFormValues, string>> = {}
  if (!values.fullName.trim()) errors.fullName = 'Full name is required'
  if (mode === 'create') {
    if (!values.phone.trim()) errors.phone = 'Phone is required'
    else if (!/^\d+$/.test(values.phone)) errors.phone = 'Phone must contain numbers only'
  } else if (values.phone && !/^\d+$/.test(values.phone)) {
    errors.phone = 'Phone must contain numbers only'
  }
  const usernameError = validateUsername(values.username)
  if (usernameError) errors.username = usernameError
  const passwordError = validatePassword(values.password, mode === 'create')
  if (passwordError) errors.password = passwordError
  if (!values.role) errors.role = 'Select a role'
  if (values.branchIds.length === 0) {
    errors.branchIds = 'Select at least one branch assignment' as never
  }
  return errors
}

export function emptyStaffFormValues(): StaffFormValues {
  return {
    fullName: '',
    phone: '',
    username: '',
    password: '',
    role: '',
    branchIds: [],
    primaryBranchId: null,
  }
}

export function staffToFormValues(staff: {
  fullName: string
  phone: string
  username: string
  role: StaffRole
  branchIds: string[]
  primaryBranchId: string | null
}): StaffFormValues {
  return {
    fullName: staff.fullName,
    phone: staff.phone,
    username: staff.username,
    password: '',
    role: staff.role,
    branchIds: [...staff.branchIds],
    primaryBranchId: staff.primaryBranchId,
  }
}
