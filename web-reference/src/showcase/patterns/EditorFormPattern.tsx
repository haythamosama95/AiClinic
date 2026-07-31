import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Alert } from '@/components/alert/Alert'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { Switch } from '@/components/ui/switch/Switch'
import { FormField } from '@/components/ui/form-field/FormField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { MoneyField } from '@/components/ui/money-field/MoneyField'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { MOCK_BRANCHES } from './mock-data'
import { PatternFrame } from './PatternFrame'

export function EditorFormPattern() {
  const [name, setName] = useState('General consultation')
  const [defaultPrice, setDefaultPrice] = useState(350)
  const [promoPrice, setPromoPrice] = useState<number | null>(400)
  const [branches, setBranches] = useState(MOCK_BRANCHES)
  const [submitted, setSubmitted] = useState(false)

  const promoError =
    submitted && promoPrice !== null && promoPrice > defaultPrice
      ? 'The promotion must be less than or equal to the effective price.'
      : undefined

  const toggleBranch = (id: string) => {
    setBranches((prev) =>
      prev.map((b) => (b.id === id ? { ...b, active: !b.active } : b)),
    )
  }

  return (
    <ShowcaseSection
      id="pattern-editor-form"
      title="Editor / Form"
      componentName="05 §2 Editor / Form"
      description="Service editor with branch-config matrix, promotion editor, and validation."
    >
      <PatternFrame>
        <div className="space-y-8 p-4 sm:p-6">
          <SectionHeader
            title="Service details"
            description="Organization-wide defaults. Branch overrides apply per location."
          />

          <div className="grid max-w-xl gap-4">
            <FormField id="svc-name" label="Service name" required>
              <TextInput id="svc-name" value={name} onChange={(e) => setName(e.target.value)} />
            </FormField>
            <FormField
              id="svc-price"
              label="Default price"
              required
              helperText="Used when a branch has no price override."
            >
              <MoneyField
                id="svc-price"
                value={defaultPrice}
                onValueChange={(v) => setDefaultPrice(v ?? 0)}
              />
            </FormField>
            <FormField id="svc-desc" label="Description">
              <Textarea id="svc-desc" rows={2} defaultValue="Standard outpatient consultation." />
            </FormField>
          </div>

          <SectionHeader title="Branch configuration" description="Per-branch activation and price overrides." />

          <div className="overflow-x-auto rounded-lg border border-border-default">
            <table className="w-full text-body-sm" aria-label="Branch configuration">
              <thead>
                <tr className="border-b border-border-subtle bg-surface-sunken text-start">
                  <th className="px-4 py-2 font-medium text-text-secondary">Branch</th>
                  <th className="px-4 py-2 font-medium text-text-secondary">Active</th>
                  <th className="px-4 py-2 font-medium text-text-secondary text-end">Override price</th>
                </tr>
              </thead>
              <tbody>
                {branches.map((branch) => (
                  <tr key={branch.id} className="border-b border-border-subtle last:border-0">
                    <td className="px-4 py-3 text-text-primary">{branch.name}</td>
                    <td className="px-4 py-3">
                      <Switch
                        checked={branch.active}
                        onCheckedChange={() => toggleBranch(branch.id)}
                        aria-label={`${branch.name} active`}
                      />
                    </td>
                    <td className="px-4 py-3 text-end">
                      {branch.override !== null ? (
                        <MoneyDisplay amount={branch.override} />
                      ) : (
                        <span className="text-text-tertiary">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <SectionHeader title="Promotion" description="One time-boxed promotion per branch." />

          <div className="grid max-w-sm gap-4">
            <FormField
              id="promo-price"
              label="Promotion price"
              error={promoError}
              helperText="Must be ≤ effective branch price."
            >
              <MoneyField
                id="promo-price"
                value={promoPrice ?? undefined}
                invalid={!!promoError}
                onValueChange={setPromoPrice}
              />
            </FormField>
          </div>

          {promoError ? (
            <Alert variant="danger" title="Fix validation errors before saving">
              Review the promotion price and branch overrides.
            </Alert>
          ) : null}

          <div className="sticky bottom-0 -mx-4 flex justify-end gap-2 border-t border-border-subtle bg-surface-default px-4 py-4 sm:-mx-6 sm:px-6">
            <Button variant="ghost">Cancel</Button>
            <Button variant="primary" onClick={() => setSubmitted(true)}>
              Save changes
            </Button>
          </div>
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
