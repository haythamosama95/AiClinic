import { ChevronLeft, ChevronRight, Lock } from 'lucide-react'
import { useMemo } from 'react'
import { IconButton } from '@/components/actions/IconButton'
import { cn } from '@/lib/cn'
import { getDoctorById } from './mock-data'
import { formatDayChip, formatFullDate } from './slot-availability'
import type { TimeSlot } from './types'

export type BookAppointmentStep2Props = {
  branchName: string
  patientName: string
  preferredDoctorName: string | null
  hasPreferredDoctor: boolean
  dayOptions: string[]
  selectedDate: string | null
  selectedTime: string | null
  slots: TimeSlot[]
  errors: Partial<Record<'date' | 'time', string>>
  onDateChange: (date: string) => void
  onTimeChange: (time: string) => void
}

export function BookAppointmentStep2({
  branchName,
  patientName,
  preferredDoctorName,
  hasPreferredDoctor,
  dayOptions,
  selectedDate,
  selectedTime,
  slots,
  errors,
  onDateChange,
  onTimeChange,
}: BookAppointmentStep2Props) {
  const selectedIndex = selectedDate ? dayOptions.indexOf(selectedDate) : 0

  const scrollDays = (delta: number) => {
    const next = Math.min(Math.max(0, selectedIndex + delta), dayOptions.length - 1)
    onDateChange(dayOptions[next])
  }

  const openCount = useMemo(
    () => slots.filter((s) => s.status !== 'locked').length,
    [slots],
  )

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3 rounded-xl border border-border-subtle bg-gradient-to-br from-[var(--color-teal-50)]/40 to-surface-default px-4 py-3">
        <div>
          <p className="text-overline text-text-tertiary">Booking for</p>
          <p className="text-body-strong text-text-primary">{patientName}</p>
          <p className="text-caption text-text-secondary">
            {branchName}
            {preferredDoctorName ? ` · Prefers ${preferredDoctorName}` : ' · Any doctor'}
          </p>
        </div>
        {selectedDate ? (
          <p className="text-end text-caption tabular-nums text-text-secondary">
            {openCount} open slot{openCount !== 1 ? 's' : ''}
          </p>
        ) : null}
      </div>

      <div>
        <div className="mb-2 flex items-center justify-between gap-2">
          <p className="text-body-strong text-text-primary">Day</p>
          <div className="flex items-center gap-1">
            <IconButton
              icon={<ChevronLeft size={16} />}
              label="Previous days"
              size="sm"
              onClick={() => scrollDays(-3)}
              disabled={selectedIndex <= 0}
            />
            <IconButton
              icon={<ChevronRight size={16} />}
              label="Next days"
              size="sm"
              onClick={() => scrollDays(3)}
              disabled={selectedIndex >= dayOptions.length - 1}
            />
          </div>
        </div>

        <div
          className="flex gap-2 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          role="listbox"
          aria-label="Select appointment day"
        >
          {dayOptions.map((iso) => {
            const chip = formatDayChip(iso)
            const selected = iso === selectedDate
            const isSunday = new Date(`${iso}T12:00:00`).getDay() === 0

            return (
              <button
                key={iso}
                type="button"
                role="option"
                aria-selected={selected}
                disabled={isSunday}
                onClick={() => onDateChange(iso)}
                className={cn(
                  'flex min-w-[4.25rem] shrink-0 flex-col items-center rounded-xl border px-3 py-2.5 transition-all',
                  'focus-ring',
                  selected
                    ? 'border-action-primary bg-action-primary text-action-primary-fg shadow-sm'
                    : isSunday
                      ? 'cursor-not-allowed border-border-subtle bg-surface-muted text-text-tertiary opacity-60'
                      : 'border-border-default bg-surface-default text-text-primary hover:border-border-strong hover:bg-surface-hover',
                )}
              >
                <span className="text-overline opacity-80">{chip.weekday}</span>
                <span className="text-h3 tabular-nums leading-none">{chip.day}</span>
                <span className="text-caption opacity-80">{chip.month}</span>
              </button>
            )
          })}
        </div>
        {errors.date ? (
          <p className="mt-1.5 text-caption text-status-danger-fg" role="alert">
            {errors.date}
          </p>
        ) : null}
      </div>

      {selectedDate ? (
        <div>
          <p className="mb-3 text-body-sm text-text-secondary">
            {formatFullDate(selectedDate)} · 30-minute slots
          </p>

          <div
            className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4"
            role="listbox"
            aria-label="Available time slots"
          >
            {slots.map((slot) => (
              <SlotButton
                key={slot.time}
                slot={slot}
                selected={slot.time === selectedTime}
                hasPreferredDoctor={hasPreferredDoctor}
                onSelect={() => onTimeChange(slot.time)}
              />
            ))}
          </div>

          {errors.time ? (
            <p className="mt-2 text-caption text-status-danger-fg" role="alert">
              {errors.time}
            </p>
          ) : null}

          <SlotLegend hasPreferredDoctor={hasPreferredDoctor} />
        </div>
      ) : null}
    </div>
  )
}

function SlotButton({
  slot,
  selected,
  hasPreferredDoctor,
  onSelect,
}: {
  slot: TimeSlot
  selected: boolean
  hasPreferredDoctor: boolean
  onSelect: () => void
}) {
  const locked = slot.status === 'locked'
  const doctors = slot.availableDoctorIds
    .map((id) => getDoctorById(id)?.fullName)
    .filter(Boolean)
    .join(', ')

  const statusLabel =
    slot.status === 'locked'
      ? 'Unavailable — all doctors booked'
      : slot.status === 'preferred'
        ? `Available with preferred doctor`
        : slot.status === 'alternate'
          ? `Available with other doctor${slot.availableDoctorIds.length > 1 ? 's' : ''}`
          : 'Available'

  return (
    <button
      type="button"
      role="option"
      aria-selected={selected}
      aria-disabled={locked}
      disabled={locked}
      title={locked ? statusLabel : `${statusLabel}${doctors ? `: ${doctors}` : ''}`}
      onClick={onSelect}
      className={cn(
        'group relative flex min-h-[3.25rem] flex-col items-center justify-center rounded-xl border px-2 py-2.5 text-center transition-all',
        'focus-ring',
        locked && 'cursor-not-allowed border-border-subtle bg-surface-muted text-text-tertiary',
        !locked && slot.status === 'available' &&
        'border-[var(--color-teal-200)] bg-[var(--color-teal-50)] text-[var(--color-teal-800)] hover:border-[var(--color-teal-300)] hover:bg-[var(--color-teal-100)]',
        !locked && slot.status === 'preferred' &&
        'border-[var(--color-teal-400)] bg-[var(--color-teal-100)] text-[var(--color-teal-900)] hover:border-[var(--color-teal-500)]',
        !locked && slot.status === 'alternate' &&
        'border-[var(--color-violet-200)] bg-[var(--color-violet-50)] text-[var(--color-violet-800)] hover:border-[var(--color-violet-300)] hover:bg-[var(--color-violet-100)]',
        selected &&
        !locked &&
        'ring-2 ring-border-focus ring-offset-2 ring-offset-surface-raised shadow-sm',
      )}
    >
      {locked && hasPreferredDoctor ? (
        <Lock size={14} className="mb-0.5 opacity-50" aria-hidden />
      ) : null}
      {locked && !hasPreferredDoctor ? (
        <span className="inline-flex items-center gap-1">
          <Lock size={12} className="opacity-50" aria-hidden />
          <span className="text-body-sm font-semibold tabular-nums">{slot.label}</span>
        </span>
      ) : (
        <span className="text-body-sm font-semibold tabular-nums">{slot.label}</span>
      )}
      {!locked && hasPreferredDoctor && slot.status === 'alternate' ? (
        <span className="mt-0.5 text-[0.65rem] leading-tight opacity-75">Other doctor</span>
      ) : null}
      {!locked && hasPreferredDoctor && slot.status === 'preferred' ? (
        <span className="mt-0.5 text-[0.65rem] leading-tight opacity-75">Preferred</span>
      ) : null}
    </button>
  )
}

function SlotLegend({ hasPreferredDoctor }: { hasPreferredDoctor: boolean }) {
  return (
    <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-lg border border-border-subtle bg-surface-sunken px-3 py-2.5">
      <span className="text-overline text-text-tertiary">Legend</span>
      {hasPreferredDoctor ? (
        <>
          <LegendSwatch
            className="border-[var(--color-teal-400)] bg-[var(--color-teal-100)]"
            label="Preferred doctor free"
          />
          <LegendSwatch
            className="border-[var(--color-violet-200)] bg-[var(--color-violet-50)]"
            label="Other doctors free"
          />
        </>
      ) : (
        <LegendSwatch
          className="border-[var(--color-teal-200)] bg-[var(--color-teal-50)]"
          label="Open slot"
        />
      )}
      <LegendSwatch
        className="border-border-subtle bg-surface-muted"
        label="Fully booked"
        muted
      />
    </div>
  )
}

function LegendSwatch({
  className,
  label,
  muted,
}: {
  className: string
  label: string
  muted?: boolean
}) {
  return (
    <span className="inline-flex items-center gap-1.5 text-caption text-text-secondary">
      <span
        className={cn('size-3 rounded-sm border', className, muted && 'opacity-70')}
        aria-hidden
      />
      {label}
    </span>
  )
}
