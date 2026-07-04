import type { ClinicSummary } from "@/lib/types";
import { AppointmentCard } from "@/components/AppointmentCard";
import { DoctorCard } from "@/components/DoctorCard";
import { EmptyState } from "@/components/EmptyState";
import { Panel } from "@/components/Panel";
import { SummaryHeader } from "@/components/SummaryHeader";
import { ThemeChrome } from "@/components/ThemeChrome";
import { WaitingPatientCard } from "@/components/WaitingPatientCard";

export function ModernSaasTheme({ summary }: { summary: ClinicSummary }) {
  const { appointments, doctors, waitingRoom } = summary;

  return (
    <div className="min-h-screen bg-canvas">
      <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
        <ThemeChrome themeName="Modern SaaS" className="mb-4 text-muted" />
        <SummaryHeader summary={summary} />

        <main className="mt-6 grid gap-6 lg:grid-cols-12 lg:gap-8">
          <div className="lg:col-span-7">
            <Panel title="Appointments" description="Every visit scheduled for today">
              {appointments.length === 0 ? (
                <EmptyState
                  title="No appointments today"
                  description="When patients are booked in, they'll show up here with status, doctor assignment, and visit phase."
                />
              ) : (
                <ul className="space-y-3" role="list">
                  {appointments.map((appointment) => (
                    <li key={appointment.id}>
                      <AppointmentCard appointment={appointment} />
                    </li>
                  ))}
                </ul>
              )}
            </Panel>
          </div>

          <div className="flex flex-col gap-6 lg:col-span-5">
            <Panel title="Doctors on shift" description="Who is working right now">
              {doctors.length === 0 ? (
                <EmptyState
                  title="No doctors on shift"
                  description="Shift assignments will appear here when the clinic opens."
                />
              ) : (
                <ul className="space-y-3" role="list">
                  {doctors.map((doctor) => (
                    <li key={doctor.id}>
                      <DoctorCard doctor={doctor} />
                    </li>
                  ))}
                </ul>
              )}
            </Panel>

            <Panel
              title="Checked in"
              description="Patients in the waiting room"
              count={waitingRoom.length}
              countLabel="waiting"
            >
              {waitingRoom.length === 0 ? (
                <EmptyState
                  title="Waiting room is clear"
                  description="Checked-in patients will appear here with their doctor preference and wait time."
                />
              ) : (
                <ul className="space-y-3" role="list">
                  {waitingRoom.map((patient) => (
                    <li key={patient.id}>
                      <WaitingPatientCard patient={patient} />
                    </li>
                  ))}
                </ul>
              )}
            </Panel>
          </div>
        </main>

        <footer className="mt-8 pb-4 text-center text-xs text-muted">
          AiClinic · front-desk summary view
        </footer>
      </div>
    </div>
  );
}
