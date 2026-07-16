import { AnimatePresence } from 'motion/react'
import { Pill, Plus } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'
import { TREATMENT_MEDICATION_OPTIONS } from '../mock-data'
import type { TreatmentPlanEntry } from '../types'
import { TreatmentPlanEntryCard } from './TreatmentPlanEntryCard'
import { TreatmentPlanFormDialog } from './TreatmentPlanFormDialog'

export type TreatmentPlanEditorProps = {
  entries: TreatmentPlanEntry[]
  onChange: (entries: TreatmentPlanEntry[]) => void
  className?: string
}

export function TreatmentPlanEditor({ entries, onChange, className }: TreatmentPlanEditorProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const editingEntry = editingId ? entries.find((e) => e.id === editingId) ?? null : null

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

  const addEntry = (entry: Omit<TreatmentPlanEntry, 'id'>) => {
    onChange([...entries, { id: crypto.randomUUID(), ...entry }])
  }

  const updateEntry = (id: string, patch: Omit<TreatmentPlanEntry, 'id'>) => {
    onChange(entries.map((e) => (e.id === id ? { ...e, ...patch } : e)))
  }

  const handleSubmit = (entry: Omit<TreatmentPlanEntry, 'id'>) => {
    if (editingId) {
      updateEntry(editingId, entry)
    } else {
      addEntry(entry)
    }
  }

  const removeEntry = (id: string) => {
    onChange(entries.filter((e) => e.id !== id))
  }

  return (
    <>
      <div
        className={cn(
          'rounded-xl border border-border-subtle bg-surface-default p-4',
          className,
        )}
      >
        <div className="mb-4">
          <h3 className="text-body-strong text-text-primary">Prescriptions</h3>
          <p className="mt-0.5 text-body-sm text-text-secondary">
            {entries.length > 0
              ? `${entries.length} prescription${entries.length === 1 ? '' : 's'} added`
              : 'Add medications with dosage, frequency, and duration.'}
          </p>
        </div>

        {entries.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border-default bg-surface-muted/50 px-4 py-8 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-full bg-surface-raised text-text-tertiary">
              <Pill size={18} strokeWidth={1.75} />
            </div>
            <p className="text-body-sm text-text-secondary">No prescriptions added yet.</p>
            <Button
              variant="secondary"
              size="sm"
              className="mt-4"
              leadingIcon={<Plus size={14} />}
              onClick={openAddDialog}
            >
              Add prescription
            </Button>
          </div>
        ) : (
          <div className="space-y-3">
            <AnimatePresence mode="popLayout">
              {entries.map((entry) => {
                const medication = TREATMENT_MEDICATION_OPTIONS.find(
                  (item) => item.id === entry.medicationId,
                )

                return (
                  <TreatmentPlanEntryCard
                    key={entry.id}
                    medicationLabel={medication?.label ?? 'Unspecified medication'}
                    medicationMeta={medication?.meta}
                    dosage={entry.dosage}
                    frequency={entry.frequency}
                    duration={entry.duration}
                    onEdit={() => openEditDialog(entry.id)}
                    onRemove={() => removeEntry(entry.id)}
                  />
                )
              })}
            </AnimatePresence>
          </div>
        )}

        {entries.length > 0 ? (
          <Button
            variant="secondary"
            size="sm"
            className="mt-4 w-full sm:w-auto"
            leadingIcon={<Plus size={14} />}
            onClick={openAddDialog}
          >
            Add another prescription
          </Button>
        ) : null}
      </div>

      <TreatmentPlanFormDialog
        open={dialogOpen}
        onOpenChange={handleDialogOpenChange}
        editingEntry={editingEntry}
        onSubmit={handleSubmit}
      />
    </>
  )
}
