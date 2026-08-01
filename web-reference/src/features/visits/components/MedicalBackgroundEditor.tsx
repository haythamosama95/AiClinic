<<<<<<< HEAD
import { FormField } from '@/components/ui/form-field/FormField'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { MultiSelect } from '@/components/ui/multi-select/MultiSelect'
import { cn } from '@/lib/cn'

export type MedicalBackgroundEditorProps = {
  chronicConditions: ComboboxItem[]
  allergies: ComboboxItem[]
  currentMedications: ComboboxItem[]
  chronicConditionOptions: ComboboxItem[]
  allergyOptions: ComboboxItem[]
  medicationOptions: ComboboxItem[]
  onChronicConditionsChange: (items: ComboboxItem[]) => void
  onAllergiesChange: (items: ComboboxItem[]) => void
  onCurrentMedicationsChange: (items: ComboboxItem[]) => void
  className?: string
}

=======
import { AnimatePresence, motion } from 'motion/react'
import { AlertTriangle, HeartPulse, Pill, Plus } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Tabs } from '@/components/navigation/Tabs'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import {
  getAllergyById,
  getChronicConditionById,
  getCurrentMedicationById,
} from '../mock-data'
import type { MedicalBackgroundEntry } from '../types'
import {
  MedicalBackgroundEntryCard,
  type MedicalBackgroundAccent,
} from './MedicalBackgroundEntryCard'
import { MedicalBackgroundFormDialog } from './MedicalBackgroundFormDialog'

type BackgroundCategoryId = 'conditions' | 'allergies' | 'medications'

type BackgroundCategory = {
  id: BackgroundCategoryId
  label: string
  shortLabel: string
  description: string
  emptyTitle: string
  emptyHint: string
  itemLabel: string
  noteLabel: string
  noteHint: string
  notePlaceholder: string
  searchPlaceholder: string
  dialogTitle: string
  dialogDescription: string
  accent: MedicalBackgroundAccent
  icon: typeof HeartPulse
  options: ComboboxItem[]
  resolveItem: (id: string) => ComboboxItem | undefined
}

const CATEGORIES: BackgroundCategory[] = [
  {
    id: 'conditions',
    label: 'Chronic conditions',
    shortLabel: 'Conditions',
    description: 'Active diagnoses and long-term conditions.',
    emptyTitle: 'No conditions on record for this visit',
    emptyHint: 'Add each diagnosis with onset, control, or treatment context.',
    itemLabel: 'Condition',
    noteLabel: 'Clinical note',
    noteHint: 'Onset, severity, control status, or recent changes.',
    notePlaceholder: 'e.g. Diagnosed 2019 · well controlled on metformin…',
    searchPlaceholder: 'Search diagnoses and ICD codes…',
    dialogTitle: 'Add chronic condition',
    dialogDescription: 'Select a condition and note how it relates to this visit.',
    accent: 'warning',
    icon: HeartPulse,
    options: [],
    resolveItem: getChronicConditionById,
  },
  {
    id: 'allergies',
    label: 'Allergies',
    shortLabel: 'Allergies',
    description: 'Drug, food, and environmental sensitivities.',
    emptyTitle: 'No allergies documented',
    emptyHint: 'Record each allergy with reaction type and severity.',
    itemLabel: 'Allergy',
    noteLabel: 'Reaction note',
    noteHint: 'Reaction type, severity, and when it was last observed.',
    notePlaceholder: 'e.g. Anaphylaxis with penicillin · avoid all beta-lactams…',
    searchPlaceholder: 'Search drug, food, and environmental allergies…',
    dialogTitle: 'Add allergy',
    dialogDescription: 'Select an allergen and describe the reaction for this encounter.',
    accent: 'danger',
    icon: AlertTriangle,
    options: [],
    resolveItem: getAllergyById,
  },
  {
    id: 'medications',
    label: 'Current medications',
    shortLabel: 'Medications',
    description: 'Medications the patient is taking at the time of visit.',
    emptyTitle: 'No medications listed',
    emptyHint: 'Add each medication with dose, adherence, or recent changes.',
    itemLabel: 'Medication',
    noteLabel: 'Dosing note',
    noteHint: 'Dose, frequency, adherence, or recent changes.',
    notePlaceholder: 'e.g. 500 mg twice daily · patient reports good adherence…',
    searchPlaceholder: 'Search current medications…',
    dialogTitle: 'Add medication',
    dialogDescription: 'Select a medication and note how the patient is taking it.',
    accent: 'info',
    icon: Pill,
    options: [],
    resolveItem: getCurrentMedicationById,
  },
]

export type MedicalBackgroundEditorProps = {
  chronicConditions: MedicalBackgroundEntry[]
  allergies: MedicalBackgroundEntry[]
  currentMedications: MedicalBackgroundEntry[]
  chronicConditionOptions: ComboboxItem[]
  allergyOptions: ComboboxItem[]
  medicationOptions: ComboboxItem[]
  onChronicConditionsChange: (entries: MedicalBackgroundEntry[]) => void
  onAllergiesChange: (entries: MedicalBackgroundEntry[]) => void
  onCurrentMedicationsChange: (entries: MedicalBackgroundEntry[]) => void
  className?: string
}

function CategoryCount({ count, accent }: { count: number; accent: MedicalBackgroundAccent }) {
  const tone =
    accent === 'warning'
      ? 'bg-status-warning-surface text-status-warning-fg'
      : accent === 'danger'
        ? 'bg-status-danger-surface text-status-danger-fg'
        : 'bg-status-info-surface text-status-info-fg'

  return (
    <span
      className={cn(
        'ms-auto inline-flex min-w-[1.25rem] items-center justify-center rounded-full px-1.5 py-0.5 text-[11px] font-semibold tabular-nums',
        count > 0 ? tone : 'bg-surface-muted text-text-tertiary',
      )}
      aria-hidden
    >
      {count}
    </span>
  )
}

>>>>>>> master
export function MedicalBackgroundEditor({
  chronicConditions,
  allergies,
  currentMedications,
  chronicConditionOptions,
  allergyOptions,
  medicationOptions,
  onChronicConditionsChange,
  onAllergiesChange,
  onCurrentMedicationsChange,
  className,
}: MedicalBackgroundEditorProps) {
<<<<<<< HEAD
  return (
    <div className={cn('space-y-5 rounded-xl border border-border-subtle bg-surface-default p-4', className)}>
      <div>
        <h3 className="text-body-strong text-text-primary">Medical background</h3>
        <p className="mt-0.5 text-body-sm text-text-secondary">
          Chronic conditions, allergies, and current medications relevant to this visit.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <FormField
          id="chronic-conditions"
          label="Chronic conditions"
          helperText="Active diagnoses and long-term conditions."
        >
          <MultiSelect
            id="chronic-conditions"
            placeholder="Add chronic conditions…"
            options={chronicConditionOptions}
            value={chronicConditions}
            onValueChange={onChronicConditionsChange}
            allLabel="Select all conditions"
          />
        </FormField>

        <FormField
          id="allergies"
          label="Allergies"
          helperText="Drug, food, and environmental allergies."
        >
          <MultiSelect
            id="allergies"
            placeholder="Add allergies…"
            options={allergyOptions}
            value={allergies}
            onValueChange={onAllergiesChange}
            allLabel="Select all allergies"
          />
        </FormField>

        <FormField
          id="current-medications"
          label="Current medications"
          helperText="Medications the patient is taking at the time of visit."
        >
          <MultiSelect
            id="current-medications"
            placeholder="Add medications…"
            options={medicationOptions}
            value={currentMedications}
            onValueChange={onCurrentMedicationsChange}
            allLabel="Select all medications"
          />
        </FormField>
      </div>
    </div>
=======
  const categories = CATEGORIES.map((category) => {
    if (category.id === 'conditions') return { ...category, options: chronicConditionOptions }
    if (category.id === 'allergies') return { ...category, options: allergyOptions }
    return { ...category, options: medicationOptions }
  })

  const entriesByCategory: Record<BackgroundCategoryId, MedicalBackgroundEntry[]> = {
    conditions: chronicConditions,
    allergies,
    medications: currentMedications,
  }

  const onChangeByCategory: Record<
    BackgroundCategoryId,
    (entries: MedicalBackgroundEntry[]) => void
  > = {
    conditions: onChronicConditionsChange,
    allergies: onAllergiesChange,
    medications: onCurrentMedicationsChange,
  }

  const [activeCategory, setActiveCategory] = useState<BackgroundCategoryId>('conditions')
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)

  const category = categories.find((item) => item.id === activeCategory) ?? categories[0]
  const entries = entriesByCategory[category.id]
  const onChange = onChangeByCategory[category.id]
  const usedIds = new Set(entries.map((entry) => entry.itemId))
  const canAddMore = usedIds.size < category.options.length
  const editingEntry = editingId ? entries.find((entry) => entry.id === editingId) ?? null : null
  const usedIdsForDialog = new Set(
    entries.filter((entry) => entry.id !== editingId).map((entry) => entry.itemId),
  )
  const totalEntries =
    chronicConditions.length + allergies.length + currentMedications.length
  const preset = motionPresets['fade']
  const transition = resolveTransition(preset)

  const openAddDialog = () => {
    setEditingId(null)
    setDialogOpen(true)
  }

  const openEditDialog = (id: string) => {
    setEditingId(id)
    setDialogOpen(true)
  }

  const handleDialogOpenChange = (open: boolean) => {
    setDialogOpen(open)
    if (!open) setEditingId(null)
  }

  const addEntry = (entry: Omit<MedicalBackgroundEntry, 'id'>) => {
    onChange([...entries, { id: crypto.randomUUID(), ...entry }])
  }

  const updateEntry = (id: string, patch: Omit<MedicalBackgroundEntry, 'id'>) => {
    onChange(entries.map((entry) => (entry.id === id ? { ...entry, ...patch } : entry)))
  }

  const updateNote = (id: string, note: string) => {
    onChange(entries.map((entry) => (entry.id === id ? { ...entry, note } : entry)))
  }

  const removeEntry = (id: string) => {
    onChange(entries.filter((entry) => entry.id !== id))
  }

  const handleSubmit = (entry: Omit<MedicalBackgroundEntry, 'id'>) => {
    if (editingId) {
      updateEntry(editingId, entry)
    } else {
      addEntry(entry)
    }
  }

  const CategoryIcon = category.icon

  return (
    <>
      <div
        className={cn(
          'overflow-hidden rounded-xl border border-border-subtle bg-surface-default',
          className,
        )}
      >
        <div className="border-b border-border-subtle px-4 py-4 sm:px-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 className="font-display text-body-strong text-text-primary">Medical background</h3>
              <p className="mt-1 max-w-prose text-body-sm text-text-secondary">
                Each condition, allergy, and medication needs a note — control status, reaction
                details, or dosing context for this visit.
              </p>
            </div>
            {totalEntries > 0 ? (
              <p className="text-caption text-text-tertiary">
                {totalEntries} item{totalEntries === 1 ? '' : 's'} documented
              </p>
            ) : null}
          </div>
        </div>

        <div className="grid min-h-[18rem] lg:grid-cols-[minmax(11rem,13rem)_1fr]">
          <div
            className="border-b border-border-subtle bg-surface-muted/30 px-3 py-3 lg:border-b-0 lg:border-e"
            role="presentation"
          >
            <Tabs
              variant="vertical"
              aria-label="Medical background categories"
              value={activeCategory}
              onChange={(id) => setActiveCategory(id as BackgroundCategoryId)}
              items={categories.map((item) => {
                const Icon = item.icon
                const count = entriesByCategory[item.id].length
                return {
                  id: item.id,
                  label: (
                    <span className="flex w-full items-center gap-2">
                      <Icon size={15} strokeWidth={1.75} className="shrink-0 opacity-70" />
                      <span className="truncate">{item.shortLabel}</span>
                      <CategoryCount count={count} accent={item.accent} />
                    </span>
                  ),
                }
              })}
              className="w-full"
            />
          </div>

          <div className="flex min-w-0 flex-col">
            <div className="border-b border-border-subtle px-4 py-3 sm:px-5">
              <div className="flex items-start gap-3">
                <div
                  className={cn(
                    'mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg',
                    category.accent === 'warning' && 'bg-status-warning-surface text-status-warning-fg',
                    category.accent === 'danger' && 'bg-status-danger-surface text-status-danger-fg',
                    category.accent === 'info' && 'bg-status-info-surface text-status-info-fg',
                  )}
                >
                  <CategoryIcon size={16} strokeWidth={1.75} />
                </div>
                <div className="min-w-0">
                  <h4 className="text-body-strong text-text-primary">{category.label}</h4>
                  <p className="mt-0.5 text-body-sm text-text-secondary">{category.description}</p>
                </div>
              </div>
            </div>

            <div className="flex flex-1 flex-col px-4 py-4 sm:px-5">
              {entries.length === 0 ? (
                <div className="flex flex-1 flex-col items-center justify-center rounded-xl border border-dashed border-border-default bg-surface-muted/40 px-4 py-10 text-center">
                  <div
                    className={cn(
                      'mb-3 flex size-10 items-center justify-center rounded-full',
                      category.accent === 'warning' && 'bg-status-warning-surface text-status-warning-fg',
                      category.accent === 'danger' && 'bg-status-danger-surface text-status-danger-fg',
                      category.accent === 'info' && 'bg-status-info-surface text-status-info-fg',
                    )}
                  >
                    <CategoryIcon size={18} strokeWidth={1.75} />
                  </div>
                  <p className="text-body-sm font-medium text-text-primary">{category.emptyTitle}</p>
                  <p className="mt-1 max-w-sm text-body-sm text-text-secondary">{category.emptyHint}</p>
                  <Button
                    variant="secondary"
                    size="sm"
                    className="mt-5"
                    leadingIcon={<Plus size={14} />}
                    onClick={openAddDialog}
                    disabled={!canAddMore}
                  >
                    Add {category.id === 'conditions' ? 'condition' : category.id === 'allergies' ? 'allergy' : 'medication'}
                  </Button>
                </div>
              ) : (
                <div className="space-y-3">
                  <AnimatePresence mode="popLayout">
                    {entries.map((entry) => {
                      const item = category.resolveItem(entry.itemId)
                      if (!item) return null
                      return (
                        <MedicalBackgroundEntryCard
                          key={entry.id}
                          item={item}
                          note={entry.note}
                          accent={category.accent}
                          noteLabel={category.noteLabel}
                          notePlaceholder={category.notePlaceholder}
                          onNoteChange={(note) => updateNote(entry.id, note)}
                          onEdit={() => openEditDialog(entry.id)}
                          onRemove={() => removeEntry(entry.id)}
                        />
                      )
                    })}
                  </AnimatePresence>
                </div>
              )}

              {entries.length > 0 && canAddMore ? (
                <Button
                  variant="secondary"
                  size="sm"
                  className="mt-4 w-full sm:w-auto"
                  leadingIcon={<Plus size={14} />}
                  onClick={openAddDialog}
                >
                  Add another
                </Button>
              ) : null}
            </div>
          </div>
        </div>

        <motion.div
          layout={!getReducedMotion()}
          className="border-t border-border-subtle bg-surface-muted/20 px-4 py-2.5 sm:px-5"
          initial={false}
          animate={{ opacity: 1 }}
          transition={transition}
        >
          <p className="text-caption text-text-tertiary">
            Notes stay with each item in the visit summary — add context clinicians need at the
            point of care.
          </p>
        </motion.div>
      </div>

      <MedicalBackgroundFormDialog
        open={dialogOpen}
        onOpenChange={handleDialogOpenChange}
        title={editingEntry ? `Edit ${category.shortLabel.toLowerCase()}` : category.dialogTitle}
        description={category.dialogDescription}
        itemLabel={category.itemLabel}
        noteLabel={category.noteLabel}
        noteHint={category.noteHint}
        notePlaceholder={category.notePlaceholder}
        searchPlaceholder={category.searchPlaceholder}
        options={category.options}
        usedItemIds={usedIdsForDialog}
        editingEntry={editingEntry}
        onSubmit={handleSubmit}
      />
    </>
>>>>>>> master
  )
}
