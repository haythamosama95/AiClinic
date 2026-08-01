import { useMemo, useState } from 'react'
import { motion } from 'motion/react'
import { Pencil, Plus, SearchX, Stethoscope, Trash2 } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { ConfirmationDialog, Dialog } from '@/components/dialog/Dialog'
import type { ComboboxItem } from '@/components/ui/combobox/Combobox'
import {
  emptyServiceFormValues,
  ServiceFormFields,
  serviceToFormValues,
  type ServiceFormValues,
} from '../forms/ServiceFormFields'
import type { BranchRecord, OrganizationProfile, ServiceRecord } from '../types'

export type ServicesTabProps = {
  services: ServiceRecord[]
  branches: BranchRecord[]
  organization: OrganizationProfile
  onAdd: (values: ServiceFormValues) => void
  onUpdate: (id: string, values: ServiceFormValues) => void
  onRemove: (id: string) => void
}

export function ServicesTab({
  services,
  branches,
  organization,
  onAdd,
  onUpdate,
  onRemove,
}: ServicesTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingService, setEditingService] = useState<ServiceRecord | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<ServiceRecord | null>(null)
  const [formValues, setFormValues] = useState<ServiceFormValues>(emptyServiceFormValues())
  const [search, setSearch] = useState('')

  const branchOptions: ComboboxItem[] = useMemo(
    () =>
      branches
        .filter((b) => b.name.trim())
        .map((b) => ({ id: b.id, label: b.name, meta: b.code })),
    [branches],
  )

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return services
    return services.filter((s) => s.name.toLowerCase().includes(q))
  }, [services, search])

  const formatPrice = (price: number | null) =>
    price !== null
      ? new Intl.NumberFormat('en', {
          style: 'currency',
          currency: organization.currencyCode,
        }).format(price)
      : '—'

  const openCreate = () => {
    setEditingService(null)
    setFormValues(emptyServiceFormValues())
    setDialogOpen(true)
  }

  const openEdit = (service: ServiceRecord) => {
    setEditingService(service)
    setFormValues(serviceToFormValues(service))
    setDialogOpen(true)
  }

  const handleSubmit = () => {
    if (editingService) {
      onUpdate(editingService.id, formValues)
    } else {
      onAdd(formValues)
    }
    setDialogOpen(false)
    setEditingService(null)
  }

  const hasServices = services.length > 0
  const hasResults = filtered.length > 0

  return (
    <>
      <motion.div
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.22 }}
        className="space-y-6"
      >
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-xl space-y-1">
            <h3 className="font-[family-name:var(--font-display)] text-h3 text-text-primary">
              Services
            </h3>
            <p className="text-body-sm text-text-secondary">
              Billable procedures and default pricing. Services can be offered at all branches or
              assigned to specific locations.
            </p>
          </div>
          <Button leadingIcon={<Plus size={16} />} onClick={openCreate}>
            Add service
          </Button>
        </div>

        {hasServices ? (
          <div className="flex flex-wrap items-center gap-3">
            <input
              type="search"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search services…"
              aria-label="Search services"
              className="focus-ring h-10 min-w-[12rem] flex-1 rounded-lg border border-border-default bg-surface-default px-3 text-body-sm text-text-primary placeholder:text-text-tertiary sm:max-w-xs"
            />
          </div>
        ) : null}

        {!hasServices ? (
          <div className="rounded-2xl border border-dashed border-border-default bg-surface-sunken/50 px-6 py-16 text-center">
            <Stethoscope size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
            <p className="mt-4 text-body-strong text-text-primary">No services yet</p>
            <p className="mt-1 text-body-sm text-text-secondary">
              Add billable procedures to use when creating invoices.
            </p>
            <Button className="mt-6" leadingIcon={<Plus size={16} />} onClick={openCreate}>
              Add service
            </Button>
          </div>
        ) : !hasResults ? (
          <div className="rounded-2xl border border-border-subtle bg-surface-default px-6 py-14 text-center shadow-elevation-1">
            <SearchX size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
            <p className="mt-4 text-body-strong text-text-primary">No services match</p>
            <p className="mt-1 text-body-sm text-text-secondary">Try a different search term.</p>
            <Button className="mt-6" variant="secondary" onClick={() => setSearch('')}>
              Clear search
            </Button>
          </div>
        ) : (
          <div className="overflow-hidden rounded-2xl border border-border-subtle bg-surface-default shadow-elevation-1">
            <table className="w-full text-left text-body-sm">
              <thead>
                <tr className="border-b border-border-subtle bg-surface-sunken/50">
                  <th className="px-4 py-3 font-medium text-text-secondary">Service</th>
                  <th className="px-4 py-3 font-medium text-text-secondary">Price</th>
                  <th className="px-4 py-3 font-medium text-text-secondary">Branches</th>
                  <th className="w-24 px-4 py-3 font-medium text-text-secondary">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((service) => (
                  <tr
                    key={service.id}
                    className="border-b border-border-subtle last:border-b-0 hover:bg-surface-sunken/30"
                  >
                    <td className="px-4 py-3 font-medium text-text-primary">
                      {service.name || '—'}
                    </td>
                    <td className="px-4 py-3 font-mono text-caption text-text-secondary">
                      {formatPrice(service.price)}
                    </td>
                    <td className="px-4 py-3 text-text-secondary">
                      {service.allBranches
                        ? 'All branches'
                        : `${service.branchIds.length} selected`}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex gap-1">
                        <IconButton
                          icon={<Pencil size={15} />}
                          label="Edit service"
                          variant="ghost"
                          size="sm"
                          onClick={() => openEdit(service)}
                        />
                        {services.length > 1 ? (
                          <IconButton
                            icon={<Trash2 size={15} />}
                            label="Remove service"
                            variant="ghost"
                            size="sm"
                            onClick={() => setDeleteTarget(service)}
                          />
                        ) : null}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </motion.div>

      <Dialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open)
          if (!open) setEditingService(null)
        }}
        title={editingService ? 'Edit service' : 'Add service'}
        size="md"
        footer={
          <Button variant="primary" onClick={handleSubmit}>
            {editingService ? 'Save changes' : 'Add service'}
          </Button>
        }
      >
        <ServiceFormFields
          idPrefix={editingService?.id ?? 'new-service'}
          values={formValues}
          onChange={(patch) => setFormValues((prev) => ({ ...prev, ...patch }))}
          branchOptions={branchOptions}
          currency={organization.currencyCode}
        />
      </Dialog>

      <ConfirmationDialog
        open={Boolean(deleteTarget)}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="Delete service?"
        description={
          deleteTarget
            ? `${deleteTarget.name} will be removed from your service catalog. This cannot be undone.`
            : ''
        }
        confirmLabel="Delete service"
        onConfirm={() => {
          if (deleteTarget) onRemove(deleteTarget.id)
          setDeleteTarget(null)
        }}
      />
    </>
  )
}
