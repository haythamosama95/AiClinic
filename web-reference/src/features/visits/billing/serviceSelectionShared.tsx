import { Plus, Receipt, Search } from 'lucide-react'
import type { ReactNode } from 'react'
import { motion } from 'motion/react'
import { Button } from '@/components/actions/Button'
import { Card } from '@/components/card/Card'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import { motionPresets, resolveTransition } from '@/lib/motion'
import type { SelectedServiceLine } from './types'

export function ServiceSelectionHeader({
  searchQuery,
  onSearchChange,
  viewToggle,
  onAddToCatalog,
}: {
  searchQuery: string
  onSearchChange: (value: string) => void
  viewToggle: ReactNode
  onAddToCatalog: () => void
}) {
  return (
    <div className="border-b border-border-subtle bg-surface-sunken/50 px-5 py-4 sm:px-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-overline text-text-tertiary">Step 1 of 2</p>
          <h2 className="mt-0.5 font-display text-h2 text-text-primary">Services performed</h2>
          <p className="mt-1 text-body-sm text-text-secondary">
            Select every procedure delivered during this visit.
          </p>
        </div>
        <Button
          variant="secondary"
          size="sm"
          leadingIcon={<Plus size={14} />}
          onClick={onAddToCatalog}
          className="shrink-0"
        >
          Add to catalog
        </Button>
      </div>

      <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="min-w-0 flex-1">
          <SearchInput
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search services…"
            showShortcutHint={false}
            aria-label="Search services"
          />
        </div>
        {viewToggle}
      </div>
    </div>
  )
}

export function ServiceSelectionEmpty({
  onAddToCatalog,
}: {
  onAddToCatalog: () => void
}) {
  return (
    <div className="flex flex-col items-center gap-3 px-6 py-16 text-center">
      <span className="flex size-12 items-center justify-center rounded-full bg-surface-sunken text-icon-muted">
        <Search size={20} aria-hidden />
      </span>
      <p className="text-body-sm text-text-secondary">No services match your search.</p>
      <Button variant="ghost" size="sm" leadingIcon={<Plus size={14} />} onClick={onAddToCatalog}>
        Add a new service
      </Button>
    </div>
  )
}

export function ServiceSelectionSidebar({
  selectedLines,
  subtotal,
}: {
  selectedLines: SelectedServiceLine[]
  subtotal: number
}) {
  const transition = resolveTransition(motionPresets['slide-up'])

  return (
    <motion.aside
      initial={{ opacity: 0, x: 12 }}
      animate={{ opacity: 1, x: 0 }}
      transition={transition}
      className="lg:sticky lg:top-6 lg:self-start"
    >
      <Card variant="raised" padding="lg" className="rounded-2xl">
        <div className="flex items-center gap-3">
          <span className="flex size-10 items-center justify-center rounded-xl bg-[var(--color-violet-50)] text-[var(--color-violet-600)]">
            <Receipt size={18} strokeWidth={1.75} aria-hidden />
          </span>
          <div>
            <p className="text-overline text-text-tertiary">Selected</p>
            <p className="font-display text-h3 text-text-primary tabular-nums">
              {selectedLines.length}{' '}
              <span className="text-body font-normal text-text-secondary">
                {selectedLines.length === 1 ? 'service' : 'services'}
              </span>
            </p>
          </div>
        </div>

        {selectedLines.length > 0 ? (
          <ul className="mt-5 space-y-2.5 border-t border-border-subtle pt-5">
            {selectedLines.map((line) => (
              <li key={line.id} className="flex items-start justify-between gap-2 text-body-sm">
                <span className="min-w-0 text-text-primary">
                  {line.name}
                  {line.quantity > 1 ? (
                    <span className="text-text-tertiary"> × {line.quantity}</span>
                  ) : null}
                </span>
                <MoneyDisplay
                  amount={line.unitPrice * line.quantity}
                  className="shrink-0 text-body-sm"
                />
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-5 border-t border-border-subtle pt-5 text-body-sm text-text-tertiary">
            No services selected yet. Pick from the catalog or add a new one.
          </p>
        )}

        <div className="mt-5 flex items-baseline justify-between border-t border-border-subtle pt-4">
          <span className="text-body-sm text-text-secondary">Subtotal</span>
          <MoneyDisplay amount={subtotal} emphasis />
        </div>
      </Card>
    </motion.aside>
  )
}

export function ServiceSelectionFooter({
  onBack,
  onContinue,
  canContinue,
}: {
  onBack: () => void
  onContinue: () => void
  canContinue: boolean
}) {
  return (
    <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
      <Button variant="secondary" onClick={onBack}>
        Back to review
      </Button>
      <Button
        variant="primary"
        trailingIcon={<Receipt size={16} />}
        onClick={onContinue}
        disabled={!canContinue}
      >
        Review invoice
      </Button>
    </div>
  )
}
