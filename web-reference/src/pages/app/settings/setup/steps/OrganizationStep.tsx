import { Building2 } from 'lucide-react'
import { FormField } from '@/components/ui/form-field/FormField'
import { Select } from '@/components/ui/select/Select'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { CURRENCY_OPTIONS, TIMEZONE_OPTIONS } from '@/data/settings'
import { useSetup } from '../../SetupContext'
import type { StepErrors } from '../validation'

export type OrganizationStepProps = {
  errors: StepErrors
}

export function OrganizationStep({ errors }: OrganizationStepProps) {
  const { draft, updateOrganization } = useSetup()
  const { organization } = draft

  return (
    <div className="space-y-6">
      <div className="flex items-start gap-4">
        <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-[var(--color-teal-50)] text-[var(--color-teal-600)]">
          <Building2 size={22} strokeWidth={1.5} aria-hidden />
        </div>
        <div>
          <h2 className="font-display text-h2 text-text-primary">Your organization</h2>
          <p className="mt-1 max-w-lg text-body text-text-secondary">
            Set the legal name and regional defaults for your clinic. These apply across every
            branch.
          </p>
        </div>
      </div>

      <div className="max-w-lg space-y-4">
        <FormField id="org-name" label="Organization name" required error={errors.name}>
          <TextInput
            id="org-name"
            value={organization.name}
            onChange={(e) => updateOrganization({ name: e.target.value })}
            placeholder="e.g. Nile Dental Group"
            invalid={!!errors.name}
          />
        </FormField>

        <FormField id="org-timezone" label="Timezone" required error={errors.timezone}>
          <Select
            id="org-timezone"
            value={organization.timezone}
            onValueChange={(timezone) => updateOrganization({ timezone })}
            options={[...TIMEZONE_OPTIONS]}
            invalid={!!errors.timezone}
          />
        </FormField>

        <FormField
          id="org-currency"
          label="Currency"
          required
          error={errors.currency}
          helperText="Used for invoices, services, and financial reports."
        >
          <Select
            id="org-currency"
            value={organization.currency}
            onValueChange={(currency) => updateOrganization({ currency })}
            options={[...CURRENCY_OPTIONS]}
            invalid={!!errors.currency}
          />
        </FormField>
      </div>
    </div>
  )
}
