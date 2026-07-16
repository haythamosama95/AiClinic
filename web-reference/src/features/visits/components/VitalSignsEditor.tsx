import { AnimatePresence } from 'motion/react'
import { Activity, Plus } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'
import { getVitalSignById, VITAL_SIGN_CATALOG } from '../mock-data'
import type { VitalSignEntry } from '../types'
import { VitalSignEntryCard } from './VitalSignEntryCard'
import { VitalSignFormDialog } from './VitalSignFormDialog'

export type VitalSignsEditorProps = {
  entries: VitalSignEntry[]
  onChange: (entries: VitalSignEntry[]) => void
  className?: string
}

export function VitalSignsEditor({ entries, onChange, className }: VitalSignsEditorProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const usedIds = new Set(entries.map((e) => e.vitalSignId))
  const canAddMore = usedIds.size < VITAL_SIGN_CATALOG.length
  const editingEntry = editingId ? entries.find((e) => e.id === editingId) ?? null : null
  const usedIdsForDialog = new Set(
    entries.filter((e) => e.id !== editingId).map((e) => e.vitalSignId),
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

  const addEntry = (entry: Omit<VitalSignEntry, 'id'>) => {
    onChange([...entries, { id: crypto.randomUUID(), ...entry }])
  }

  const updateEntry = (id: string, patch: Omit<VitalSignEntry, 'id'>) => {
    onChange(entries.map((e) => (e.id === id ? { ...e, ...patch } : e)))
  }

  const handleSubmit = (entry: Omit<VitalSignEntry, 'id'>) => {
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
          <h3 className="text-body-strong text-text-primary">Recorded measurements</h3>
          <p className="mt-0.5 text-body-sm text-text-secondary">
            {entries.length > 0
              ? `${entries.length} vital sign${entries.length === 1 ? '' : 's'} documented`
              : 'Add each measurement as it is taken.'}
          </p>
        </div>

        {entries.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border-default bg-surface-muted/50 px-4 py-8 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-full bg-surface-raised text-text-tertiary">
              <Activity size={18} strokeWidth={1.75} />
            </div>
            <p className="text-body-sm text-text-secondary">No vital signs recorded yet.</p>
            <Button
              variant="secondary"
              size="sm"
              className="mt-4"
              leadingIcon={<Plus size={14} />}
              onClick={openAddDialog}
              disabled={!canAddMore}
            >
              Add vital sign
            </Button>
          </div>
        ) : (
          <div className="flex flex-wrap gap-3">
            <AnimatePresence mode="popLayout">
              {entries.map((entry) => {
                const def = getVitalSignById(entry.vitalSignId)
                if (!def) return null
                return (
                  <VitalSignEntryCard
                    key={entry.id}
                    definition={def}
                    value={entry.value}
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
            Add another vital sign
          </Button>
        ) : null}
      </div>

      <VitalSignFormDialog
        open={dialogOpen}
        onOpenChange={handleDialogOpenChange}
        usedVitalSignIds={usedIdsForDialog}
        editingEntry={editingEntry}
        onSubmit={handleSubmit}
      />
    </>
  )
}
