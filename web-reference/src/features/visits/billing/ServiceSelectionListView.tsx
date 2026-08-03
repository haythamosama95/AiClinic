import { Checkbox } from '@/components/ui/checkbox/Checkbox'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { NumberInput } from '@/components/ui/number-input/NumberInput'
import type { CatalogService } from '@/data/services'
import { cn } from '@/lib/cn'
import type { SelectedServiceLine } from './types'

export type ServiceSelectionListViewProps = {
  services: CatalogService[]
  selectedIds: Set<string>
  selectedLines: SelectedServiceLine[]
  onToggle: (service: CatalogService, checked: boolean) => void
  onQuantityChange: (serviceId: string, quantity: number) => void
}

export function ServiceSelectionListView({
  services,
  selectedIds,
  selectedLines,
  onToggle,
  onQuantityChange,
}: ServiceSelectionListViewProps) {
  return (
    <ul className="divide-y divide-border-subtle">
      {services.map((service) => {
        const isSelected = selectedIds.has(service.id)
        const line = selectedLines.find((l) => l.serviceId === service.id)

        return (
          <li
            key={service.id}
            className={cn(
              'flex items-center gap-3 px-5 py-3.5 transition-colors sm:px-6',
              isSelected && 'bg-surface-selected/60',
            )}
          >
            <Checkbox
              id={`svc-list-${service.id}`}
              checked={isSelected}
              onCheckedChange={(checked) => onToggle(service, checked === true)}
              aria-label={`Select ${service.name}`}
            />

            <label htmlFor={`svc-list-${service.id}`} className="min-w-0 flex-1 cursor-pointer">
              <span className="text-body-strong text-text-primary">{service.name}</span>
              <span className="mt-0.5 block text-caption text-text-secondary">
                <MoneyDisplay amount={service.price} />
              </span>
            </label>

            {isSelected && line ? (
              <div className="w-20 shrink-0">
                <NumberInput
                  size="sm"
                  min={1}
                  max={99}
                  value={line.quantity}
                  onValueChange={(qty) => onQuantityChange(service.id, qty ?? 1)}
                  aria-label={`Quantity for ${service.name}`}
                />
              </div>
            ) : null}
          </li>
        )
      })}
    </ul>
  )
}
