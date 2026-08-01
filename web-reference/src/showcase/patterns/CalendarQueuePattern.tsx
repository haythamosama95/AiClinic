import { useMemo } from 'react'
import { AppointmentCard } from '@/components/card/EntityCards'
import { Calendar, type CalendarEvent } from '@/components/calendar/Calendar'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { MOCK_APPOINTMENTS } from './mock-data'
import { PatternFrame } from './PatternFrame'

export function CalendarQueuePattern() {
  const events: CalendarEvent[] = useMemo(
    () =>
      MOCK_APPOINTMENTS.filter((a) => a.status !== 'cancelled').map((a, i) => {
        const start = new Date(2026, 6, 4, 9 + i * 0.5, i % 2 === 0 ? 0 : 30)
        const end = new Date(start.getTime() + 30 * 60 * 1000)
        return {
          id: a.id,
          title: a.patient,
          start,
          end,
          patient: a.patient,
          doctor: a.doctor,
        }
      }),
    [],
  )

  const queueColumns = [
    { title: 'Waiting', items: MOCK_APPOINTMENTS.filter((a) => a.status === 'pending') },
    { title: 'In progress', items: [] as typeof MOCK_APPOINTMENTS },
    { title: 'Completed', items: MOCK_APPOINTMENTS.filter((a) => a.status === 'confirmed') },
  ]

  return (
    <ShowcaseSection
      id="pattern-calendar-queue"
      title="Calendar / Queue"
      componentName="05 §2 Board / Queue + Calendar"
      description="Appointment day view with time grid and queue board columns."
    >
      <PatternFrame>
        <div className="grid gap-6 p-4 lg:grid-cols-2 sm:p-6">
          <div>
            <SectionHeader title="Day schedule" description="Jul 4, 2026 · Downtown" />
            <Calendar events={events} view="day" className="mt-4" />
          </div>
          <div>
            <SectionHeader title="Queue board" description="Drag cards between columns in production." />
            <div className="mt-4 grid grid-cols-3 gap-3">
              {queueColumns.map((col) => (
                <div
                  key={col.title}
                  className="rounded-lg border border-border-default bg-surface-sunken p-2"
                >
                  <p className="mb-2 px-1 text-overline text-text-tertiary">{col.title}</p>
                  <div className="space-y-2">
                    {col.items.length === 0 ? (
                      <p className="px-1 py-4 text-center text-caption text-text-tertiary">Empty</p>
                    ) : (
                      col.items.map((a) => (
                        <AppointmentCard
                          key={a.id}
                          time={a.time}
                          patient={a.patient}
                          doctor={a.doctor}
                          status={a.status}
                          branch={a.branch}
                        />
                      ))
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
