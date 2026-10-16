import { ChevronRight, MapPin, MapPinned, Plus, Trash2 } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import { useCallback, useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { Card } from '@/components/card/Card'
import { FormField } from '@/components/ui/form-field/FormField'
import { PhoneInput } from '@/components/ui/phone-input/PhoneInput'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { createEmptyBranch, type BranchDraft } from '@/data/settings'
import { cn } from '@/lib/cn'
import { resolveTransition } from '@/lib/motion'
import { MapsLocationInput, WorkingHoursEditor } from '../../components/WorkingHoursEditor'
import { useSetup } from '../../SetupContext'
import { SETUP_FIELD_HINTS } from '../setupFieldHints'
import { hasErrors, validateSingleBranch, type StepErrors } from '../validation'

export type BranchStepProps = {
  errors: StepErrors
}

function branchDayErrors(errors: StepErrors, prefix: string): Record<string, string> {
  const dayErrors: Record<string, string> = {}
  Object.entries(errors).forEach(([key, value]) => {
    if (key.startsWith(`${prefix}-`) && key.endsWith('-time')) {
      dayErrors[key.slice(prefix.length + 1)] = value
    }
  })
  return dayErrors
}

function CollapsedBranchCard({
  branch,
  index,
  onExpand,
  onRemove,
  canRemove,
}: {
  branch: BranchDraft
  index: number
  onExpand: () => void
  onRemove: () => void
  canRemove: boolean
}) {
  const openDays = branch.workingDays.filter((d) => d.enabled).length

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -8 }}
      transition={resolveTransition({ duration: 'quick', ease: 'out' })}
    >
      <div className="flex items-stretch gap-2">
        <button
          type="button"
          onClick={onExpand}
          className={cn(
            'focus-ring flex min-w-0 flex-1 items-center gap-3 rounded-lg border border-border-default',
            'bg-surface-muted/50 px-4 py-3 text-start transition-colors hover:bg-surface-hover',
          )}
        >
          <div className="flex size-9 shrink-0 items-center justify-center rounded-md bg-surface-default text-[var(--color-violet-600)]">
            <MapPin size={16} strokeWidth={1.5} aria-hidden />
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-body-strong text-text-primary">
              {branch.name || `Branch ${index + 1}`}
            </p>
            <p className="truncate text-caption text-text-tertiary">
              {[branch.code, branch.mobile, `${openDays} open days`].filter(Boolean).join(' · ')}
            </p>
          </div>
          <ChevronRight
            size={16}
            className="shrink-0 text-icon-muted"
            aria-hidden
          />
        </button>
        {canRemove ? (
          <IconButton
            icon={<Trash2 size={16} />}
            label="Remove branch"
            variant="ghost"
            size="md"
            onClick={onRemove}
            className="shrink-0 self-center"
          />
        ) : null}
      </div>
    </motion.div>
  )
}

function BranchForm({
  branch,
  index,
  errors,
  onUpdate,
  onRemove,
  canRemove,
}: {
  branch: BranchDraft
  index: number
  errors: StepErrors
  onUpdate: (patch: Partial<BranchDraft>) => void
  onRemove: () => void
  canRemove: boolean
}) {
  const prefix = `branch-${index}`

  return (
    <Card variant="flat" padding="lg" className="relative overflow-hidden">
      <div className="mb-4 flex items-center justify-between gap-3">
        <p className="text-body-strong text-text-primary">Branch {index + 1}</p>
        {canRemove ? (
          <IconButton
            icon={<Trash2 size={16} />}
            label="Remove branch"
            variant="ghost"
            size="sm"
            onClick={onRemove}
          />
        ) : null}
      </div>

      <div className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            id={`${branch.id}-name`}
            label="Branch name"
            required
            hint={SETUP_FIELD_HINTS.branchName}
            error={errors[`${prefix}-name`]}
          >
            <TextInput
              id={`${branch.id}-name`}
              value={branch.name}
              onChange={(e) => onUpdate({ name: e.target.value })}
              placeholder="e.g. Zamalek"
              invalid={!!errors[`${prefix}-name`]}
            />
          </FormField>

          <FormField
            id={`${branch.id}-code`}
            label="Branch code"
            required
            hint={SETUP_FIELD_HINTS.branchCode}
            error={errors[`${prefix}-code`]}
          >
            <TextInput
              id={`${branch.id}-code`}
              value={branch.code}
              onChange={(e) => onUpdate({ code: e.target.value.toUpperCase() })}
              placeholder="e.g. ZML"
              invalid={!!errors[`${prefix}-code`]}
              className="uppercase"
            />
          </FormField>
        </div>

        <FormField
          id={`${branch.id}-mobile`}
          label="Mobile"
          required
          hint={SETUP_FIELD_HINTS.branchMobile}
          error={errors[`${prefix}-mobile`]}
        >
          <PhoneInput
            id={`${branch.id}-mobile`}
            value={branch.mobile}
            onValueChange={(mobile) => onUpdate({ mobile })}
            invalid={!!errors[`${prefix}-mobile`]}
          />
        </FormField>

        <MapsLocationInput
          id={`${branch.id}-map`}
          value={branch.mapLocation}
          onChange={(mapLocation) => onUpdate({ mapLocation })}
          invalid={!!errors[`${prefix}-map`]}
        />

        {errors[`${prefix}-hours`] ? (
          <p className="text-caption text-status-danger-fg" role="alert">
            {errors[`${prefix}-hours`]}
          </p>
        ) : null}

        <WorkingHoursEditor
          value={branch.workingDays}
          onChange={(workingDays) => onUpdate({ workingDays })}
          errors={branchDayErrors(errors, prefix)}
        />
      </div>
    </Card>
  )
}

export function BranchStep({ errors: parentErrors }: BranchStepProps) {
  const { draft, setBranches } = useSetup()
  const [activeBranchId, setActiveBranchId] = useState(() => draft.branches[0]?.id ?? '')
  const [confirmedIds, setConfirmedIds] = useState<Set<string>>(() => new Set())
  const [localErrors, setLocalErrors] = useState<StepErrors>({})

  const mergedErrors = useMemo(
    () => ({ ...parentErrors, ...localErrors }),
    [parentErrors, localErrors],
  )

  const activeIndex = draft.branches.findIndex((b) => b.id === activeBranchId)
  const activeBranch = activeIndex >= 0 ? draft.branches[activeIndex] : draft.branches[0]

  const updateBranch = (id: string, patch: Partial<BranchDraft>) => {
    setBranches(draft.branches.map((b) => (b.id === id ? { ...b, ...patch } : b)))
  }

  const validateAndConfirm = useCallback(
    (branchId: string): boolean => {
      const index = draft.branches.findIndex((b) => b.id === branchId)
      if (index < 0) return true

      const branchErrors = validateSingleBranch(draft.branches[index], index, draft.branches)
      if (hasErrors(branchErrors)) {
        setLocalErrors(branchErrors)
        return false
      }

      setLocalErrors({})
      setConfirmedIds((prev) => new Set(prev).add(branchId))
      return true
    },
    [draft.branches],
  )

  const addBranch = () => {
    if (!activeBranch) return
    if (!validateAndConfirm(activeBranch.id)) return

    const newBranch = createEmptyBranch()
    setBranches([...draft.branches, newBranch])
    setActiveBranchId(newBranch.id)
  }

  const expandBranch = (branchId: string) => {
    if (branchId === activeBranchId) return

    if (activeBranch && !confirmedIds.has(activeBranch.id)) {
      if (!validateAndConfirm(activeBranch.id)) return
    }

    setLocalErrors({})
    setActiveBranchId(branchId)
  }

  const removeBranch = (id: string) => {
    const next = draft.branches.filter((b) => b.id !== id)
    setBranches(next)
    setConfirmedIds((prev) => {
      const updated = new Set(prev)
      updated.delete(id)
      return updated
    })

    if (id === activeBranchId) {
      const fallback = next[next.length - 1]
      setActiveBranchId(fallback?.id ?? '')
    }
    setLocalErrors({})
  }

  const collapsedBranches = draft.branches.filter(
    (b) => b.id !== activeBranchId && confirmedIds.has(b.id),
  )

  return (
    <div className="space-y-6">
      <div className="flex items-start gap-4">
        <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-[var(--color-violet-50)] text-[var(--color-violet-600)]">
          <MapPinned size={22} strokeWidth={1.5} aria-hidden />
        </div>
        <div>
          <h2 className="font-display text-h2 text-text-primary">Branches</h2>
          <p className="mt-1 max-w-lg text-body text-text-secondary">
            Add every location where patients are seen. Each branch needs a unique code for
            scheduling and billing.
          </p>
        </div>
      </div>

      {mergedErrors._form ? (
        <p className="text-body-sm text-status-danger-fg" role="alert">
          {mergedErrors._form}
        </p>
      ) : null}

      <div className="space-y-3">
        <AnimatePresence initial={false}>
          {collapsedBranches.map((branch) => {
            const index = draft.branches.findIndex((b) => b.id === branch.id)
            return (
              <CollapsedBranchCard
                key={branch.id}
                branch={branch}
                index={index}
                onExpand={() => expandBranch(branch.id)}
                onRemove={() => removeBranch(branch.id)}
                canRemove={draft.branches.length > 1}
              />
            )
          })}
        </AnimatePresence>

        {activeBranch ? (
          <motion.div
            key={activeBranch.id}
            layout
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={resolveTransition({ duration: 'base', ease: 'out' })}
          >
            <BranchForm
              branch={activeBranch}
              index={activeIndex}
              errors={mergedErrors}
              onUpdate={(patch) => updateBranch(activeBranch.id, patch)}
              onRemove={() => removeBranch(activeBranch.id)}
              canRemove={draft.branches.length > 1}
            />
          </motion.div>
        ) : null}
      </div>

      <Button variant="secondary" leadingIcon={<Plus size={16} />} onClick={addBranch}>
        Add another branch
      </Button>
    </div>
  )
}
