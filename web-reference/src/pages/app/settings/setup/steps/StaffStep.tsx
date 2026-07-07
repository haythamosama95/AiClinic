import { Users } from 'lucide-react'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { FormField } from '@/components/ui/form-field/FormField'
import { MultiSelect } from '@/components/ui/multi-select/MultiSelect'
import { PasswordInput } from '@/components/ui/password-input/PasswordInput'
import { PhoneInput } from '@/components/ui/phone-input/PhoneInput'
import { Select } from '@/components/ui/select/Select'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { createEmptyStaff, STAFF_ROLE_OPTIONS, type StaffDraft } from '@/data/settings'
import { EntityList } from '../../components/EntityList'
import { useSetup } from '../../SetupContext'
import type { StepErrors } from '../validation'

export type StaffStepProps = {
  errors: StepErrors
}

export function StaffStep({ errors }: StaffStepProps) {
  const { draft, setStaff } = useSetup()

  const branchOptions: ComboboxItem[] = draft.branches.map((b) => ({
    id: b.id,
    label: b.name || b.code || 'Unnamed branch',
    meta: b.code,
  }))

  const updateStaff = (id: string, patch: Partial<StaffDraft>) => {
    setStaff(draft.staff.map((s) => (s.id === id ? { ...s, ...patch } : s)))
  }

  const addStaff = () => setStaff([...draft.staff, createEmptyStaff()])

  const removeStaff = (id: string) => {
    setStaff(draft.staff.filter((s) => s.id !== id))
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start gap-4">
        <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-[var(--color-teal-50)] text-[var(--color-teal-700)]">
          <Users size={22} strokeWidth={1.5} aria-hidden />
        </div>
        <div>
          <h2 className="font-display text-h2 text-text-primary">Staff</h2>
          <p className="mt-1 max-w-lg text-body text-text-secondary">
            Create accounts for your team. Each person needs a role and at least one branch
            assignment.
          </p>
        </div>
      </div>

      {errors._form ? (
        <p className="text-body-sm text-status-danger-fg" role="alert">
          {errors._form}
        </p>
      ) : null}

      <EntityList
        items={draft.staff}
        onAdd={addStaff}
        onRemove={removeStaff}
        addLabel="Add another staff member"
        getItemLabel={(item) => item.name || 'New staff member'}
        renderItem={(member, index) => {
          const prefix = `staff-${index}`
          const selectedBranches = branchOptions.filter((b) => member.branchIds.includes(b.id))

          return (
            <div className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <FormField
                  id={`${member.id}-name`}
                  label="Full name"
                  required
                  error={errors[`${prefix}-name`]}
                >
                  <TextInput
                    id={`${member.id}-name`}
                    value={member.name}
                    onChange={(e) => updateStaff(member.id, { name: e.target.value })}
                    placeholder="e.g. Dr. Sara Hassan"
                    invalid={!!errors[`${prefix}-name`]}
                  />
                </FormField>

                <FormField
                  id={`${member.id}-mobile`}
                  label="Mobile"
                  required
                  error={errors[`${prefix}-mobile`]}
                >
                  <PhoneInput
                    id={`${member.id}-mobile`}
                    value={member.mobile}
                    onValueChange={(mobile) => updateStaff(member.id, { mobile })}
                    invalid={!!errors[`${prefix}-mobile`]}
                  />
                </FormField>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <FormField
                  id={`${member.id}-username`}
                  label="Username"
                  required
                  error={errors[`${prefix}-username`]}
                >
                  <TextInput
                    id={`${member.id}-username`}
                    value={member.username}
                    onChange={(e) => updateStaff(member.id, { username: e.target.value })}
                    placeholder="e.g. sara.hassan"
                    invalid={!!errors[`${prefix}-username`]}
                  />
                </FormField>

                <FormField
                  id={`${member.id}-password`}
                  label="Password"
                  required
                  error={errors[`${prefix}-password`]}
                >
                  <PasswordInput
                    id={`${member.id}-password`}
                    value={member.password}
                    onChange={(e) => updateStaff(member.id, { password: e.target.value })}
                    invalid={!!errors[`${prefix}-password`]}
                  />
                </FormField>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <FormField
                  id={`${member.id}-role`}
                  label="Role"
                  required
                  error={errors[`${prefix}-role`]}
                >
                  <Select
                    id={`${member.id}-role`}
                    value={member.role}
                    onValueChange={(role) => updateStaff(member.id, { role })}
                    options={[...STAFF_ROLE_OPTIONS]}
                    invalid={!!errors[`${prefix}-role`]}
                  />
                </FormField>

                <FormField
                  id={`${member.id}-branches`}
                  label="Branches assigned"
                  required
                  error={errors[`${prefix}-branches`]}
                >
                  <MultiSelect
                    id={`${member.id}-branches`}
                    value={selectedBranches}
                    onValueChange={(items) =>
                      updateStaff(member.id, { branchIds: items.map((i) => i.id) })
                    }
                    options={branchOptions}
                    placeholder="Select branches"
                    invalid={!!errors[`${prefix}-branches`]}
                    disabled={branchOptions.length === 0}
                  />
                </FormField>
              </div>
            </div>
          )
        }}
      />
    </div>
  )
}
