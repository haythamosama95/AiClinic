import { LayoutGrid, List } from 'lucide-react'
import { useMemo, useState } from 'react'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { Card } from '@/components/card/Card'
import type { CatalogService } from '@/data/services'
import { searchServices } from '@/data/services'
import { AddServiceDialog } from './AddServiceDialog'
import { ServiceSelectionGridView } from './ServiceSelectionGridView'
import { ServiceSelectionListView } from './ServiceSelectionListView'
import {
  ServiceSelectionEmpty,
  ServiceSelectionFooter,
  ServiceSelectionHeader,
  ServiceSelectionSidebar,
} from './serviceSelectionShared'
import type { SelectedServiceLine } from './types'
import { createLineFromService } from './types'

export type ServiceSelectionView = 'grid' | 'list'

export type ServiceSelectionStepProps = {
  catalog: CatalogService[]
  selectedLines: SelectedServiceLine[]
  onCatalogChange: (catalog: CatalogService[]) => void
  onLinesChange: (lines: SelectedServiceLine[]) => void
  onContinue: () => void
  onBack: () => void
}

export function ServiceSelectionStep({
  catalog,
  selectedLines,
  onCatalogChange,
  onLinesChange,
  onContinue,
  onBack,
}: ServiceSelectionStepProps) {
  const [query, setQuery] = useState('')
  const [addDialogOpen, setAddDialogOpen] = useState(false)
  const [view, setView] = useState<ServiceSelectionView>('grid')

  const filtered = useMemo(() => searchServices(query, catalog), [query, catalog])
  const selectedIds = useMemo(
    () => new Set(selectedLines.map((line) => line.serviceId)),
    [selectedLines],
  )

  const subtotal = selectedLines.reduce((sum, line) => sum + line.unitPrice * line.quantity, 0)

  const toggleService = (service: CatalogService, checked: boolean) => {
    if (checked) {
      onLinesChange([...selectedLines, createLineFromService(service)])
    } else {
      onLinesChange(selectedLines.filter((line) => line.serviceId !== service.id))
    }
  }

  const updateQuantity = (serviceId: string, quantity: number) => {
    onLinesChange(
      selectedLines.map((line) =>
        line.serviceId === serviceId ? { ...line, quantity: Math.max(1, quantity) } : line,
      ),
    )
  }

  const handleAddToCatalog = (service: CatalogService) => {
    onCatalogChange([...catalog, service])
    onLinesChange([...selectedLines, createLineFromService(service)])
  }

  const viewToggle = (
    <SegmentedControl
      aria-label="Catalog layout"
      size="sm"
      value={view}
      onChange={setView}
      options={[
        { value: 'grid', label: <LayoutGrid size={15} aria-hidden /> },
        { value: 'list', label: <List size={15} aria-hidden /> },
      ]}
    />
  )

  return (
    <>
      <div className="grid gap-6 lg:grid-cols-[1fr_18rem]">
        <Card variant="raised" padding="sm" className="overflow-hidden rounded-2xl p-0">
          <ServiceSelectionHeader
            searchQuery={query}
            onSearchChange={setQuery}
            viewToggle={viewToggle}
            onAddToCatalog={() => setAddDialogOpen(true)}
          />

          <div className={view === 'grid' ? undefined : 'max-h-[min(52vh,28rem)] overflow-y-auto'}>
            {filtered.length === 0 ? (
              <ServiceSelectionEmpty onAddToCatalog={() => setAddDialogOpen(true)} />
            ) : view === 'grid' ? (
              <ServiceSelectionGridView
                services={filtered}
                selectedIds={selectedIds}
                selectedLines={selectedLines}
                onToggle={toggleService}
                onQuantityChange={updateQuantity}
              />
            ) : (
              <ServiceSelectionListView
                services={filtered}
                selectedIds={selectedIds}
                selectedLines={selectedLines}
                onToggle={toggleService}
                onQuantityChange={updateQuantity}
              />
            )}
          </div>
        </Card>

        <ServiceSelectionSidebar selectedLines={selectedLines} subtotal={subtotal} />
      </div>

      <ServiceSelectionFooter
        onBack={onBack}
        onContinue={onContinue}
        canContinue={selectedLines.length > 0}
      />

      <AddServiceDialog
        open={addDialogOpen}
        onOpenChange={setAddDialogOpen}
        onAdd={handleAddToCatalog}
      />
    </>
  )
}
