import { useMemo } from 'react'
import { FormField } from '@/components/ui/form-field/FormField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { Combobox, type ComboboxItem } from '@/components/ui/combobox/Combobox'
import { CURRENCY_CODES, TIMEZONES } from '../constants'
import type { OrganizationFormValues } from '../types'

export type OrganizationFormFieldsProps = {
  values: OrganizationFormValues
  onChange: (patch: Partial<OrganizationFormValues>) => void
  disabled?: boolean
  errors?: Partial<Record<keyof OrganizationFormValues, string>>
}

function toItems(options: readonly string[]): ComboboxItem[] {
  return options.map((code) => ({ id: code, label: code }))
}

export function OrganizationFormFields({
  values,
  onChange,
  disabled,
  errors = {},
}: OrganizationFormFieldsProps) {
  const currencyItems = useMemo(() => toItems(CURRENCY_CODES), [])
  const timezoneItems = useMemo(() => toItems(TIMEZONES), [])

  const currencyValue = values.currencyCode
    ? { id: values.currencyCode, label: values.currencyCode }
    : null

  const timezoneValue = values.timezone
    ? { id: values.timezone, label: values.timezone }
    : null

  return (
    <div className="grid gap-5 sm:grid-cols-2">
      <FormField
        id="org-name"
        label="Organization name"
        required
        error={errors.name}
      >
        <TextInput
          id="org-name"
          value={values.name}
          onChange={(e) => onChange({ name: e.target.value })}
          placeholder="Enter your clinic name"
          disabled={disabled}
          invalid={Boolean(errors.name)}
        />
      </FormField>

      <FormField id="org-logo" label="Logo URL" error={errors.logoUrl}>
        <TextInput
          id="org-logo"
          type="url"
          value={values.logoUrl ?? ''}
          onChange={(e) => onChange({ logoUrl: e.target.value || null })}
          placeholder="https://example.com/logo.png"
          disabled={disabled}
          invalid={Boolean(errors.logoUrl)}
        />
      </FormField>

      <FormField
        id="org-currency"
        label="Currency code"
        required
        error={errors.currencyCode}
      >
        <Combobox
          id="org-currency"
          items={currencyItems}
          value={currencyValue}
          onValueChange={(item) => onChange({ currencyCode: item?.id ?? '' })}
          placeholder="Type to search (e.g. EGP)"
          disabled={disabled}
          invalid={Boolean(errors.currencyCode)}
        />
      </FormField>

      <FormField id="org-timezone" label="Timezone" required error={errors.timezone}>
        <Combobox
          id="org-timezone"
          items={timezoneItems}
          value={timezoneValue}
          onValueChange={(item) => onChange({ timezone: item?.id ?? '' })}
          placeholder="Type to search (e.g. Africa/Cairo)"
          disabled={disabled}
          invalid={Boolean(errors.timezone)}
        />
      </FormField>
    </div>
  )
}

export function validateOrganization(values: OrganizationFormValues) {
  const errors: Partial<Record<keyof OrganizationFormValues, string>> = {}
  if (!values.name.trim()) errors.name = 'Organization name is required'
  if (!values.currencyCode.trim()) errors.currencyCode = 'Select a currency code from the list'
  else if (!CURRENCY_CODES.includes(values.currencyCode as (typeof CURRENCY_CODES)[number])) {
    errors.currencyCode = 'Select a currency code from the list'
  }
  if (!values.timezone.trim()) errors.timezone = 'Select a timezone from the list'
  else if (!TIMEZONES.includes(values.timezone as (typeof TIMEZONES)[number])) {
    errors.timezone = 'Select a timezone from the list'
  }
  return errors
}
