import { AnimatePresence } from 'motion/react'
import { FlaskConical, Plus } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'
import { getInvestigationById, INVESTIGATION_OPTIONS } from '../mock-data'
import type { InvestigationEntry } from '../types'
import { InvestigationEntryCard } from './InvestigationEntryCard'
import { InvestigationFormDialog } from './InvestigationFormDialog'

export type InvestigationsEditorProps = {
  entries: InvestigationEntry[]
  onChange: (entries: InvestigationEntry[]) => void
  className?: string
}

export function InvestigationsEditor({ entries, onChange, className }: InvestigationsEditorProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const usedIds = new Set(entries.map((e) => e.investigationId))
  const canAddMore = usedIds.size < INVESTIGATION_OPTIONS.length
  const editingEntry = editingId ? entries.find((e) => e.id === editingId) ?? null : null
  const usedIdsForDialog = new Set(
    entries.filter((e) => e.id !== editingId).map((e) => e.investigationId),
  )

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

  const addEntry = (entry: Omit<InvestigationEntry, 'id'>) => {
    onChange([...entries, { id: crypto.randomUUID(), ...entry }])
  }

  const updateEntry = (id: string, patch: Omit<InvestigationEntry, 'id'>) => {
    onChange(entries.map((e) => (e.id === id ? { ...e, ...patch } : e)))
  }

  const handleSubmit = (entry: Omit<InvestigationEntry, 'id'>) => {
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
          <h3 className="text-body-strong text-text-primary">Ordered investigations</h3>
          <p className="mt-0.5 text-body-sm text-text-secondary">
            {entries.length > 0
              ? `${entries.length} investigation${entries.length === 1 ? '' : 's'} to order`
              : 'Add labs, imaging, or other diagnostic tests.'}
          </p>
        </div>

        {entries.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border-default bg-surface-muted/50 px-4 py-8 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-full bg-surface-raised text-text-tertiary">
              <FlaskConical size={18} strokeWidth={1.75} />
            </div>
            <p className="text-body-sm text-text-secondary">No investigations added yet.</p>
            <Button
              variant="secondary"
              size="sm"
              className="mt-4"
              leadingIcon={<Plus size={14} />}
              onClick={openAddDialog}
              disabled={!canAddMore}
            >
              Add investigation
            </Button>
          </div>
        ) : (
          <div className="space-y-3">
            <AnimatePresence mode="popLayout">
              {entries.map((entry) => {
                const investigation = getInvestigationById(entry.investigationId)
                if (!investigation) return null
                return (
                  <InvestigationEntryCard
                    key={entry.id}
                    investigation={investigation}
                    note={entry.note}
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
            Add another investigation
          </Button>
        ) : null}
      </div>

      <InvestigationFormDialog
        open={dialogOpen}
        onOpenChange={handleDialogOpenChange}
        usedInvestigationIds={usedIdsForDialog}
        editingEntry={editingEntry}
        onSubmit={handleSubmit}
      />
    </>
  )
}
