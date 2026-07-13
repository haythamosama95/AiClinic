import { CalendarPlus } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Badge } from '@/components/badge'
import { AppointmentCard } from '@/components/card/EntityCards'
import { PageHeader } from '@/components/layout/PageHeader'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { MOCK_PATIENTS, patientFullName } from '@/data/patients'
import { BookAppointmentDialog } from './BookAppointmentDialog'
import {
  getBranchById,
  getDoctorById,
  MOCK_BOOKINGS,
  SLOT_LABELS,
} from './mock-data'
import { formatFullDate } from './slot-availability'

export function AppointmentsPage() {
  const [bookOpen, setBookOpen] = useState(false)

  const upcoming = MOCK_BOOKINGS.slice(0, 4).map((b) => {
    const patient = MOCK_PATIENTS.find((p) => p.id === b.patientId)
    const doctor = getDoctorById(b.doctorId)
    const branch = getBranchById(b.branchId)
    return {
      id: `${b.branchId}-${b.date}-${b.time}-${b.doctorId}`,
      time: SLOT_LABELS[b.time as keyof typeof SLOT_LABELS],
      patient: patient ? patientFullName(patient) : 'Unknown',
      doctor: doctor?.fullName ?? '—',
      status: 'confirmed' as const,
      branch: branch?.name ?? '—',
      date: b.date,
    }
  })

  return (
    <>
      <PageHeader
        title="Appointments"
        description="Schedule, confirm, and track patient appointments."
        actions={
          <Button
            variant="primary"
            leadingIcon={<CalendarPlus size={16} />}
            onClick={() => setBookOpen(true)}
          >
            Book appointment
          </Button>
        }
      />

      <div className="mt-8 space-y-8">
        <section>
          <SectionHeader
            title="Today"
            description="Jul 13, 2026 · Downtown Clinic"
            actions={
              <Badge color="info" variant="soft">
                {upcoming.length} scheduled
              </Badge>
            }
          />
          <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {upcoming.map((appt) => (
              <AppointmentCard
                key={appt.id}
                time={appt.time}
                patient={appt.patient}
                doctor={appt.doctor}
                status={appt.status}
                branch={appt.branch}
              />
            ))}
          </div>
        </section>

        <section className="rounded-xl border border-dashed border-border-default bg-surface-default p-6 text-center">
          <p className="text-body text-text-secondary">
            Calendar day view and queue board will appear here. Use{' '}
            <button
              type="button"
              className="font-medium text-action-primary underline-offset-2 hover:underline"
              onClick={() => setBookOpen(true)}
            >
              Book appointment
            </button>{' '}
            to schedule a new visit — {formatFullDate('2026-07-13')} slots are live in the demo.
          </p>
        </section>
      </div>

      <BookAppointmentDialog open={bookOpen} onOpenChange={setBookOpen} />
    </>
  )
}
