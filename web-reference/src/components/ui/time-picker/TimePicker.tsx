import { Clock } from 'lucide-react'
import { useId, useState } from 'react'
import { cn } from '@/lib/cn'
import { useDirection } from '@/providers/DirectionProvider'
import { inputFieldClasses, type InputSize } from '../input-base/input-styles'
import { Popover } from '../popover/Popover'

export type TimePickerProps = {
  id?: string
  size?: InputSize
  invalid?: boolean
  disabled?: boolean
  readOnly?: boolean
  value?: string
  defaultValue?: string
  onValueChange?: (time: string) => void
  stepMinutes?: number
  use24Hour?: boolean
  placeholder?: string
  className?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
}

function pad(n: number) {
  return String(n).padStart(2, '0')
}

function generateSlots(stepMinutes: number, use24Hour: boolean): string[] {
  const slots: string[] = []
  for (let h = 0; h < 24; h++) {
    for (let m = 0; m < 60; m += stepMinutes) {
      const time24 = `${pad(h)}:${pad(m)}`
      if (use24Hour) {
        slots.push(time24)
      } else {
        const period = h >= 12 ? 'PM' : 'AM'
        const h12 = h % 12 || 12
        slots.push(`${h12}:${pad(m)} ${period}`)
      }
    }
  }
  return slots
}

export function TimePicker({
  id: idProp,
  size = 'md',
  invalid,
  disabled,
  readOnly,
  value: controlled,
  defaultValue,
  onValueChange,
  stepMinutes = 15,
  use24Hour,
  placeholder = 'Select time',
  className,
  ...aria
}: TimePickerProps) {
  const autoId = useId()
  const id = idProp ?? autoId
  const { locale } = useDirection()
  const is24 = use24Hour ?? locale !== 'ar'
  const [open, setOpen] = useState(false)
  const [internal, setInternal] = useState(defaultValue ?? '')
  const slots = generateSlots(stepMinutes, is24)
  const value = controlled ?? internal

  const select = (time: string) => {
    if (controlled === undefined) setInternal(time)
    onValueChange?.(time)
    setOpen(false)
  }

  return (
    <Popover
      open={open && !disabled && !readOnly}
      onOpenChange={setOpen}
      contentClassName="w-48 max-h-60 overflow-auto p-1"
      trigger={
        <div className={cn('relative', className)}>
          <input
            id={id}
            type="text"
            readOnly
            disabled={disabled}
            placeholder={placeholder}
            value={value}
            onClick={() => !disabled && !readOnly && setOpen(true)}
            className={cn(inputFieldClasses({ size, invalid, disabled, readOnly }), 'cursor-pointer pe-10')}
            {...aria}
          />
          <Clock
            className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-icon-muted"
            aria-hidden
          />
        </div>
      }
    >
      <ul role="listbox" aria-label="Time options">
        {slots.map((slot) => (
          <li key={slot} role="presentation">
            <button
              type="button"
              role="option"
              aria-selected={slot === value}
              onClick={() => select(slot)}
              className={cn(
                'focus-ring w-full rounded-md px-3 py-2 text-start text-body tabular-nums hover:bg-surface-hover',
                slot === value && 'bg-surface-selected',
              )}
            >
              {slot}
            </button>
          </li>
        ))}
      </ul>
    </Popover>
  )
}
