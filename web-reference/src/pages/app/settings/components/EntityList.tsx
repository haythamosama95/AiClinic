import { Plus, Trash2 } from 'lucide-react'
import type { ReactNode } from 'react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { Card } from '@/components/card/Card'
import { cn } from '@/lib/cn'

export type EntityListProps<T extends { id: string }> = {
  items: T[]
  onAdd: () => void
  onRemove: (id: string) => void
  addLabel: string
  minItems?: number
  renderItem: (item: T, index: number) => ReactNode
  getItemLabel?: (item: T, index: number) => string
  className?: string
}

export function EntityList<T extends { id: string }>({
  items,
  onAdd,
  onRemove,
  addLabel,
  minItems = 1,
  renderItem,
  getItemLabel,
  className,
}: EntityListProps<T>) {
  return (
    <div className={cn('space-y-4', className)}>
      {items.map((item, index) => (
        <Card
          key={item.id}
          variant="flat"
          padding="lg"
          className="relative overflow-hidden"
        >
          <div className="mb-4 flex items-center justify-between gap-3">
            <p className="text-body-strong text-text-primary">
              {getItemLabel?.(item, index) ?? `Item ${index + 1}`}
            </p>
            {items.length > minItems ? (
              <IconButton
                icon={<Trash2 size={16} />}
                label="Remove"
                variant="ghost"
                size="sm"
                onClick={() => onRemove(item.id)}
              />
            ) : null}
          </div>
          {renderItem(item, index)}
        </Card>
      ))}

      <Button variant="secondary" leadingIcon={<Plus size={16} />} onClick={onAdd}>
        {addLabel}
      </Button>
    </div>
  )
}
