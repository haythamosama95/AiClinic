import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

export function Material3Theme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="min-h-screen bg-[#FFFBFE] font-[family-name:var(--font-roboto)] text-[#1C1B1F]">
      <div className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
        <ThemeChrome themeName="Material 3" className="mb-6 text-[#79747E]" />

        <header className="mb-6 rounded-[28px] bg-[#EADDFF] px-6 py-8">
          <p className="text-sm font-medium text-[#6750A4]">{formatDateLong(summary.date)}</p>
          <h1 className="mt-2 text-3xl font-normal tracking-tight text-[#21005D]">
            Clinic summary
          </h1>
          <div className="mt-6 flex flex-wrap gap-3">
            {[
              ["Appointments", stats.appointmentCount, "bg-[#E8DEF8] text-[#1D192B]"],
              ["In progress", stats.inProgress, "bg-[#FFD8E4] text-[#31111D]"],
              ["Waiting", stats.waiting, "bg-[#FFD8E4] text-[#31111D]"],
              ["On shift", stats.onShift, "bg-[#D0BCFF] text-[#381E72]"],
            ].map(([label, val, colors]) => (
              <div
                key={label as string}
                className={`rounded-2xl px-5 py-4 ${colors}`}
              >
                <p className="text-2xl font-medium">{val}</p>
                <p className="text-xs font-medium opacity-80">{label}</p>
              </div>
            ))}
          </div>
        </header>

        <div className="grid gap-6 lg:grid-cols-12">
          <section className="rounded-[28px] bg-[#F3EDF7] p-6 lg:col-span-7">
            <h2 className="text-xl font-normal text-[#1C1B1F]">Appointments</h2>
            {summary.appointments.length === 0 ? (
              <p className="mt-8 text-center text-[#79747E]">No appointments today</p>
            ) : (
              <ul className="mt-4 space-y-3">
                {summary.appointments.map((a) => (
                  <li
                    key={a.id}
                    className="rounded-2xl bg-[#FFFBFE] p-4 shadow-[0_1px_2px_rgba(0,0,0,0.1),0_1px_3px_rgba(0,0,0,0.08)] transition hover:shadow-md"
                  >
                    <div className="flex gap-4">
                      <time className="shrink-0 text-sm font-medium text-[#6750A4]">
                        {formatTimeRange(a.startTime, a.endTime)}
                      </time>
                      <div>
                        <p className="font-medium">{a.patientName}</p>
                        <p className="text-sm text-[#49454F]">{a.appointmentType}</p>
                        <div className="mt-2 flex flex-wrap gap-2">
                          <span className="rounded-lg bg-[#E8DEF8] px-3 py-1 text-xs font-medium text-[#381E72]">
                            {statusLabels[a.status]}
                          </span>
                          <span className="rounded-lg bg-[#E7E0EC] px-3 py-1 text-xs text-[#49454F]">
                            {visitPhaseLabels[a.visitPhase]}
                          </span>
                        </div>
                        <p className="mt-2 text-sm text-[#49454F]">
                          {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                          {a.patientChoseDoctor && a.doctorName && " · Patient's choice"}
                        </p>
                        {a.waitMinutes !== undefined && (
                          <p className="mt-1 text-xs font-medium text-[#7D5260]">
                            Waiting {formatWait(a.waitMinutes)}
                          </p>
                        )}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <div className="flex flex-col gap-6 lg:col-span-5">
            <section className="rounded-[28px] bg-[#E8DEF8] p-6">
              <h2 className="text-xl font-normal text-[#1D192B]">Doctors on shift</h2>
              {summary.doctors.length === 0 ? (
                <p className="mt-4 text-sm text-[#49454F]">No doctors on shift</p>
              ) : (
                <ul className="mt-4 space-y-3">
                  {summary.doctors.map((d) => (
                    <li key={d.id} className="rounded-2xl bg-[#FFFBFE] p-4">
                      <p className="font-medium">{d.name}</p>
                      <span className="mt-1 inline-block rounded-lg bg-[#D0BCFF] px-2 py-0.5 text-xs text-[#381E72]">
                        {shiftStatusLabels[d.shiftStatus]}
                      </span>
                      <p className="mt-2 text-sm text-[#49454F]">
                        {d.currentPatient ?? "Available · no patient in progress"}
                        {d.sessionMinutes !== undefined && ` · ${formatDuration(d.sessionMinutes)}`}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </section>

            <section className="rounded-[28px] bg-[#FFD8E4] p-6">
              <div className="flex items-center justify-between">
                <h2 className="text-xl font-normal text-[#31111D]">Checked in</h2>
                <span className="flex h-10 w-10 items-center justify-center rounded-full bg-[#7D5260] text-sm font-medium text-white">
                  {stats.waiting}
                </span>
              </div>
              {summary.waitingRoom.length === 0 ? (
                <p className="mt-4 text-sm text-[#49454F]">Waiting room is clear</p>
              ) : (
                <ul className="mt-4 space-y-3">
                  {summary.waitingRoom.map((w) => (
                    <li key={w.id} className="rounded-2xl bg-[#FFFBFE] p-4">
                      <div className="flex justify-between">
                        <p className="font-medium">{w.patientName}</p>
                        <span className="text-sm font-medium text-[#7D5260]">
                          {formatWait(w.waitMinutes)}
                        </span>
                      </div>
                      <p className="mt-1 text-sm text-[#49454F]">
                        {doctorAssignmentLabel(w.doctorName, true)} · {formatTime(w.scheduledTime)}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </div>
        </div>
      </div>
    </div>
  );
}
