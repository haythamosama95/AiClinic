import { Check, Minus, Plus } from 'lucide-react'
import { motion } from 'motion/react'
import { IconButton } from '@/components/actions/IconButton'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import type { CatalogService } from '@/data/services'
import { cn } from '@/lib/cn'
import { motionPresets, resolveTransition } from '@/lib/motion'
import type { SelectedServiceLine } from './types'

export type ServiceSelectionGridViewProps = {
  services: CatalogService[]
  selectedIds: Set<string>
  selectedLines: SelectedServiceLine[]
  onToggle: (service: CatalogService, checked: boolean) => void
  onQuantityChange: (serviceId: string, quantity: number) => void
}

export function ServiceSelectionGridView({
  services,
  selectedIds,
  selectedLines,
  onToggle,
  onQuantityChange,
}: ServiceSelectionGridViewProps) {
  const transition = resolveTransition(motionPresets['fade-scale'])

  return (
    <ul className="grid grid-cols-2 gap-2 p-4 sm:grid-cols-3 sm:gap-3 sm:p-5 lg:grid-cols-4">
      {services.map((service, index) => {
        const isSelected = selectedIds.has(service.id)
        const line = selectedLines.find((l) => l.serviceId === service.id)
        const quantity = line?.quantity ?? 1

        return (
          <motion.li
            key={service.id}
            initial={{ opacity: 0, scale: 0.97 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ ...transition, delay: Math.min(index * 0.02, 0.2) }}
          >
            <div
              className={cn(
                'group relative flex h-full min-h-[7.5rem] flex-col rounded-xl border transition-colors duration-[var(--duration-fast)]',
                isSelected
                  ? 'border-action-primary bg-surface-selected shadow-[inset_0_2px_0_0_var(--action-primary)]'
                  : 'border-border-default bg-surface-default hover:border-border-strong hover:bg-surface-hover',
              )}
            >
              <button
                type="button"
                onClick={() => onToggle(service, !isSelected)}
                className="focus-ring flex flex-1 flex-col rounded-xl p-3.5 text-start sm:p-4"
                aria-pressed={isSelected}
                aria-label={
                  isSelected ? `Remove ${service.name} from visit` : `Add ${service.name} to visit`
                }
              >
                <span className="flex items-start justify-between gap-2">
                  <span
                    className={cn(
                      'line-clamp-2 text-body-strong leading-snug',
                      isSelected ? 'text-text-primary' : 'text-text-primary',
                    )}
                  >
                    {service.name}
                  </span>
                  <span
                    className={cn(
                      'flex size-5 shrink-0 items-center justify-center rounded-full border transition-colors',
                      isSelected
                        ? 'border-action-primary bg-action-primary text-action-primary-fg'
                        : 'border-border-default bg-surface-default text-transparent group-hover:border-border-strong',
                    )}
                    aria-hidden
                  >
                    <Check size={12} strokeWidth={2.5} />
                  </span>
                </span>

                <span className="mt-auto pt-3 font-mono text-body-sm tabular-nums text-text-primary">
                  <MoneyDisplay amount={service.price} />
                </span>
              </button>

              {isSelected && line ? (
                <div
                  className="flex items-center justify-between gap-2 border-t border-border-subtle px-3 py-2 sm:px-3.5"
                  onClick={(e) => e.stopPropagation()}
                  onKeyDown={(e) => e.stopPropagation()}
                >
                  <span className="text-caption text-text-tertiary">Qty</span>
                  <div className="flex items-center gap-1">
                    <IconButton
                      icon={<Minus size={14} />}
                      label={`Decrease quantity for ${service.name}`}
                      size="sm"
                      variant="ghost"
                      disabled={quantity <= 1}
                      onClick={() => onQuantityChange(service.id, quantity - 1)}
                    />
                    <span
                      className="min-w-[1.75rem] text-center font-mono text-body-sm tabular-nums text-text-primary"
                      aria-live="polite"
                    >
                      {quantity}
                    </span>
                    <IconButton
                      icon={<Plus size={14} />}
                      label={`Increase quantity for ${service.name}`}
                      size="sm"
                      variant="ghost"
                      disabled={quantity >= 99}
                      onClick={() => onQuantityChange(service.id, quantity + 1)}
                    />
                  </div>
                </div>
              ) : null}
            </div>
          </motion.li>
        )
      })}
    </ul>
  )
}
