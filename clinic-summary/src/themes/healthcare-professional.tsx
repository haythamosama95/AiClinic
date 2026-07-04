import type { ClinicSummary } from "@/lib/types";
import { formatDateLong, formatTimeRange, formatWait, formatTime, formatDuration } from "@/lib/format";
import { doctorAssignmentLabel, statusLabels, visitPhaseLabels, shiftStatusLabels } from "@/lib/labels";
import { getSummaryStats } from "@/lib/stats";
import { ThemeChrome } from "@/components/ThemeChrome";

export function HealthcareProfessionalTheme({ summary }: { summary: ClinicSummary }) {
  const stats = getSummaryStats(summary);

  return (
    <div className="min-h-screen bg-[#ECFEFF] font-[family-name:var(--font-noto)] text-[#164E63]">
      <div className="border-b border-[#0891B2]/15 bg-white">
        <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3 sm:px-6">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#0891B2] text-sm font-bold text-white">
            AC
          </div>
          <span className="font-[family-name:var(--font-figtree)] text-lg font-semibold">
            AiClinic
          </span>
          <span className="ml-auto text-sm text-[#64748B]">Front desk summary</span>
        </div>
      </div>

      <div className="mx-auto max-w-6xl px-4 py-8 sm:px-6">
        <ThemeChrome themeName="Healthcare Professional" className="mb-6 text-[#64748B]" />

        <header className="rounded-xl border border-[#0891B2]/20 bg-white p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-wider text-[#0891B2]">
            Summary stats
          </p>
          <h1 className="mt-1 font-[family-name:var(--font-figtree)] text-2xl font-semibold">
            Today&apos;s clinic
          </h1>
          <p className="text-sm text-[#64748B]">{formatDateLong(summary.date)}</p>
          <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
            {[
              ["Appointments", stats.appointmentCount],
              ["In progress", stats.inProgress],
              ["Waiting", stats.waiting],
              ["On shift", stats.onShift],
            ].map(([label, val]) => (
              <div key={label as string} className="rounded-lg bg-[#F0FDFA] px-4 py-3 ring-1 ring-[#0891B2]/10">
                <p className="font-[family-name:var(--font-figtree)] text-2xl font-bold text-[#0891B2]">
                  {val}
                </p>
                <p className="text-xs font-medium text-[#64748B]">{label}</p>
              </div>
            ))}
          </div>
        </header>

        <main className="mt-8 grid gap-6 lg:grid-cols-12">
          <section className="rounded-xl border border-[#E2E8F0] bg-white shadow-sm lg:col-span-7">
            <div className="border-b border-[#E2E8F0] px-5 py-4">
              <h2 className="font-[family-name:var(--font-figtree)] font-semibold">Appointments</h2>
              <p className="text-sm text-[#64748B]">Every visit scheduled for today</p>
            </div>
            <div className="p-4">
              {summary.appointments.length === 0 ? (
                <p className="py-12 text-center text-[#64748B]">No appointments today</p>
              ) : (
                <ul className="space-y-3">
                  {summary.appointments.map((a) => (
                    <li
                      key={a.id}
                      className="rounded-lg border border-[#E2E8F0] p-4 hover:border-[#0891B2]/30"
                    >
                      <div className="flex gap-4">
                        <time className="w-24 shrink-0 text-sm font-medium tabular-nums text-[#0891B2]">
                          {formatTimeRange(a.startTime, a.endTime)}
                        </time>
                        <div>
                          <div className="flex flex-wrap gap-2">
                            <span className="rounded-full bg-[#ECFEFF] px-2.5 py-0.5 text-xs font-medium text-[#0E7490] ring-1 ring-[#0891B2]/20">
                              {statusLabels[a.status]}
                            </span>
                            <span className="rounded-full bg-[#F1F5F9] px-2.5 py-0.5 text-xs text-[#64748B]">
                              {visitPhaseLabels[a.visitPhase]}
                            </span>
                          </div>
                          <p className="mt-2 font-[family-name:var(--font-figtree)] font-semibold">
                            {a.patientName}
                          </p>
                          <p className="text-sm text-[#64748B]">{a.appointmentType}</p>
                          <p className="mt-2 text-sm">
                            {doctorAssignmentLabel(a.doctorName, a.doctorOnShift)}
                            {a.patientChoseDoctor && a.doctorName && (
                              <span className="ml-1 text-xs font-medium text-[#059669]">
                                · Patient&apos;s choice
                              </span>
                            )}
                          </p>
                          {a.waitMinutes !== undefined && (
                            <p className="mt-1 text-xs font-medium text-[#D97706]">
                              Waiting {formatWait(a.waitMinutes)}
                            </p>
                          )}
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </section>

          <div className="flex flex-col gap-6 lg:col-span-5">
            <section className="rounded-xl border border-[#E2E8F0] bg-white shadow-sm">
              <div className="border-b border-[#E2E8F0] px-5 py-4">
                <h2 className="font-[family-name:var(--font-figtree)] font-semibold">
                  Doctors on shift
                </h2>
              </div>
              <div className="p-4">
                {summary.doctors.length === 0 ? (
                  <p className="py-8 text-center text-sm text-[#64748B]">No doctors on shift</p>
                ) : (
                  <ul className="space-y-3">
                    {summary.doctors.map((d) => (
                      <li key={d.id} className="rounded-lg bg-[#F8FAFC] p-4">
                        <p className="font-semibold">{d.name}</p>
                        <p className="text-xs text-[#059669]">{shiftStatusLabels[d.shiftStatus]}</p>
                        <p className="mt-1 text-sm text-[#64748B]">
                          {d.currentPatient ?? (
                            <span className="text-[#059669]">Available · no patient in progress</span>
                          )}
                          {d.sessionMinutes !== undefined && ` · ${formatDuration(d.sessionMinutes)}`}
                        </p>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </section>

            <section className="rounded-xl border border-[#0891B2]/20 bg-white shadow-sm">
              <div className="flex items-center justify-between border-b border-[#E2E8F0] px-5 py-4">
                <h2 className="font-[family-name:var(--font-figtree)] font-semibold">Checked in</h2>
                <span className="rounded-full bg-[#0891B2] px-3 py-1 text-sm font-semibold text-white">
                  {stats.waiting} waiting
                </span>
              </div>
              <div className="p-4">
                {summary.waitingRoom.length === 0 ? (
                  <p className="py-8 text-center text-sm text-[#64748B]">Waiting room is clear</p>
                ) : (
                  <ul className="space-y-3">
                    {summary.waitingRoom.map((w) => (
                      <li key={w.id} className="rounded-lg border border-[#E2E8F0] p-4">
                        <div className="flex justify-between">
                          <p className="font-semibold">{w.patientName}</p>
                          <span className="text-sm font-medium text-[#D97706]">
                            {formatWait(w.waitMinutes)}
                          </span>
                        </div>
                        <p className="mt-1 text-sm text-[#64748B]">
                          {doctorAssignmentLabel(w.doctorName, true)} · Scheduled{" "}
                          {formatTime(w.scheduledTime)}
                        </p>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </section>
          </div>
        </main>
      </div>
    </div>
  );
}
