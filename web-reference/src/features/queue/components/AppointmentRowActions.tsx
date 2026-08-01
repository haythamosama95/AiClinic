import { ChevronDown } from 'lucide-react'
import { useState, useRef, useEffect } from 'react'
import type { Appointment, AppointmentStatus } from '../types'
import { STATUS_TRANSITIONS } from '../types'
import type { Doctor } from '../types'

type AppointmentRowActionsProps = {
  appointment: Appointment
  doctors: Doctor[]
  onTransition: (appointmentId: string, target: AppointmentStatus, doctorId?: string) => void
}

export function AppointmentRowActions({
  appointment,
  doctors,
  onTransition,
}: AppointmentRowActionsProps) {
  const [open, setOpen] = useState(false)
  const [showDoctorPicker, setShowDoctorPicker] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const transitions = STATUS_TRANSITIONS[appointment.status]

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false)
        setShowDoctorPicker(false)
      }
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  if (transitions.length === 0) return null

  const availableDoctors = doctors.filter((d) => d.status !== 'on_break')

  function handleAction(target: AppointmentStatus) {
    if (target === 'in_progress' && appointment.status === 'checked_in') {
      setShowDoctorPicker(true)
      return
    }
    onTransition(appointment.id, target)
    setOpen(false)
  }

  function handleDoctorSelect(doctorId: string) {
    onTransition(appointment.id, 'in_progress', doctorId)
    setOpen(false)
    setShowDoctorPicker(false)
  }

  return (
    <div className="relative" ref={ref} onClick={(e) => e.stopPropagation()}>
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-default px-2 py-1 text-xs font-medium text-text-primary transition-colors hover:border-border-focus hover:text-text-link focus:outline-none focus-visible:ring-2 focus-visible:ring-border-focus focus-visible:ring-offset-1"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={`Actions for ${appointment.patientName}`}
      >
        Actions
        <ChevronDown className="h-3 w-3" aria-hidden="true" />
      </button>

      {open && (
        <div
          className="absolute right-0 z-20 mt-1 min-w-[160px] rounded-lg border border-border-default bg-surface-default py-1 shadow-elevation-2"
          role="menu"
        >
          {showDoctorPicker ? (
            <>
              <p className="px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wide text-text-secondary">
                Assign Doctor
              </p>
              {availableDoctors.map((doc) => (
                <button
                  key={doc.id}
                  type="button"
                  role="menuitem"
                  onClick={() => handleDoctorSelect(doc.id)}
                  className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm hover:bg-surface-hover focus:bg-surface-hover focus:outline-none"
                >
                  <span
                    className={`h-2 w-2 rounded-full ${
                      doc.status === 'available' ? 'bg-status-success-fg' : 'bg-status-warning-fg'
                    }`}
                    aria-hidden="true"
                  />
                  {doc.name}
                </button>
              ))}
            </>
          ) : (
            transitions.map((t) => (
              <button
                key={t.target}
                type="button"
                role="menuitem"
                onClick={() => handleAction(t.target)}
                className={`flex w-full px-3 py-1.5 text-left text-sm hover:bg-surface-hover focus:bg-surface-hover focus:outline-none ${
                  t.variant === 'danger'
                    ? 'text-status-danger-fg'
                    : t.variant === 'success'
                      ? 'text-status-success-fg'
                      : 'text-text-primary'
                }`}
              >
                {t.label}
              </button>
            ))
          )}
        </div>
      )}
    </div>
  )
}
