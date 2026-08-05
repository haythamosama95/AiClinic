import { Copy, Trash2 } from 'lucide-react'
import type { ReactNode } from 'react'
import { ContextMenu, type MenuEntry } from '@/components/navigation/Menu'
import { cn } from '@/lib/cn'
import type { ShiftInstance } from '../types'

type ShiftCalendarMenuProps = {
  shift: ShiftInstance
  className?: string
  style?: React.CSSProperties
  onDuplicate: (shiftId: string) => void
  onDelete: (shiftId: string) => void
  children: ReactNode
}

export function ShiftCalendarMenu({
  shift,
  className,
  style,
  onDuplicate,
  onDelete,
  children,
}: ShiftCalendarMenuProps) {
  const entries: MenuEntry[] = [
    {
      id: 'duplicate',
      label: 'Duplicate',
      icon: <Copy size={16} strokeWidth={1.5} />,
      onSelect: () => onDuplicate(shift.id),
    },
    {
      id: 'delete',
      label: 'Delete',
      icon: <Trash2 size={16} strokeWidth={1.5} />,
      destructive: true,
      onSelect: () => onDelete(shift.id),
    },
  ]

  return (
    <ContextMenu entries={entries}>
      <div className={cn(className)} style={style}>
        {children}
      </div>
    </ContextMenu>
  )
}
